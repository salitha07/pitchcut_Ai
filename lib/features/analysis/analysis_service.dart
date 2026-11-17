import 'package:flutter/foundation.dart';

import '../../data/caption_repository.dart';
import '../../data/project_repository.dart';
import '../../data/report_repository.dart';
import '../../features/editor/engine/editor_engine.dart';
import '../../models/pause_segment.dart';
import '../../models/performance_report.dart';
import 'face_frame_service.dart';
import 'face_position_service.dart';
import 'pause_detection_service.dart';
import 'speaking_pace_service.dart';
import 'stability_analysis_service.dart';

class AnalysisService {
  AnalysisService({
    required this._projectRepository,
    required this._captionRepository,
    required this._reportRepository,
    required this._editorEngine,
    FaceFrameService? faceFrameService,
    FacePositionService? facePositionService,
    PauseDetectionService? pauseDetectionService,
    SpeakingPaceService? speakingPaceService,
    StabilityAnalysisService? stabilityAnalysisService,
  }) : _faceFrameService = faceFrameService ?? FaceFrameService(),
       _facePositionService =
           facePositionService ?? const FacePositionService(),
       _pauseDetectionService =
           pauseDetectionService ?? const PauseDetectionService(),
       _speakingPaceService =
           speakingPaceService ?? const SpeakingPaceService(),
       _stabilityAnalysisService =
           stabilityAnalysisService ?? const StabilityAnalysisService();

  final ProjectRepository _projectRepository;
  final CaptionRepository _captionRepository;
  final ReportRepository _reportRepository;
  final EditorEngine _editorEngine;
  final FaceFrameService _faceFrameService;
  final FacePositionService _facePositionService;
  final PauseDetectionService _pauseDetectionService;
  final SpeakingPaceService _speakingPaceService;
  final StabilityAnalysisService _stabilityAnalysisService;

  Future<PerformanceReport> analyseProject(String projectId) async {
    final clips = await _projectRepository.getClips(projectId);

    if (clips.isEmpty) {
      throw StateError('This project has no video clips to analyse.');
    }

    final captions = await _captionRepository.getCaptions(projectId);

    final allPauses = <PauseSegment>[];
    final faceScores = <int>[];
    final stabilityScores = <int>[];
    var pauseAnalysisAvailable = false;

    // Analyse each clip and preserve its identity for editor suggestions.
    for (var clipIndex = 0; clipIndex < clips.length; clipIndex++) {
      final clip = clips[clipIndex];

      try {
        final samples = await _editorEngine.getLoudnessSamples(clip.localPath);

        // Temporary diagnostics to inspect background noise levels.
        if (samples.isNotEmpty) {
          final sorted = List<double>.from(samples)..sort();

          double percentile(double p) {
            final index = ((sorted.length - 1) * p).round();
            return sorted[index];
          }

          debugPrint(
            'LOUDNESS DEBUG: '
            'min=${sorted.first}, '
            'p10=${percentile(0.10)}, '
            'p25=${percentile(0.25)}, '
            'median=${percentile(0.50)}, '
            'p75=${percentile(0.75)}, '
            'max=${sorted.last}',
          );
        } else {
          debugPrint('LOUDNESS DEBUG: No samples for ${clip.id}');
        }

        final detectedPauses = _pauseDetectionService.detectPauses(
          samples,
          minPauseMs: 2000,
        );

        allPauses.addAll(
          detectedPauses.map(
            (pause) => pause.copyWith(clipId: clip.id, clipIndex: clipIndex),
          ),
        );

        pauseAnalysisAvailable = true;
      } catch (error) {
        debugPrint('Pause analysis failed for ${clip.id}: $error');
      }

      try {
        final framePaths = await _faceFrameService.extractFrames(
          clip.localPath,
          intervalMs: 1000,
        );

        final score = await _facePositionService.analyseFrames(framePaths);

        if (score != null) {
          faceScores.add(score);
        }
      } catch (error) {
        debugPrint('Face analysis failed for ${clip.id}: $error');
      }

      try {
        final score = await _stabilityAnalysisService.analyse(clip);

        if (score != null) {
          stabilityScores.add(score);
        }
      } catch (error) {
        debugPrint('Stability analysis failed for ${clip.id}: $error');
      }
    }

    final paceScore = _speakingPaceService.calculateScore(captions);
    final faceScore = _average(faceScores);
    final stabilityScore = _average(stabilityScores);

    final pauseScore = pauseAnalysisAvailable
        ? _calculatePauseScore(allPauses)
        : null;

    final overallScore = calculateOverallScore(
      pauseScore: pauseScore,
      faceScore: faceScore,
      stabilityScore: stabilityScore,
      paceScore: paceScore,
    );

    if (overallScore == null) {
      throw StateError(
        'Analysis could not calculate a score. '
        'Please check the video, captions and sensor data.',
      );
    }

    final report = PerformanceReport(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      projectId: projectId,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      score: overallScore,
      pauses: allPauses,
      faceScore: faceScore,
      stabilityScore: stabilityScore,
      paceScore: paceScore,
      tips: _generateTips(
        allPauses: allPauses,
        faceScore: faceScore,
        stabilityScore: stabilityScore,
        paceScore: paceScore,
      ),
    );

    await _reportRepository.saveReport(report);

    return report;
  }

  static int? calculateOverallScore({
    required int? pauseScore,
    required int? faceScore,
    required int? stabilityScore,
    required int? paceScore,
  }) {
    const weights = {
      'pause': 30.0,
      'face': 25.0,
      'stability': 25.0,
      'pace': 20.0,
    };

    final scores = {
      'pause': pauseScore,
      'face': faceScore,
      'stability': stabilityScore,
      'pace': paceScore,
    };

    var weightedTotal = 0.0;
    var availableWeight = 0.0;

    for (final entry in scores.entries) {
      final score = entry.value;

      if (score == null) continue;

      weightedTotal += score.clamp(0, 100) * weights[entry.key]!;
      availableWeight += weights[entry.key]!;
    }

    if (availableWeight == 0) return null;

    return (weightedTotal / availableWeight).round().clamp(0, 100);
  }

  int _calculatePauseScore(List<PauseSegment> pauses) {
    final totalPauseMs = pauses.fold<int>(
      0,
      (total, pause) => total + pause.durationMs,
    );

    return (100 - (totalPauseMs / 1000 * 2)).round().clamp(0, 100);
  }

  int? _average(List<int> values) {
    if (values.isEmpty) return null;

    return (values.reduce((a, b) => a + b) / values.length).round().clamp(
      0,
      100,
    );
  }

  List<String> _generateTips({
    required List<PauseSegment> allPauses,
    required int? faceScore,
    required int? stabilityScore,
    required int? paceScore,
  }) {
    final tips = <String>[];

    if (allPauses.isNotEmpty) {
      tips.add('Review long pauses to improve presentation flow.');
    }

    if (faceScore != null && faceScore < 70) {
      tips.add('Keep your face centred and maintain a consistent position.');
    }

    if (stabilityScore != null && stabilityScore < 70) {
      tips.add('Keep your phone steady while recording.');
    }

    if (paceScore != null && paceScore < 70) {
      tips.add('Practise speaking at a more consistent pace.');
    }

    if (tips.isEmpty) {
      tips.add('Good work! Keep practising to improve your presentation.');
    }

    return tips.take(3).toList();
  }
}
