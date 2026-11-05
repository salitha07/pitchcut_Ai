import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/engine/editor_engine.dart';
import 'package:pitchcut_ai/features/editor/engine/method_channel_editor_engine.dart';

import '../../../fakes/fake_editor_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FakeEditorEngine export cancellation', () {
    test('cancellation emits CANCELLED and never completes the export', () async {
      final engine = FakeEditorEngine(delay: Duration.zero);
      final events = <ExportEvent>[];
      final errors = <Object>[];
      final firstEvent = Completer<void>();
      final streamEnded = Completer<void>();

      engine.export(clipPaths: ['/storage/video.mp4']).listen(
        (event) {
          events.add(event);
          if (!firstEvent.isCompleted) firstEvent.complete();
        },
        onError: (Object error) {
          errors.add(error);
        },
        onDone: () {
          if (!streamEnded.isCompleted) streamEnded.complete();
        },
      );

      await firstEvent.future;
      await engine.cancelExport();
      await engine.cancelExport();
      await streamEnded.future;

      expect(events, hasLength(1));
      expect(events.single.progress, 0.0);
      expect(events.every((event) => event.outputPath == null), isTrue);
      expect(errors, hasLength(1));
      expect(
        errors.single,
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'CANCELLED',
        ),
      );
    });

    test('cancelExport with no active export completes and emits nothing',
        () async {
      final engine = FakeEditorEngine(delay: Duration.zero);
      final events = <ExportEvent>[];
      final errors = <Object>[];
      final streamEnded = Completer<void>();
      engine.export(clipPaths: ['/storage/video.mp4']).listen(
        events.add,
        onError: errors.add,
        onDone: () => streamEnded.complete(),
      );
      await streamEnded.future;

      final eventCount = events.length;
      await engine.cancelExport();

      expect(events, hasLength(eventCount));
      expect(errors, isEmpty);
    });

    test('failed export emits its configured error without a completed event',
        () async {
      final engine = FakeEditorEngine(delay: Duration.zero)
        ..setMethodError('export', 'EXPORT_FAILED');

      await expectLater(
        engine.export(clipPaths: ['/storage/video.mp4']).toList(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'EXPORT_FAILED',
          ),
        ),
      );
    });
  });

  group('MethodChannelEditorEngine export cancellation', () {
    const methodChannel = MethodChannel('pitchcut/editor');
    const eventChannel = EventChannel('pitchcut/editor/progress');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockStreamHandler(eventChannel, null);
    });

    test('cancelExport passes CANCELLED through without a completed event',
        () async {
      final streamReady = Completer<void>();
      final streamEnded = Completer<void>();
      final events = <ExportEvent>[];
      final errors = <Object>[];
      dynamic eventSink;
      var cancellationCalls = 0;

      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            eventSink = sink;
            if (!streamReady.isCompleted) streamReady.complete();
          },
        ),
      );
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'cancelExport') {
          cancellationCalls++;
          if (cancellationCalls == 1) {
            eventSink.error(
              code: 'CANCELLED',
              message: 'Export cancelled',
            );
            eventSink.endOfStream();
          }
        }
        return null;
      });

      final engine = MethodChannelEditorEngine();
      engine.export(clipPaths: ['/storage/video.mp4']).listen(
        events.add,
        onError: (Object error) => errors.add(error),
        onDone: () {
          if (!streamEnded.isCompleted) streamEnded.complete();
        },
      );

      await streamReady.future;
      await engine.cancelExport();
      await engine.cancelExport();
      await streamEnded.future;

      expect(events, isEmpty);
      expect(errors, hasLength(1));
      expect(cancellationCalls, 2);
      expect(
        errors.single,
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'CANCELLED',
        ),
      );
    });

    test('cancelExport with no active export emits no event', () async {
      final streamReady = Completer<void>();
      final events = <Object?>[];
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, sink) => streamReady.complete(),
        ),
      );
      messenger.setMockMethodCallHandler(methodChannel, (call) async => null);

      final engine = MethodChannelEditorEngine();
      final subscription = eventChannel.receiveBroadcastStream().listen(
        events.add,
      );
      await streamReady.future;
      await engine.cancelExport();
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(events, isEmpty);
    });

    test('preserves event order and closes after the final event', () async {
      final streamReady = Completer<void>();
      dynamic eventSink;
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            eventSink = sink;
            streamReady.complete();
          },
        ),
      );
      messenger.setMockMethodCallHandler(methodChannel, (call) async => null);

      final events = <ExportEvent>[];
      final streamEnded = Completer<void>();
      MethodChannelEditorEngine()
          .export(clipPaths: ['/input/video.mp4'])
          .listen(events.add, onDone: () => streamEnded.complete());

      await streamReady.future;
      eventSink.success({'progress': 0, 'outputPath': null});
      eventSink.success({'progress': 0.6, 'outputPath': null});
      eventSink.success({'progress': 1, 'outputPath': '/output/final.mp4'});
      eventSink.endOfStream();
      await streamEnded.future;

      expect(events.map((event) => event.progress), [0.0, 0.6, 1.0]);
      expect(events.last.outputPath, '/output/final.mp4');
    });

    test('listener cancellation cancels native event subscription and export',
        () async {
      final streamReady = Completer<void>();
      final nativeStreamCancelled = Completer<void>();
      final cancelExportCalled = Completer<void>();
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, sink) => streamReady.complete(),
          onCancel: (arguments) => nativeStreamCancelled.complete(),
        ),
      );
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'cancelExport' && !cancelExportCalled.isCompleted) {
          cancelExportCalled.complete();
        }
        return null;
      });

      final subscription = MethodChannelEditorEngine()
          .export(clipPaths: ['/input/video.mp4'])
          .listen((_) {});
      await streamReady.future;
      await subscription.cancel();

      await nativeStreamCancelled.future;
      await cancelExportCalled.future;
    });

    test('forwards a native PlatformException and closes the stream', () async {
      final streamReady = Completer<void>();
      dynamic eventSink;
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            eventSink = sink;
            streamReady.complete();
          },
        ),
      );
      messenger.setMockMethodCallHandler(methodChannel, (call) async => null);

      final errors = <Object>[];
      final streamEnded = Completer<void>();
      MethodChannelEditorEngine()
          .export(clipPaths: ['/input/video.mp4'])
          .listen(
            (_) {},
            onError: errors.add,
            onDone: () => streamEnded.complete(),
          );

      await streamReady.future;
      eventSink.error(code: 'UNSUPPORTED_FORMAT', message: 'Bad media');
      eventSink.endOfStream();
      await streamEnded.future;

      expect(errors, hasLength(1));
      expect(
        errors.single,
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_FORMAT',
        ),
      );
    });

    test('ignores malformed events and completes without throwing', () async {
      final streamReady = Completer<void>();
      dynamic eventSink;
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            eventSink = sink;
            streamReady.complete();
          },
        ),
      );
      messenger.setMockMethodCallHandler(methodChannel, (call) async => null);

      final events = <ExportEvent>[];
      final errors = <Object>[];
      final streamEnded = Completer<void>();
      MethodChannelEditorEngine().export(clipPaths: ['/input/video.mp4']).listen(
            events.add,
            onError: errors.add,
            onDone: () => streamEnded.complete(),
          );

      await streamReady.future;
      eventSink.success({'cancelled': false});
      eventSink.success({'progress': 'not numeric'});
      eventSink.success({'progress': 0.25, 'outputPath': 123});
      eventSink.endOfStream();
      await streamEnded.future;

      expect(events, isEmpty);
      expect(errors, isEmpty);
    });
  });
}
