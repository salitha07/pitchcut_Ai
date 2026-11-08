import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pitchcut_ai/features/editor/engine/editor_engine.dart';

import '../../fakes/fake_editor_engine.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/models/video_clip.dart';
import 'package:pitchcut_ai/features/editor/video_editor_screen.dart';
import 'package:pitchcut_ai/features/editor/video_export_screen.dart';
import 'package:pitchcut_ai/features/editor/services/video_export_service.dart';

// Keep widget tests independent of platform-channel scheduling; service tests
// exercise this same adapter against the real shared method/event channels.
class _PlayableSharedExportService extends VideoExportService {
  _PlayableSharedExportService({required super.engine});

  @override
  Future<bool> verifyOutput(String path) async => true;
}

class _UiTimelineEngine extends FakeEditorEngine {
  late StreamController<ExportEvent> events;
  int? targetHeight;
  int cancellations = 0;

  @override
  Stream<ExportEvent> exportTimeline({
    required List<EditorTimelineItem> items,
    required int targetHeight,
  }) {
    this.targetHeight = targetHeight;
    events = StreamController<ExportEvent>();
    return events.stream;
  }

  @override
  Future<void> cancelExport() async {
    cancellations++;
    events.addError(PlatformException(code: 'CANCELLED', message: 'Cancelled'));
    unawaited(events.close());
  }
}

void main() {
  const clip = VideoClip(
    path: '/recordings/scene.mp4',
    name: 'scene.mp4',
    duration: Duration(seconds: 45),
  );

  test('video editor widget remains available for navigation to Export', () {
    const editor = VideoEditorScreen(videoPath: '/recordings/scene.mp4');
    expect(editor.videoPath, '/recordings/scene.mp4');
  });

  testWidgets('shows timeline details and updates estimated quality settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VideoExportScreen(
          clips: [clip],
          duration: Duration(seconds: 45),
          sourceAspectRatio: 16 / 9,
        ),
      ),
    );

    expect(find.text('scene.mp4'), findsOneWidget);
    expect(find.text('0:45'), findsOneWidget);
    expect(find.text('MP4'), findsOneWidget);
    expect(find.text('1280 × 720 (720p)'), findsOneWidget);

    await tester.tap(find.text('1080p'));
    await tester.pump();
    expect(find.text('1920 × 1080 (1080p)'), findsOneWidget);
  });

  testWidgets('Export action streams engine progress and opens success', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = _UiTimelineEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoExportScreen(
          clips: const [clip],
          duration: clip.duration,
          sourceAspectRatio: 16 / 9,
          backend: _PlayableSharedExportService(engine: engine),
        ),
      ),
    );
    await tester.tap(find.text('480p'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('start-video-export')));
    await tester.pump();
    expect(engine.targetHeight, 480);
    engine.events.add(ExportEvent(0.4));
    await tester.pump();
    expect(find.text('40% exported'), findsOneWidget);
    expect(find.byKey(const ValueKey('cancel-video-export')), findsOneWidget);
    engine.events.add(const ExportEvent(1, '/cache/shared-output.mp4'));
    unawaited(engine.events.close());
    await tester.pumpAndSettle();
    expect(find.text('Video exported successfully'), findsOneWidget);
    expect(find.text('/cache/shared-output.mp4'), findsOneWidget);
  });

  testWidgets('shared cancellation and errors allow another export attempt', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = _UiTimelineEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoExportScreen(
          clips: const [clip],
          duration: clip.duration,
          sourceAspectRatio: 16 / 9,
          backend: _PlayableSharedExportService(engine: engine),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('start-video-export')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cancel-video-export')));
    await tester.pumpAndSettle();
    expect(engine.cancellations, 1);
    expect(find.text('Export cancelled. No output was kept.'), findsOneWidget);
    await tester.tap(find.text('Export again'));
    await tester.pump();
    engine.events.addError(
      PlatformException(
        code: 'EXPORT_FAILED',
        message: 'Device encoder failed',
      ),
    );
    unawaited(engine.events.close());
    await tester.pumpAndSettle();
    expect(find.text('Device encoder failed'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    engine.events.add(const ExportEvent(1, '/cache/retried.mp4'));
    unawaited(engine.events.close());
    await tester.pumpAndSettle();
    expect(find.text('Video exported successfully'), findsOneWidget);
  });
}
