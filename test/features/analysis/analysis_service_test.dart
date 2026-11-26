
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

Clip _createClip(String id, int order) {
  return Clip(
    id: id,
    projectId: 'project-1',
    localPath: '/fake/$id.mp4',
    durationMs: 60000,
    width: 1920,
    height: 1080,
    order: order,
  );
}

Caption _createCaption({
  required String id,
  required String clipId,
  required int wordCount,
}) {
  return Caption(
    id: id,
    startMs: 0,
    endMs: 60000,
    text: List.filled(wordCount, 'word').join(' '),
    sourceClipId: clipId,
    sourceStartMs: 0,
  );
}

AnalysisService _createService({
  required List<Clip> clips,
  required List<Caption> captions,
  required _FakeReportRepository reportRepository,
}) {
  return AnalysisService(
    projectRepository: _FakeProjectRepository(clips),
    captionRepository: _FakeCaptionRepository(captions),
    reportRepository: reportRepository,
    editorEngine: FakeEditorEngine(delay: Duration.zero),
    faceFrameService: _EmptyFaceFrameService(),
  );
}

void main() {
  test('caption text and timestamps feed the saved pace score', () async {
    final clip = _createClip('clip-1', 0);

    final captions = [
      Caption(
        id: 'caption-1',
        startMs: 0,
        endMs: 60000,
        text: List.filled(120, 'word').join(' '),
      ),
    ];

    final reportRepository = _FakeReportRepository();

    final service = _createService(
      clips: [clip],
      captions: captions,
      reportRepository: reportRepository,
    );

    final report = await service.analyseProject('project-1');

    expect(report.paceScore, 100);
    expect(report.score, 100);
    expect(reportRepository.savedReport, isNotNull);
    expect(reportRepository.savedReport!.paceScore, 100);
  });

  test('analyseVideo analyses only the selected video captions', () async {
    final clip1 = _createClip('clip-1', 0);
    final clip2 = _createClip('clip-2', 1);

    final captions = [
      _createCaption(
        id: 'caption-1',
        clipId: 'clip-1',
        wordCount: 120,
      ),
      _createCaption(
        id: 'caption-2',
        clipId: 'clip-2',
        wordCount: 10,
      ),
    ];

    final reportRepository = _FakeReportRepository();

    final service = _createService(
      clips: [clip1, clip2],
      captions: captions,
      reportRepository: reportRepository,
    );

    final report = await service.analyseVideo('project-1', 'clip-1');

    expect(report.paceScore, 100);
    expect(report.reportType, 'video');
    expect(report.clipId, 'clip-1');

    expect(reportRepository.savedReport, isNotNull);
    expect(reportRepository.savedReport!.clipId, 'clip-1');
    expect(reportRepository.savedReport!.reportType, 'video');
  });

  test('analyseVideo uses captions belonging to the second video', () async {
    final clip1 = _createClip('clip-1', 0);
    final clip2 = _createClip('clip-2', 1);

    final captions = [
      _createCaption(
        id: 'caption-1',
        clipId: 'clip-1',
        wordCount: 120,
      ),
      _createCaption(
        id: 'caption-2',
        clipId: 'clip-2',
        wordCount: 10,
      ),
    ];

    final reportRepository = _FakeReportRepository();

    final service = _createService(
      clips: [clip1, clip2],
      captions: captions,
      reportRepository: reportRepository,
    );

    final report = await service.analyseVideo('project-1', 'clip-2');

    expect(report.reportType, 'video');
    expect(report.clipId, 'clip-2');
    expect(report.paceScore, lessThan(100));
  });

  test('analyseVideo throws when the clip does not exist', () async {
    final reportRepository = _FakeReportRepository();

    final service = _createService(
      clips: [_createClip('clip-1', 0)],
      captions: [],
      reportRepository: reportRepository,
    );

    expect(
      () => service.analyseVideo('project-1', 'invalid-clip'),
      throwsA(isA<StateError>()),
    );
  });
}
