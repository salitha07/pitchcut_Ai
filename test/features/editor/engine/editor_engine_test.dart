import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pitchcut_ai/features/editor/engine/editor_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/engine/method_channel_editor_engine.dart';
import 'package:pitchcut_ai/models/caption.dart';

import '../../../fakes/fake_editor_engine.dart';

void expectSuccessfulExportEvents(
  List<ExportEvent> events,
  List<double> expectedProgress,
) {
  expect(events.map((event) => event.progress).toList(), expectedProgress);
  expect(events, isNotEmpty);

  var previousProgress = 0.0;
  for (var index = 0; index < events.length; index++) {
    final event = events[index];
    expect(event.progress, inInclusiveRange(0.0, 1.0));
    if (index > 0) {
      expect(event.progress, greaterThanOrEqualTo(previousProgress));
    }
    expect(event.outputPath, index == events.length - 1 ? isNotNull : isNull);
    previousProgress = event.progress;
  }

  expect(events.last.progress, 1.0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FakeEditorEngine', () {
    late FakeEditorEngine fakeEngine;

    setUp(() {
      // Use zero delay in unit tests for fast execution
      fakeEngine = FakeEditorEngine(delay: Duration.zero);
    });

    test('default delay is short and can be configured', () async {
      expect(FakeEditorEngine().delay, const Duration(milliseconds: 50));
      final delayedEngine = FakeEditorEngine(
        delay: const Duration(milliseconds: 25),
      );
      final stopwatch = Stopwatch()..start();

      await delayedEngine.trim(path: '/video.mp4', startMs: 0, endMs: 1);

      expect(
        stopwatch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 20)),
      );
    });

    test('trim returns the unchanged input path by default', () async {
      final result = await fakeEngine.trim(
        path: '/storage/video.mp4',
        startMs: 1000,
        endMs: 3000,
      );
      expect(result, '/storage/video.mp4');
    });

    test(
      'cut returns exactly two non-empty input-path entries by default',
      () async {
        final parts = await fakeEngine.cut(
          path: '/storage/video.mp4',
          atMs: 2500,
        );
        expect(parts.length, 2);
        expect(parts, ['/storage/video.mp4', '/storage/video.mp4']);
        expect(parts.every((part) => part.trim().isNotEmpty), isTrue);
      },
    );

    test('merge returns the first input path by default', () async {
      final result = await fakeEngine.merge(
        paths: ['/storage/clip1.mp4', '/storage/clip2.mp4'],
      );
      expect(result, '/storage/clip1.mp4');
    });

    test('rotate returns the unchanged input path by default', () async {
      final result = await fakeEngine.rotate(
        path: '/storage/video.mp4',
        degrees: 90,
      );
      expect(result, '/storage/video.mp4');
    });

    test('crop returns the unchanged input path by default', () async {
      final result = await fakeEngine.crop(
        path: '/storage/video.mp4',
        left: 10,
        top: 20,
        width: 720,
        height: 1280,
      );
      expect(result, '/storage/video.mp4');
    });

    test('synthetic path mode preserves transformed-style outputs', () async {
      final synthetic = FakeEditorEngine(
        delay: Duration.zero,
        useSyntheticPaths: true,
      );

      expect(
        await synthetic.trim(
          path: '/storage/video.mp4',
          startMs: 1000,
          endMs: 3000,
        ),
        '/storage/video_trimmed_1000_3000.mp4',
      );
      expect(await synthetic.cut(path: '/storage/video.mp4', atMs: 2500), [
        '/storage/video_part1_2500ms.mp4',
        '/storage/video_part2_2500ms.mp4',
      ]);
      expect(
        await synthetic.merge(
          paths: ['/storage/clip1.mp4', '/storage/clip2.mp4'],
        ),
        '/storage/clip1_merged.mp4',
      );
      expect(
        await synthetic.rotate(path: '/storage/video.mp4', degrees: 90),
        '/storage/video_rot90.mp4',
      );
      expect(
        await synthetic.crop(
          path: '/storage/video.mp4',
          left: 10,
          top: 20,
          width: 720,
          height: 1280,
        ),
        '/storage/video_crop_720x1280.mp4',
      );
    });

    test(
      'getLoudnessSamples returns 50 normalized samples between 0.0 and 1.0',
      () async {
        final samples = await fakeEngine.getLoudnessSamples(
          '/storage/video.mp4',
        );
        expect(samples.length, 50);
        for (final sample in samples) {
          expect(sample, greaterThanOrEqualTo(0.0));
          expect(sample, lessThanOrEqualTo(1.0));
        }
      },
    );

    test('export emits progress from 0.0 to 1.0 with outputPath only on the last event', () async {
      final caption = Caption(
        id: 'test-caption',
        text: 'Hello',
        startMs: 100,
        endMs: 500,
      );
      final events = await fakeEngine
          .export(
            clipPaths: ['/storage/video.mp4'],
            captions: [caption],
            targetHeight: 720,
          )
          .toList();

      expect(events.length, 5);
      expectSuccessfulExportEvents(events, [0.0, 0.25, 0.50, 0.75, 1.0]);
      expect(events[4].outputPath, '/storage/video.mp4');
      expect(fakeEngine.lastMethod, 'export');
      expect(fakeEngine.lastCallArguments, {
        'clipPaths': ['/storage/video.mp4'],
        'captions': [caption],
        'targetHeight': 720,
      });
    });

    test('synthetic export uses transformed path only when opted in', () async {
      final synthetic = FakeEditorEngine(
        delay: Duration.zero,
        useSyntheticPaths: true,
      );

      final events = await synthetic
          .export(clipPaths: ['/storage/video.mp4'])
          .toList();

      expect(events.last.outputPath, '/storage/video_export.mp4');
    });

    test('cancelExport cancels export and emits CANCELLED error', () async {
      final delayedEngine = FakeEditorEngine(delay: Duration.zero);
      final events = <ExportEvent>[];
      final errors = <Object>[];
      final firstEvent = Completer<void>();
      final streamEnded = Completer<void>();

      delayedEngine
          .export(clipPaths: ['/storage/video.mp4'])
          .listen(
            (event) {
              events.add(event);
              if (!firstEvent.isCompleted) firstEvent.complete();
            },
            onError: (Object error) {
              errors.add(error);
              if (!streamEnded.isCompleted) streamEnded.complete();
            },
            onDone: () {
              if (!streamEnded.isCompleted) streamEnded.complete();
            },
          );

      await firstEvent.future;
      await delayedEngine.cancelExport();
      await streamEnded.future;

      expect(events, hasLength(1));
      expect(events.single.progress, 0.0);
      expect(events.single.outputPath, isNull);
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

    test('simulatedErrorCode throws for all operations', () async {
      fakeEngine.simulatedErrorCode = 'FILE_NOT_FOUND';

      expect(
        () => fakeEngine.trim(path: '/video.mp4', startMs: 0, endMs: 1000),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'FILE_NOT_FOUND',
          ),
        ),
      );

      expect(
        () => fakeEngine.export(clipPaths: ['/video.mp4']).first,
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'FILE_NOT_FOUND',
          ),
        ),
      );
    });

    test('setMethodError allows setting errors per method', () async {
      fakeEngine.setMethodError('trim', 'INVALID_RANGE');

      expect(
        () => fakeEngine.trim(path: '/video.mp4', startMs: 5000, endMs: 1000),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'INVALID_RANGE',
          ),
        ),
      );

      // Other operations still succeed
      final rotated = await fakeEngine.rotate(path: '/video.mp4', degrees: 180);
      expect(rotated, '/video.mp4');
    });

    test(
      'configured error codes are limited to the five contract codes',
      () async {
        for (final code in [
          'FILE_NOT_FOUND',
          'INVALID_RANGE',
          'UNSUPPORTED_FORMAT',
          'EXPORT_FAILED',
          'CANCELLED',
        ]) {
          fakeEngine.setMethodError('trim', code);
          await expectLater(
            fakeEngine.trim(path: '/video.mp4', startMs: 0, endMs: 1),
            throwsA(
              isA<PlatformException>().having(
                (error) => error.code,
                'code',
                code,
              ),
            ),
          );
        }

        fakeEngine.setMethodError('trim', 'NATIVE_INTERNAL');
        await expectLater(
          fakeEngine.trim(path: '/video.mp4', startMs: 0, endMs: 1),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'EXPORT_FAILED',
            ),
          ),
        );

        fakeEngine.setMethodError('export', 'NATIVE_INTERNAL');
        await expectLater(
          fakeEngine.export(clipPaths: ['/video.mp4']).toList(),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'EXPORT_FAILED',
            ),
          ),
        );
      },
    );
  });

  group('MethodChannelEditorEngine', () {
    const methodChannel = MethodChannel('pitchcut/editor');
    const eventChannel = EventChannel('pitchcut/editor/progress');
    late MethodChannelEditorEngine engine;
    final List<MethodCall> recordedCalls = [];

    setUp(() {
      recordedCalls.clear();
      engine = MethodChannelEditorEngine();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
            recordedCalls.add(call);
            switch (call.method) {
              case 'trim':
                return '/output/trimmed.mp4';
              case 'cut':
                return ['/output/cut1.mp4', '/output/cut2.mp4'];
              case 'merge':
                return '/output/merged.mp4';
              case 'rotate':
                return '/output/rotated.mp4';
              case 'crop':
                return '/output/cropped.mp4';
              case 'cancelExport':
                return null;
              case 'getLoudnessSamples':
                return [0.1, 0.4, 0.9];
              case 'export':
                return null;
              default:
                throw PlatformException(code: 'UNIMPLEMENTED');
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, null);
    });

    test('trim invokes channel and returns path', () async {
      final result = await engine.trim(
        path: '/input/video.mp4',
        startMs: 500,
        endMs: 2500,
      );

      expect(result, '/output/trimmed.mp4');
      expect(recordedCalls.length, 1);
      expect(recordedCalls.first.method, 'trim');
      expect(recordedCalls.first.arguments, {
        'path': '/input/video.mp4',
        'startMs': 500,
        'endMs': 2500,
      });
    });

    test('cut invokes channel and returns parts list', () async {
      final parts = await engine.cut(path: '/input/video.mp4', atMs: 1500);

      expect(parts, ['/output/cut1.mp4', '/output/cut2.mp4']);
      expect(recordedCalls.first.method, 'cut');
      expect(recordedCalls.first.arguments, {
        'path': '/input/video.mp4',
        'atMs': 1500,
      });
    });

    test('merge invokes channel and returns merged path', () async {
      final result = await engine.merge(paths: ['/c1.mp4', '/c2.mp4']);

      expect(result, '/output/merged.mp4');
      expect(recordedCalls.first.method, 'merge');
      expect(recordedCalls.first.arguments, {
        'paths': ['/c1.mp4', '/c2.mp4'],
      });
    });

    test('rotate invokes channel and returns path', () async {
      final result = await engine.rotate(
        path: '/input/video.mp4',
        degrees: 270,
      );

      expect(result, '/output/rotated.mp4');
      expect(recordedCalls.first.method, 'rotate');
      expect(recordedCalls.first.arguments, {
        'path': '/input/video.mp4',
        'degrees': 270,
      });
    });

    test('crop invokes channel with pixels rectangle', () async {
      final result = await engine.crop(
        path: '/input/video.mp4',
        left: 0,
        top: 0,
        width: 1080,
        height: 1920,
      );

      expect(result, '/output/cropped.mp4');
      expect(recordedCalls.first.method, 'crop');
      expect(recordedCalls.first.arguments, {
        'path': '/input/video.mp4',
        'left': 0,
        'top': 0,
        'width': 1080,
        'height': 1920,
      });
    });

    test('getLoudnessSamples returns doubles list', () async {
      final samples = await engine.getLoudnessSamples('/input/video.mp4');

      expect(samples, [0.1, 0.4, 0.9]);
      expect(recordedCalls.first.method, 'getLoudnessSamples');
      expect(recordedCalls.first.arguments, {'path': '/input/video.mp4'});
    });

    test('cancelExport invokes channel', () async {
      await engine.cancelExport();

      expect(recordedCalls.length, 1);
      expect(recordedCalls.first.method, 'cancelExport');
    });

    test('export serializes captions and streams progress events', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, sink) {
                sink.success({'progress': 0.0, 'outputPath': null});
                sink.success({'progress': 0.25, 'outputPath': null});
                sink.success({'progress': 0.5, 'outputPath': null});
                sink.success({'progress': 0.75, 'outputPath': null});
                sink.success({
                  'progress': 1.0,
                  'outputPath': '/output/final.mp4',
                });
                sink.endOfStream();
              },
            ),
          );

      const caption = Caption(
        id: 'cap_1',
        startMs: 100,
        endMs: 800,
        text: 'Hello PitchCut',
      );

      final events = await engine
          .export(
            clipPaths: ['/c1.mp4', '/c2.mp4'],
            captions: [caption],
            targetHeight: 1080,
          )
          .toList();

      expect(events.length, 5);
      expectSuccessfulExportEvents(events, [0.0, 0.25, 0.5, 0.75, 1.0]);
      expect(events.last.outputPath, '/output/final.mp4');

      expect(recordedCalls.length, 1);
      expect(recordedCalls.first.method, 'export');
      expect(recordedCalls.first.arguments['clipPaths'], [
        '/c1.mp4',
        '/c2.mp4',
      ]);
      expect(recordedCalls.first.arguments['targetHeight'], 1080);
      expect(recordedCalls.first.arguments['captions'], [
        {'startMs': 100, 'endMs': 800, 'text': 'Hello PitchCut'},
      ]);
    });

    test('PlatformException passes through with contract error code', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            throw PlatformException(
              code: 'UNSUPPORTED_FORMAT',
              message: 'Unsupported video codec',
            );
          });

      expect(
        () => engine.trim(path: '/bad.avi', startMs: 0, endMs: 500),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'UNSUPPORTED_FORMAT',
          ),
        ),
      );
    });
  });
}
