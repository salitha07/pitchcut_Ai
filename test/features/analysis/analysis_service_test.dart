import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/data/caption_repository.dart';
import 'package:pitchcut_ai/data/project_repository.dart';
import 'package:pitchcut_ai/data/report_repository.dart';
import 'package:pitchcut_ai/features/analysis/analysis_service.dart';
import 'package:pitchcut_ai/features/analysis/face_frame_service.dart';
import 'package:pitchcut_ai/models/caption.dart';
import 'package:pitchcut_ai/models/clip.dart';
import 'package:pitchcut_ai/models/performance_report.dart';

import '../../fakes/fake_editor_engine.dart';

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(this.clips);

  final List<Clip> clips;

  @override
  Future<List<Clip>> getClips(String projectId) async => clips;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCaptionRepository implements CaptionRepository {
  _FakeCaptionRepository(this.captions);

  final List<Caption> captions;

  @override
  Future<List<Caption>> getCaptions(String projectId) async => captions;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeReportRepository implements ReportRepository {
  PerformanceReport? savedReport;

  @override
  Future<void> saveReport(PerformanceReport report) async {
    savedReport = report;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyFaceFrameService extends FaceFrameService {
  @override
  Future<List<String>> extractFrames(
    String videoPath, {
    int intervalMs = 1000,
  }) async {
    return [];
  }
}

void main() {
  test('caption text and timestamps feed the saved pace score', () async {
    final clip = Clip(
      id: 'clip-1',
      projectId: 'project-1',
      localPath: '/fake/video.mp4',
      durationMs: 60000,
      width: 1920,
      height: 1080,
      order: 0,
    );

    final captions = [
      Caption(
        id: 'caption-1',
        startMs: 0,
        endMs: 60000,
        text: List.filled(120, 'word').join(' '),
      ),
    ];

    final reportRepository = _FakeReportRepository();

    final service = AnalysisService(
      projectRepository: _FakeProjectRepository([clip]),
      captionRepository: _FakeCaptionRepository(captions),
      reportRepository: reportRepository,
      editorEngine: FakeEditorEngine(delay: Duration.zero),
      faceFrameService: _EmptyFaceFrameService(),
    );

    final report = await service.analyseProject('project-1');

    expect(report.paceScore, 100);
    expect(report.score, 100);
    expect(reportRepository.savedReport, isNotNull);
    expect(reportRepository.savedReport!.paceScore, 100);
  });
}
