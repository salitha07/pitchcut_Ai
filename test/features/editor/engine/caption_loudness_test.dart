import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/engine/method_channel_editor_engine.dart';
import 'package:pitchcut_ai/models/caption.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('pitchcut/editor');
  const eventChannel = EventChannel('pitchcut/editor/progress');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });

  test(
    'export sends caption text and its exact active interval to native code',
    () async {
      MethodCall? exportCall;
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            sink.success({'progress': 1.0, 'outputPath': '/output/final.mp4'});
            sink.endOfStream();
          },
        ),
      );
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'export') exportCall = call;
        return null;
      });

      await MethodChannelEditorEngine()
          .export(
            clipPaths: ['/input/video.mp4'],
            captions: const [
              Caption(
                id: 'caption-1',
                startMs: 1_500,
                endMs: 2_500,
                text: 'Test caption',
              ),
            ],
            targetHeight: 720,
          )
          .toList();

      expect(exportCall?.arguments, {
        'clipPaths': ['/input/video.mp4'],
        'captions': [
          {'startMs': 1_500, 'endMs': 2_500, 'text': 'Test caption'},
        ],
        'targetHeight': 720,
      });
    },
  );

  test('export preserves non-Latin and emoji caption text', () async {
    const text = 'සිංහල தமிழ் 🎬';
    MethodCall? exportCall;
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          sink.success({'progress': 1.0, 'outputPath': '/output/final.mp4'});
          sink.endOfStream();
        },
      ),
    );
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'export') exportCall = call;
      return null;
    });

    await MethodChannelEditorEngine()
        .export(
          clipPaths: ['/input/video.mp4'],
          captions: const [
            Caption(
              id: 'unicode-caption',
              startMs: 0,
              endMs: 3_000,
              text: text,
            ),
          ],
        )
        .toList();

    expect(exportCall?.arguments['captions'], [
      {'startMs': 0, 'endMs': 3_000, 'text': text},
    ]);
  });

  test(
    'export forwards invalid caption timing for native validation',
    () async {
      MethodCall? exportCall;
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (arguments, sink) {}),
      );
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'export') {
          exportCall = call;
          throw PlatformException(
            code: 'INVALID_RANGE',
            message: 'Caption endMs must be greater than startMs',
          );
        }
        return null;
      });

      await expectLater(
        MethodChannelEditorEngine()
            .export(
              clipPaths: ['/input/video.mp4'],
              captions: const [
                Caption(
                  id: 'invalid-caption',
                  startMs: 2_000,
                  endMs: 1_000,
                  text: 'Invalid interval',
                ),
              ],
            )
            .toList(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'INVALID_RANGE',
          ),
        ),
      );

      expect(exportCall?.arguments['captions'], [
        {'startMs': 2_000, 'endMs': 1_000, 'text': 'Invalid interval'},
      ]);
    },
  );

  test(
    'export forwards negative caption start for native validation',
    () async {
      MethodCall? exportCall;
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (arguments, sink) {}),
      );
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'export') {
          exportCall = call;
          throw PlatformException(
            code: 'INVALID_RANGE',
            message: 'Caption startMs must be non-negative',
          );
        }
        return null;
      });

      await expectLater(
        MethodChannelEditorEngine()
            .export(
              clipPaths: ['/input/video.mp4'],
              captions: const [
                Caption(
                  id: 'negative-caption',
                  startMs: -1,
                  endMs: 1_000,
                  text: 'Negative start',
                ),
              ],
            )
            .toList(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'INVALID_RANGE',
          ),
        ),
      );

      expect(exportCall?.arguments['captions'], [
        {'startMs': -1, 'endMs': 1_000, 'text': 'Negative start'},
      ]);
    },
  );

  test('export serializes an empty captions list', () async {
    MethodCall? exportCall;
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          sink.success({'progress': 1.0, 'outputPath': '/output/final.mp4'});
          sink.endOfStream();
        },
      ),
    );
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'export') exportCall = call;
      return null;
    });

    await MethodChannelEditorEngine()
        .export(clipPaths: ['/input/video.mp4'])
        .toList();

    expect(exportCall?.arguments['captions'], isEmpty);
  });

  test('loudness values are returned as normalized doubles', () async {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      expect(call.method, 'getLoudnessSamples');
      expect(call.arguments, {'path': '/input/video.mp4'});
      return [0, 0.25, 1];
    });

    final samples = await MethodChannelEditorEngine().getLoudnessSamples(
      '/input/video.mp4',
    );

    expect(samples, [0.0, 0.25, 1.0]);
    expect(samples.every((sample) => sample >= 0.0 && sample <= 1.0), isTrue);
  });

  test('loudness rejects a null native response', () async {
    messenger.setMockMethodCallHandler(methodChannel, (call) async => null);

    await expectLater(
      MethodChannelEditorEngine().getLoudnessSamples('/input/silent.mp4'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'EXPORT_FAILED',
        ),
      ),
    );
  });

  test('loudness errors preserve native error codes', () async {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      throw PlatformException(
        code: 'UNSUPPORTED_FORMAT',
        message: 'No audio track found',
      );
    });

    await expectLater(
      MethodChannelEditorEngine().getLoudnessSamples('/input/video.mp4'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'UNSUPPORTED_FORMAT',
        ),
      ),
    );
  });

  test('loudness parsing rejects non-numeric native samples', () async {
    messenger.setMockMethodCallHandler(
      methodChannel,
      (call) async => [0.25, 'not-a-number'],
    );

    await expectLater(
      MethodChannelEditorEngine().getLoudnessSamples('/input/video.mp4'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'EXPORT_FAILED',
        ),
      ),
    );
  });
}
