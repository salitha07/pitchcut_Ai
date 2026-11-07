import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/models/video_clip.dart';
import 'package:pitchcut_ai/features/editor/models/video_export_state.dart';
import 'package:pitchcut_ai/features/editor/services/video_export_controller.dart';

const _clip = VideoClip(
  path: '/recorded/source.mp4',
  name: 'source.mp4',
  duration: Duration(seconds: 6),
);

class _FakeExportBackend implements VideoExportBackend {
  final exportCompleter = Completer<String>();
  final verificationCompleter = Completer<bool>();
  ExportProgressCallback? progressCallback;
  int verifyCalls = 0;
  int cancelCalls = 0;
  final discarded = <String>[];
  Object? exportError;

  @override
  Future<String> exportTimeline(
    List<VideoClip> clips,
    VideoExportQuality quality, {
    required ExportProgressCallback onProgress,
  }) {
    progressCallback = onProgress;
    if (exportError != null) return Future.error(exportError!);
    return exportCompleter.future;
  }

  @override
  Future<void> cancelExport() async {
    cancelCalls++;
    if (!exportCompleter.isCompleted) {
      exportCompleter.completeError(const VideoExportCancelled());
    }
  }

  @override
  Future<bool> verifyOutput(String path) {
    verifyCalls++;
    return verificationCompleter.future;
  }

  @override
  Future<void> discardOutput(String path) async {
    discarded.add(path);
  }
}

void main() {
  test(
    'reports success only after the output verifier accepts the file',
    () async {
      final backend = _FakeExportBackend();
      final controller = VideoExportController(backend: backend);
      final operation = controller.start([_clip], VideoExportQuality.p720);

      expect(controller.state.status, VideoExportStatus.exporting);
      backend.progressCallback!(0.3);
      expect(controller.state.progress, 0.3);
      backend.exportCompleter.complete('/output/final.mp4');
      await Future<void>.delayed(Duration.zero);
      expect(backend.verifyCalls, 1);
      expect(controller.state.status, VideoExportStatus.exporting);

      backend.verificationCompleter.complete(true);
      await operation;
      expect(controller.state.status, VideoExportStatus.succeeded);
      expect(controller.state.progress, 1);
      expect(controller.state.outputPath, '/output/final.mp4');
      controller.dispose();
    },
  );

  test('reports verification failures instead of success', () async {
    final backend = _FakeExportBackend()..verificationCompleter.complete(false);
    final controller = VideoExportController(backend: backend);
    final operation = controller.start([_clip], VideoExportQuality.p1080);
    backend.exportCompleter.complete('/output/corrupt.mp4');
    await operation;

    expect(controller.state.status, VideoExportStatus.failed);
    expect(controller.state.errorMessage, contains('verified as playable'));
    expect(controller.state.outputPath, isNull);
    expect(backend.discarded, ['/output/corrupt.mp4']);
    controller.dispose();
  });

  test('cancels native work and enters a cancelled state', () async {
    final backend = _FakeExportBackend();
    final controller = VideoExportController(backend: backend);
    final operation = controller.start([_clip], VideoExportQuality.p480);
    final cancelling = controller.cancel();

    expect(controller.state.status, VideoExportStatus.cancelling);
    await cancelling;
    await operation;
    expect(backend.cancelCalls, 1);
    expect(controller.state.status, VideoExportStatus.cancelled);
    controller.dispose();
  });

  test('surfaces exporter errors and allows a later attempt', () async {
    final backend = _FakeExportBackend()
      ..exportError = StateError('encoder failed');
    final controller = VideoExportController(backend: backend);
    await controller.start([_clip], VideoExportQuality.p720);

    expect(controller.state.status, VideoExportStatus.failed);
    expect(controller.state.errorMessage, 'encoder failed');
    controller.dispose();
  });

  test(
    'cancelling during output verification removes the completed file',
    () async {
      final backend = _FakeExportBackend();
      final controller = VideoExportController(backend: backend);
      final operation = controller.start([_clip], VideoExportQuality.p720);
      backend.exportCompleter.complete('/output/just-finished.mp4');
      await Future<void>.delayed(Duration.zero);
      expect(backend.verifyCalls, 1);

      await controller.cancel();
      backend.verificationCompleter.complete(true);
      await operation;

      expect(controller.state.status, VideoExportStatus.cancelled);
      expect(backend.discarded, ['/output/just-finished.mp4']);
      controller.dispose();
    },
  );
}
