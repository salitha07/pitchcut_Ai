import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/engine/method_channel_editor_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('pitchcut/editor');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final engine = MethodChannelEditorEngine();

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> expectExportFailed(Future<Object?> Function() call) async {
    await expectLater(
      call(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'EXPORT_FAILED',
        ),
      ),
    );
  }

  Future<void> respondWith(Object? response) async {
    messenger.setMockMethodCallHandler(channel, (call) async => response);
  }

  test(
    'path-returning methods reject null, wrong-type and empty replies',
    () async {
      final calls = <Future<Object?> Function()>[
        () => engine.trim(path: '/in.mp4', startMs: 0, endMs: 1),
        () => engine.merge(paths: ['/in.mp4']),
        () => engine.rotate(path: '/in.mp4', degrees: 90),
        () => engine.crop(
          path: '/in.mp4',
          left: 0,
          top: 0,
          width: 10,
          height: 10,
        ),
      ];

      for (final invalidReply in <Object?>[null, 42, '', '   ']) {
        await respondWith(invalidReply);
        for (final call in calls) {
          await expectExportFailed(call);
        }
      }
    },
  );

  test(
    'cut rejects null, wrong type, wrong length and non-string members',
    () async {
      final invalidReplies = <Object?>[
        null,
        '/not-a-list.mp4',
        ['/only-one.mp4'],
        ['/first.mp4', '/second.mp4', '/third.mp4'],
        ['/first.mp4', 42],
        ['/first.mp4', ''],
      ];
      for (final reply in invalidReplies) {
        await respondWith(reply);
        await expectExportFailed(() => engine.cut(path: '/in.mp4', atMs: 100));
      }
    },
  );

  test(
    'loudness rejects null, wrong type and non-numeric list members',
    () async {
      for (final reply in <Object?>[
        null,
        'not-a-list',
        [0.2, 'bad'],
      ]) {
        await respondWith(reply);
        await expectExportFailed(() => engine.getLoudnessSamples('/in.mp4'));
      }
    },
  );

  test('converts integer loudness samples to doubles', () async {
    await respondWith([0, 1, 2]);
    expect(await engine.getLoudnessSamples('/in.mp4'), [0.0, 1.0, 2.0]);
  });

  test('preserves every contract PlatformException code', () async {
    for (final code in [
      'FILE_NOT_FOUND',
      'INVALID_RANGE',
      'UNSUPPORTED_FORMAT',
      'EXPORT_FAILED',
      'CANCELLED',
    ]) {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: code, message: 'cause'),
      );
      await expectLater(
        engine.trim(path: '/in.mp4', startMs: 0, endMs: 1),
        throwsA(
          isA<PlatformException>().having((error) => error.code, 'code', code),
        ),
      );
    }
  });

  test('converts unknown native error codes to EXPORT_FAILED', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(
        code: 'NATIVE_INTERNAL_ERROR',
        message: 'actual cause',
      ),
    );

    await expectExportFailed(
      () => engine.trim(path: '/in.mp4', startMs: 0, endMs: 1),
    );
  });

  test('converts non-PlatformException channel failures to EXPORT_FAILED',
      () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw StateError('unexpected channel failure'),
    );

    await expectExportFailed(
      () => engine.trim(path: '/in.mp4', startMs: 0, endMs: 1),
    );
  });
}
