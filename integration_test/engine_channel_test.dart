import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pitchcut_ai/features/editor/engine/editor_engine.dart';
import 'package:pitchcut_ai/features/editor/engine/method_channel_editor_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final engine = MethodChannelEditorEngine();

  testWidgets('trim reaches native channel and reports missing file', (
    tester,
  ) async {
    await _expectPlatformError(
      () async {
        await engine.trim(
          path: _missingPath('trim'),
          startMs: 0,
          endMs: 1000,
        );
      },
      'FILE_NOT_FOUND',
    );
  });

  testWidgets('loudness reaches native channel and reports missing file', (
    tester,
  ) async {
    await _expectPlatformError(
      () async {
        await engine.getLoudnessSamples(_missingPath('loudness'));
      },
      'FILE_NOT_FOUND',
    );
  });

  testWidgets('merge reaches native channel and reports missing file', (
    tester,
  ) async {
    await _expectPlatformError(
      () async {
        await engine.merge(paths: [_missingPath('merge')]);
      },
      'FILE_NOT_FOUND',
    );
  });

  testWidgets('rotate reaches native channel and rejects invalid degrees', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'pitchcut-channel-smoke-',
    );
    final existingPath = '${directory.path}${Platform.pathSeparator}source';
    await File(existingPath).writeAsString('not a video');

    try {
      await _expectPlatformError(
        () async {
          await engine.rotate(path: existingPath, degrees: 45);
        },
        'INVALID_RANGE',
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  testWidgets('cancelExport with no active export completes normally', (
    tester,
  ) async {
    await _expectNoMissingPlugin(() => engine.cancelExport());
  });

  testWidgets('export with no clips ends with an error', (tester) async {
    await _expectExportError(engine.export(clipPaths: const []));
  });
}

String _missingPath(String operation) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'pitchcut-$operation-missing-${DateTime.now().microsecondsSinceEpoch}.mp4';

Future<void> _expectPlatformError(
  Future<void> Function() operation,
  String expectedCode,
) async {
  try {
    await operation();
  } on MissingPluginException catch (error) {
    fail('CHANNEL NOT REGISTERED: $error');
  } on PlatformException catch (error) {
    _failIfChannelNotRegistered(error);
    expect(
      error.code,
      expectedCode,
      reason: 'Unexpected native error: ${error.message}',
    );
    return;
  }
  fail('Expected PlatformException with code $expectedCode.');
}

Future<void> _expectNoMissingPlugin(Future<void> Function() operation) async {
  try {
    await operation();
  } on MissingPluginException catch (error) {
    fail('CHANNEL NOT REGISTERED: $error');
  } on PlatformException catch (error) {
    _failIfChannelNotRegistered(error);
    rethrow;
  }
}

Future<void> _expectExportError(Stream<ExportEvent> events) async {
  try {
    await for (final _ in events) {
      // The empty clip list must fail before producing a successful export.
    }
  } on MissingPluginException catch (error) {
    fail('CHANNEL NOT REGISTERED: $error');
  } on PlatformException catch (error) {
    _failIfChannelNotRegistered(error);
    return;
  }
  fail('Expected export with an empty clip list to end with an error.');
}

void _failIfChannelNotRegistered(PlatformException error) {
  final message = error.message ?? '';
  if (message.contains('MissingPluginException') ||
      message.toLowerCase().contains('not implemented')) {
    fail('CHANNEL NOT REGISTERED: ${error.code}: $message');
  }
}
