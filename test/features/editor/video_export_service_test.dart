import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/models/crop_rect.dart';
import 'package:pitchcut_ai/features/editor/models/video_clip.dart';
import 'package:pitchcut_ai/features/editor/models/video_export_state.dart';
import 'package:pitchcut_ai/features/editor/services/video_export_controller.dart';
import 'package:pitchcut_ai/features/editor/services/video_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const control = MethodChannel('pitchcut/editor');
  const events = EventChannel('pitchcut/editor/progress');
  const legacy = MethodChannel('pitchcut_ai/video_trim');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  const clip = VideoClip(
    path: '/source.mp4',
    name: 'source',
    duration: Duration(seconds: 2),
  );

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(control, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(legacy, (_) async {
      fail('M5 export must use the shared editor channel');
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(control, null);
    messenger.setMockMethodCallHandler(legacy, null);
    messenger.setMockStreamHandler(events, null);
  });

  void completeExport() {
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          sink.success({'progress': 0.25});
          sink.success({'progress': 1.0, 'outputPath': '/cache/rendered.mp4'});
        },
      ),
    );
  }

  test(
    'maps ordered edited segments and repeated sources to shared API',
    () async {
      completeExport();
      final progress = <double>[];
      final service = VideoExportService();
      final output = await service.exportTimeline(
        [
          clip.copyWith(
            sourceStart: const Duration(seconds: 1),
            rotationDegrees: 90,
            crop: const CropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8),
          ),
          clip.copyWith(path: '/other.mp4', rotationDegrees: 270),
          clip.copyWith(sourceStart: const Duration(seconds: 3)),
        ],
        VideoExportQuality.p480,
        onProgress: progress.add,
      );
      expect(output, '/cache/rendered.mp4');
      expect(progress, [0.25, 1.0]);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'exportTimeline');
      expect(calls.single.arguments, {
        'targetHeight': 480,
        'items': [
          {
            'path': '/source.mp4',
            'startMs': 1000,
            'endMs': 3000,
            'rotationDegrees': 90,
            'crop': {'left': 0.1, 'top': 0.2, 'right': 0.9, 'bottom': 0.8},
          },
          {
            'path': '/other.mp4',
            'startMs': 0,
            'endMs': 2000,
            'rotationDegrees': 270,
          },
          {
            'path': '/source.mp4',
            'startMs': 3000,
            'endMs': 5000,
            'rotationDegrees': 0,
          },
        ],
      });
    },
  );

  for (final quality in VideoExportQuality.values) {
    test(
      'forwards ${quality.label} without changing native settings',
      () async {
        completeExport();
        await VideoExportService().exportTimeline(
          [clip],
          quality,
          onProgress: (_) {},
        );
        expect(calls.single.arguments['targetHeight'], quality.height);
      },
    );
  }

  test(
    'native stream failures reach the existing controller error state',
    () async {
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, sink) => sink.error(
            code: 'UNSUPPORTED_FORMAT',
            message: 'Codec unavailable',
          ),
        ),
      );
      final controller = VideoExportController(backend: VideoExportService());
      await controller.start([clip], VideoExportQuality.p720);
      expect(controller.state.status, VideoExportStatus.failed);
      expect(controller.state.errorMessage, 'Codec unavailable');
      completeExport();
      // A fresh service can acquire the shared channel again after failure cleanup.
      expect(
        await VideoExportService().exportTimeline(
          [clip],
          VideoExportQuality.p720,
          onProgress: (_) {},
        ),
        '/cache/rendered.mp4',
      );
      controller.dispose();
    },
  );

  test(
    'method failures are surfaced rather than waiting for stream completion',
    () async {
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
      messenger.setMockMethodCallHandler(control, (_) async {
        throw PlatformException(
          code: 'FILE_NOT_FOUND',
          message: 'Source missing',
        );
      });
      await expectLater(
        VideoExportService().exportTimeline(
          [clip],
          VideoExportQuality.p720,
          onProgress: (_) {},
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Source missing',
          ),
        ),
      );
    },
  );

  test('cancellation reaches shared native API and allows retry', () async {
    final ready = Completer<void>();
    dynamic sink;
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, events) {
          sink = events;
          ready.complete();
        },
      ),
    );
    messenger.setMockMethodCallHandler(control, (call) async {
      calls.add(call);
      if (call.method == 'cancelExport') {
        sink.error(code: 'CANCELLED', message: 'Export cancelled');
      }
      return null;
    });
    final service = VideoExportService();
    final operation = service.exportTimeline(
      [clip],
      VideoExportQuality.p720,
      onProgress: (_) {},
    );
    final cancelled = expectLater(
      operation,
      throwsA(isA<VideoExportCancelled>()),
    );
    await ready.future;
    await service.cancelExport();
    await cancelled;
    expect(calls.map((call) => call.method), [
      'exportTimeline',
      'cancelExport',
    ]);
    completeExport();
    expect(
      await service.exportTimeline(
        [clip],
        VideoExportQuality.p1080,
        onProgress: (_) {},
      ),
      '/cache/rendered.mp4',
    );
    final callCount = calls.length;
    await service.cancelExport();
    expect(calls.length, callCount);
  });

  test(
    'rejects empty and invalid timelines before calling native export',
    () async {
      final service = VideoExportService();
      for (final clips in [
        <VideoClip>[],
        [clip.copyWith(rotationDegrees: 45)],
      ]) {
        await expectLater(
          service.exportTimeline(
            clips,
            VideoExportQuality.p720,
            onProgress: (_) {},
          ),
          throwsArgumentError,
        );
      }
      expect(calls, isEmpty);
    },
  );

  test(
    'adapts M5 minimum crop tolerance to the strict shared contract',
    () async {
      const crop = CropRect(left: 0.3, top: 0.3, right: 0.35, bottom: 0.35);
      expect(crop.isValid, isTrue);
      completeExport();
      await VideoExportService().exportTimeline(
        [clip.copyWith(crop: crop)],
        VideoExportQuality.p720,
        onProgress: (_) {},
      );
      final serialized = calls.single.arguments['items'][0]['crop'] as Map;
      expect(
        serialized['right'] - serialized['left'],
        greaterThanOrEqualTo(0.05),
      );
      expect(
        serialized['bottom'] - serialized['top'],
        greaterThanOrEqualTo(0.05),
      );
      expect(serialized['right'], closeTo(crop.right, 2e-9));
      expect(serialized['bottom'], closeTo(crop.bottom, 2e-9));
    },
  );

  test('does not accept progress-only stream closure as success', () async {
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          sink.success({'progress': 0.5});
          sink.endOfStream();
        },
      ),
    );
    await expectLater(
      VideoExportService().exportTimeline(
        [clip],
        VideoExportQuality.p720,
        onProgress: (_) {},
      ),
      throwsA(isA<StateError>()),
    );
  });
}
