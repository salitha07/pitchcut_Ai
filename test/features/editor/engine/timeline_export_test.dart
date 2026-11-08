import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/engine/editor_engine.dart';
import 'package:pitchcut_ai/features/editor/engine/method_channel_editor_engine.dart';

import '../../../fakes/fake_editor_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Editor timeline export models', () {
    test('rejects invalid paths, ranges, and rotations', () {
      expect(
        () => EditorTimelineItem(path: '  ', startMs: 0, endMs: 100),
        throwsArgumentError,
      );
      expect(
        () => EditorTimelineItem(path: '/video.mp4', startMs: -1, endMs: 100),
        throwsArgumentError,
      );
      expect(
        () => EditorTimelineItem(path: '/video.mp4', startMs: 100, endMs: 100),
        throwsArgumentError,
      );
      expect(
        () => EditorTimelineItem(
          path: '/video.mp4',
          startMs: 0,
          endMs: 100,
          rotationDegrees: 45,
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid, nonfinite, or undersized crop bounds', () {
      expect(
        () => EditorCrop(left: -0.1, top: 0, right: 0.9, bottom: 1),
        throwsArgumentError,
      );
      expect(
        () => EditorCrop(left: 0, top: 0, right: 1.1, bottom: 1),
        throwsArgumentError,
      );
      expect(
        () => EditorCrop(left: double.nan, top: 0, right: 1, bottom: 1),
        throwsArgumentError,
      );
      expect(
        () => EditorCrop(left: 0, top: 0, right: 0.049, bottom: 1),
        throwsArgumentError,
      );
      expect(
        () => EditorCrop(left: 0, top: 0, right: 1, bottom: 0.049),
        throwsArgumentError,
      );
      expect(
        () => EditorCrop(left: 0, top: 0, right: 0.05, bottom: 0.05),
        returnsNormally,
      );
    });

    test('accepts all supported target heights', () {
      final item = EditorTimelineItem(
        path: '/video.mp4',
        startMs: 0,
        endMs: 100,
      );
      for (final height in [480, 720, 1080]) {
        expect(
          () => EditorEngine.validateTimelineExportRequest(
            items: [item],
            targetHeight: height,
          ),
          returnsNormally,
        );
      }
    });
  });

  group('MethodChannelEditorEngine.exportTimeline', () {
    const methodChannel = MethodChannel('pitchcut/editor');
    const eventChannel = EventChannel('pitchcut/editor/progress');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final recordedCalls = <MethodCall>[];

    setUp(() {
      recordedCalls.clear();
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        recordedCalls.add(call);
        return null;
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockStreamHandler(eventChannel, null);
    });

    test('serializes order, repeated paths, edits, and crop', () async {
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            sink.success({'progress': 0.0});
            sink.success({
              'progress': 1.0,
              'outputPath': '/output/timeline.mp4',
            });
            sink.endOfStream();
          },
        ),
      );
      final engine = MethodChannelEditorEngine();
      final crop = EditorCrop(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
      final items = [
        EditorTimelineItem(
          path: '/same.mp4',
          startMs: 100,
          endMs: 900,
          rotationDegrees: 90,
          crop: crop,
        ),
        EditorTimelineItem(
          path: '/other.mp4',
          startMs: 0,
          endMs: 500,
          rotationDegrees: 180,
        ),
        EditorTimelineItem(path: '/same.mp4', startMs: 900, endMs: 1200),
      ];

      final events = await engine
          .exportTimeline(items: items, targetHeight: 720)
          .toList();
      expect(events.last.outputPath, '/output/timeline.mp4');

      expect(recordedCalls, hasLength(1));
      expect(recordedCalls.single.method, 'exportTimeline');
      expect(recordedCalls.single.arguments['targetHeight'], 720);
      expect(recordedCalls.first.arguments['items'], [
        {
          'path': '/same.mp4',
          'startMs': 100,
          'endMs': 900,
          'rotationDegrees': 90,
          'crop': {'left': 0.1, 'top': 0.2, 'right': 0.9, 'bottom': 0.8},
        },
        {
          'path': '/other.mp4',
          'startMs': 0,
          'endMs': 500,
          'rotationDegrees': 180,
        },
        {
          'path': '/same.mp4',
          'startMs': 900,
          'endMs': 1200,
          'rotationDegrees': 0,
        },
      ]);
    });

    test('validates nonempty items and target height before channel use', () {
      final engine = MethodChannelEditorEngine();
      expect(
        () => engine.exportTimeline(items: const [], targetHeight: 720),
        throwsArgumentError,
      );
      final item = EditorTimelineItem(
        path: '/video.mp4',
        startMs: 0,
        endMs: 100,
      );
      expect(
        () => engine.exportTimeline(items: [item], targetHeight: 360),
        throwsArgumentError,
      );
      expect(recordedCalls, isEmpty);
    });

    test('streams progress, final output, and native errors', () async {
      dynamic eventSink;
      final streamReady = Completer<void>();
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            eventSink = sink;
            streamReady.complete();
          },
        ),
      );
      final engine = MethodChannelEditorEngine();
      final events = <ExportEvent>[];
      final errors = <Object>[];
      final ended = Completer<void>();
      engine
          .exportTimeline(
            items: [
              EditorTimelineItem(path: '/video.mp4', startMs: 0, endMs: 1000),
            ],
            targetHeight: 720,
          )
          .listen(events.add, onError: errors.add, onDone: ended.complete);

      await streamReady.future;
      eventSink.success({'progress': 0.4});
      eventSink.error(code: 'CANCELLED', message: 'Export cancelled');
      eventSink.endOfStream();
      await ended.future;

      expect(events.map((event) => event.progress), [0.4]);
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

    test(
      'rejects a second export on the same channel while one is active',
      () async {
        final streamReady = Completer<void>();
        final nativeStreamCancelled = Completer<void>();
        messenger.setMockStreamHandler(
          eventChannel,
          MockStreamHandler.inline(
            onListen: (arguments, sink) => streamReady.complete(),
            onCancel: (arguments) => nativeStreamCancelled.complete(),
          ),
        );
        final engine = MethodChannelEditorEngine();
        final first = engine
            .exportTimeline(
              items: [
                EditorTimelineItem(path: '/first.mp4', startMs: 0, endMs: 1000),
              ],
              targetHeight: 720,
            )
            .listen((_) {});
        await streamReady.future;

        final secondErrors = <Object>[];
        final secondEnded = Completer<void>();
        MethodChannelEditorEngine()
            .exportTimeline(
              items: [
                EditorTimelineItem(
                  path: '/second.mp4',
                  startMs: 0,
                  endMs: 1000,
                ),
              ],
              targetHeight: 720,
            )
            .listen(
              (_) {},
              onError: secondErrors.add,
              onDone: secondEnded.complete,
            );
        await secondEnded.future;

        expect(recordedCalls, hasLength(1));
        expect(recordedCalls.single.method, 'exportTimeline');
        expect(secondErrors, hasLength(1));
        expect(
          secondErrors.single,
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'EXPORT_FAILED',
          ),
        );

        await first.cancel();
        await nativeStreamCancelled.future;
      },
    );

    test('listener cancellation cancels the shared native export', () async {
      final streamReady = Completer<void>();
      final nativeStreamCancelled = Completer<void>();
      final cancelMethodCalled = Completer<void>();
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, sink) => streamReady.complete(),
          onCancel: (arguments) => nativeStreamCancelled.complete(),
        ),
      );
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        recordedCalls.add(call);
        if (call.method == 'cancelExport' && !cancelMethodCalled.isCompleted) {
          cancelMethodCalled.complete();
        }
        return null;
      });

      final subscription = MethodChannelEditorEngine()
          .exportTimeline(
            items: [
              EditorTimelineItem(path: '/video.mp4', startMs: 0, endMs: 1000),
            ],
            targetHeight: 480,
          )
          .listen((_) {});
      await streamReady.future;
      await subscription.cancel();

      await nativeStreamCancelled.future;
      await cancelMethodCalled.future;
      expect(recordedCalls.map((call) => call.method), [
        'exportTimeline',
        'cancelExport',
      ]);
    });

    test(
      'subscription cancellation failure preserves successful completion',
      () async {
        var listens = 0;
        messenger.setMockStreamHandler(
          eventChannel,
          MockStreamHandler.inline(
            onListen: (arguments, sink) {
              listens++;
              sink.success({'progress': 1.0, 'outputPath': '/output/ok.mp4'});
            },
            onCancel: (arguments) => throw StateError('cancel failed'),
          ),
        );
        final engine = MethodChannelEditorEngine();
        final firstEvents = await engine
            .exportTimeline(
              items: [
                EditorTimelineItem(path: '/first.mp4', startMs: 0, endMs: 10),
              ],
              targetHeight: 720,
            )
            .toList();
        final secondEvents = await engine
            .exportTimeline(
              items: [
                EditorTimelineItem(path: '/second.mp4', startMs: 0, endMs: 10),
              ],
              targetHeight: 720,
            )
            .toList();

        expect(firstEvents.single.outputPath, '/output/ok.mp4');
        expect(secondEvents.single.outputPath, '/output/ok.mp4');
        expect(listens, 2);
      },
    );

    test(
      'subscription cancellation failure preserves native export error',
      () async {
        var listens = 0;
        messenger.setMockStreamHandler(
          eventChannel,
          MockStreamHandler.inline(
            onListen: (arguments, sink) {
              listens++;
              if (listens == 1) {
                sink.error(code: 'UNSUPPORTED_FORMAT', message: 'bad format');
              } else {
                sink.success({
                  'progress': 1.0,
                  'outputPath': '/output/recovered.mp4',
                });
              }
            },
            onCancel: (arguments) => throw StateError('cancel failed'),
          ),
        );
        final engine = MethodChannelEditorEngine();
        await expectLater(
          engine
              .exportTimeline(
                items: [
                  EditorTimelineItem(path: '/first.mp4', startMs: 0, endMs: 10),
                ],
                targetHeight: 720,
              )
              .toList(),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'UNSUPPORTED_FORMAT',
            ),
          ),
        );
        final secondEvents = await engine
            .exportTimeline(
              items: [
                EditorTimelineItem(path: '/second.mp4', startMs: 0, endMs: 10),
              ],
              targetHeight: 720,
            )
            .toList();

        expect(secondEvents.single.outputPath, '/output/recovered.mp4');
        expect(listens, 2);
      },
    );

    test(
      'subscription cancellation failure preserves method invocation error',
      () async {
        var invokes = 0;
        var listens = 0;
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          recordedCalls.add(call);
          if (call.method == 'exportTimeline' && invokes++ == 0) {
            throw PlatformException(
              code: 'EXPORT_FAILED',
              message: 'invoke failed',
            );
          }
          return null;
        });
        messenger.setMockStreamHandler(
          eventChannel,
          MockStreamHandler.inline(
            onListen: (arguments, sink) {
              listens++;
              if (listens > 1) {
                sink.success({
                  'progress': 1.0,
                  'outputPath': '/output/recovered.mp4',
                });
              }
            },
            onCancel: (arguments) => throw StateError('cancel failed'),
          ),
        );
        final engine = MethodChannelEditorEngine();
        await expectLater(
          engine
              .exportTimeline(
                items: [
                  EditorTimelineItem(path: '/first.mp4', startMs: 0, endMs: 10),
                ],
                targetHeight: 720,
              )
              .toList(),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.message,
              'message',
              'invoke failed',
            ),
          ),
        );
        final secondEvents = await engine
            .exportTimeline(
              items: [
                EditorTimelineItem(path: '/second.mp4', startMs: 0, endMs: 10),
              ],
              targetHeight: 720,
            )
            .toList();

        expect(secondEvents.single.outputPath, '/output/recovered.mp4');
        expect(listens, 2);
      },
    );

    test(
      'subscription cancellation failure still sends native user cancel',
      () async {
        final streamReady = Completer<void>();
        var listens = 0;
        var cancelCalls = 0;
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          recordedCalls.add(call);
          if (call.method == 'cancelExport') cancelCalls++;
          return null;
        });
        messenger.setMockStreamHandler(
          eventChannel,
          MockStreamHandler.inline(
            onListen: (arguments, sink) {
              listens++;
              if (listens == 1 && !streamReady.isCompleted) {
                streamReady.complete();
              }
              if (listens > 1) {
                sink.success({
                  'progress': 1.0,
                  'outputPath': '/output/recovered.mp4',
                });
              }
            },
            onCancel: (arguments) => throw StateError('cancel failed'),
          ),
        );
        final engine = MethodChannelEditorEngine();
        final first = engine
            .exportTimeline(
              items: [
                EditorTimelineItem(path: '/first.mp4', startMs: 0, endMs: 10),
              ],
              targetHeight: 720,
            )
            .listen((_) {});
        await streamReady.future;
        await first.cancel();
        final secondEvents = await engine
            .exportTimeline(
              items: [
                EditorTimelineItem(path: '/second.mp4', startMs: 0, endMs: 10),
              ],
              targetHeight: 720,
            )
            .toList();

        expect(cancelCalls, 1);
        expect(secondEvents.single.outputPath, '/output/recovered.mp4');
        expect(listens, 2);
      },
    );
  });

  group('FakeEditorEngine.exportTimeline', () {
    test('records the timeline and emits a successful completion', () async {
      final engine = FakeEditorEngine(delay: Duration.zero);
      final items = [
        EditorTimelineItem(path: '/clip.mp4', startMs: 0, endMs: 400),
        EditorTimelineItem(path: '/clip.mp4', startMs: 600, endMs: 900),
      ];

      final events = await engine
          .exportTimeline(items: items, targetHeight: 1080)
          .toList();

      expect(engine.lastMethod, 'exportTimeline');
      expect(engine.lastCallArguments, {
        'items': [
          {
            'path': '/clip.mp4',
            'startMs': 0,
            'endMs': 400,
            'rotationDegrees': 0,
          },
          {
            'path': '/clip.mp4',
            'startMs': 600,
            'endMs': 900,
            'rotationDegrees': 0,
          },
        ],
        'targetHeight': 1080,
      });
      expect(events.last.outputPath, contains('clip.mp4'));
    });

    test(
      'configured timeline errors and cancellation use export conventions',
      () async {
        final failed = FakeEditorEngine(
          delay: Duration.zero,
          methodErrors: {'exportTimeline': 'EXPORT_FAILED'},
        );
        final item = EditorTimelineItem(
          path: '/clip.mp4',
          startMs: 0,
          endMs: 500,
        );
        await expectLater(
          failed.exportTimeline(items: [item], targetHeight: 720).toList(),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'EXPORT_FAILED',
            ),
          ),
        );

        final engine = FakeEditorEngine(
          delay: const Duration(milliseconds: 100),
        );
        final firstEvent = Completer<void>();
        final ended = Completer<void>();
        final errors = <Object>[];
        engine
            .exportTimeline(items: [item], targetHeight: 720)
            .listen(
              (_) {
                if (!firstEvent.isCompleted) firstEvent.complete();
              },
              onError: errors.add,
              onDone: ended.complete,
            );
        await firstEvent.future;
        await engine.cancelExport();
        await ended.future;
        expect(
          errors.single,
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'CANCELLED',
          ),
        );
      },
    );
  });
}
