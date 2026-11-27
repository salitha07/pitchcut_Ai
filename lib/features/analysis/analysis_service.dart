import 'package:flutter/foundation.dart';

import '../../data/caption_repository.dart';
import '../../data/project_repository.dart';
import '../../data/report_repository.dart';
import '../../features/editor/engine/editor_engine.dart';
import '../../models/caption.dart';
import '../../models/clip.dart';
import '../../models/pause_segment.dart';
import '../../models/performance_report.dart';
import 'face_frame_service.dart';
import 'face_position_service.dart';
import 'pause_detection_service.dart';
import 'speaking_pace_service.dart';
import 'stability_analysis_service.dart';

class AnalysisService {
  AnalysisService({
    required this.projectRepository,
    required this.captionRepository,
    required this.reportRepository,
    required this.editorEngine,
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

  final ProjectRepository projectRepository;
  final CaptionRepository captionRepository;
  final ReportRepository reportRepository;
  final EditorEngine editorEngine;

  final FaceFrameService _faceFrameService;
  final FacePositionService _facePositionService;
  final PauseDetectionService _pauseDetectionService;
  final SpeakingPaceService _speakingPaceService;
  final StabilityAnalysisService _stabilityAnalysisService;

  /// Analyses one original video clip independently.
  Future<PerformanceReport> analyseVideo(
    String projectId,
    String clipId,
  ) async {
    final clips = await projectRepository.getClips(projectId);

    final matchingClips = clips.where((clip) => clip.id == clipId).toList();

    if (matchingClips.isEmpty) {
      throw StateError('The selected video was not found in this project.');
    }

    final clip = matchingClips.first;
    final allCaptions = await captionRepository.getCaptions(projectId);

    // Only captions explicitly mapped to this original source clip.
    // Legacy unmapped captions are accepted only for single-clip projects.
    final videoCaptions = _getCaptionsForVideo(
      allCaptions,
      clip,
      allowLegacyCaptions: clips.length == 1,
    );

    final result = await _analyseClips([clip], videoCaptions);

    final report = PerformanceReport(
      id: _createReportId(),
      projectId: projectId,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      score: result.score,
      pauses: result.pauses,
      faceScore: result.faceScore,
      stabilityScore: result.stabilityScore,
      paceScore: result.paceScore,
      tips: result.tips,
      reportType: 'video',
      clipId: clip.id,
    );

    await reportRepository.saveReport(report);

    return report;
  }

  /// Analyses all videos in a project together.
  Future<PerformanceReport> analyseProject(String projectId) async {
    final clips = await projectRepository.getClips(projectId);

    if (clips.isEmpty) {
      throw StateError('This project has no video clips to analyse.');
    }

    final captions = await captionRepository.getCaptions(projectId);

    final result = await _analyseClips(clips, captions);

    final report = PerformanceReport(
      id: _createReportId(),
      projectId: projectId,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      score: result.score,
      pauses: result.pauses,
      faceScore: result.faceScore,
      stabilityScore: result.stabilityScore,
      paceScore: result.paceScore,
      tips: result.tips,
      reportType: 'project',
    );

    await reportRepository.saveReport(report);

    return report;
  }

  /// Filters captions by their original video identity.
  List<Caption> _getCaptionsForVideo(
    List<Caption> captions,
    Clip clip, {
    required bool allowLegacyCaptions,
  }) {
    final matchingCaptions = <Caption>[];

    for (final caption in captions) {
      if (caption.sourceClipId == clip.id) {
        final sourceStartMs = caption.sourceStartMs;

        // Without an original source timestamp, timeline timestamps
        // cannot safely be used for individual video pace analysis.
        if (sourceStartMs == null || sourceStartMs < 0) continue;

        final durationMs = caption.endMs - caption.startMs;

        if (durationMs <= 0) continue;

        matchingCaptions.add(
          Caption(
            id: caption.id,
            startMs: sourceStartMs,
            endMs: sourceStartMs + durationMs,
            text: caption.text,
            sourceClipId: caption.sourceClipId,
            sourceStartMs: sourceStartMs,
          ),
        );
      } else if (caption.sourceClipId == null && allowLegacyCaptions) {
        // Backward compatibility for old single-video projects.
        matchingCaptions.add(caption);
      }
    }

    return matchingCaptions;
  }

  Future<_AnalysisResult> _analyseClips(
    List<Clip> clips,
    List<Caption> captions,
  ) async {
    final allPauses = <PauseSegment>[];
    final faceScores = <int>[];
    final stabilityScores = <int>[];

    var pauseAnalysisAvailable = false;

    for (var clipIndex = 0; clipIndex < clips.length; clipIndex++) {
      final clip = clips[clipIndex];

      try {
        final samples = await editorEngine.getLoudnessSamples(clip.localPath);

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

    return _AnalysisResult(
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
  }

  static String _createReportId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
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

class _AnalysisResult {
  const _AnalysisResult({
    required this.score,
    required this.pauses,
    required this.faceScore,
    required this.stabilityScore,
    required this.paceScore,
    required this.tips,
  });

  final int score;
  final List<PauseSegment> pauses;
  final int? faceScore;
  final int? stabilityScore;
  final int? paceScore;
  final List<String> tips;
}
