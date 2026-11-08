import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pitchcut_ai/models/caption.dart';

import 'editor_engine.dart';

/// An implementation of [EditorEngine] that communicates with the native
/// Android Media3 editing engine over Flutter platform channels.
///
/// Uses the `pitchcut/editor` [MethodChannel] for editing commands and the
/// `pitchcut/editor/progress` [EventChannel] for streaming export progress.
class MethodChannelEditorEngine implements EditorEngine {
  static final Map<String, Object> _activeExportChannels = {};

  static const _contractErrorCodes = {
    'FILE_NOT_FOUND',
    'INVALID_RANGE',
    'UNSUPPORTED_FORMAT',
    'EXPORT_FAILED',
    'CANCELLED',
  };

  /// The [MethodChannel] used to invoke native editing commands.
  final MethodChannel _methodChannel;

  /// The [EventChannel] used to receive export progress events.
  final EventChannel _eventChannel;

  /// Creates a [MethodChannelEditorEngine] instance.
  ///
  /// Optional [methodChannel] and [eventChannel] parameters can be provided
  /// for dependency injection and testing.
  MethodChannelEditorEngine({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel = methodChannel ?? const MethodChannel('pitchcut/editor'),
       _eventChannel =
           eventChannel ?? const EventChannel('pitchcut/editor/progress');

  Future<Object?> _invokeNative(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _methodChannel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      throw _normalizePlatformException(error);
    } catch (error) {
      throw _asExportFailed(error);
    }
  }

  PlatformException _asExportFailed(Object error) => PlatformException(
    code: 'EXPORT_FAILED',
    message: 'Native method failed: $error',
  );

  PlatformException _normalizePlatformException(PlatformException error) {
    if (_contractErrorCodes.contains(error.code)) return error;
    return PlatformException(
      code: 'EXPORT_FAILED',
      message:
          'Native method failed with unknown error code '
          '"${error.code}": ${error.message ?? 'No message provided'}',
      details: error.details,
    );
  }

  String _requireOutputPath(String method, Object? result) {
    if (result is String && result.trim().isNotEmpty) return result;
    throw PlatformException(
      code: 'EXPORT_FAILED',
      message: 'Native $method returned an invalid output path.',
    );
  }

  /// Keeps the video segment between [startMs] and [endMs].
  ///
  /// Returns the absolute path of the newly trimmed video file.
  /// Throws [PlatformException] with contract error codes on failure.
  @override
  Future<String> trim({
    required String path,
    required int startMs,
    required int endMs,
  }) async {
    final result = await _invokeNative('trim', {
      'path': path,
      'startMs': startMs,
      'endMs': endMs,
    });
    return _requireOutputPath('trim', result);
  }

  /// Splits the video clip at [atMs] into two parts.
  ///
  /// Returns a two-element list `[firstPartPath, secondPartPath]`.
  /// Throws [PlatformException] with contract error codes on failure.
  @override
  Future<List<String>> cut({required String path, required int atMs}) async {
    final result = await _invokeNative('cut', {'path': path, 'atMs': atMs});
    if (result is List &&
        result.length == 2 &&
        result.every((item) => item is String && item.trim().isNotEmpty)) {
      return result.cast<String>();
    }
    throw PlatformException(
      code: 'EXPORT_FAILED',
      message: 'Native cut returned an invalid result; expected two non-empty paths.',
    );
  }

  /// Concatenates video clips in the provided [paths] end-to-end in order.
  ///
  /// Returns the absolute path of the merged output video file.
  /// Throws [PlatformException] with contract error codes on failure.
  @override
  Future<String> merge({required List<String> paths}) async {
    final result = await _invokeNative('merge', {'paths': paths});
    return _requireOutputPath('merge', result);
  }

  /// Rotates the video at [path] by [degrees] (90, 180, or 270 clockwise).
  ///
  /// Returns the absolute path of the rotated video file.
  /// Throws [PlatformException] with contract error codes on failure.
  @override
  Future<String> rotate({required String path, required int degrees}) async {
    final result = await _invokeNative('rotate', {
      'path': path,
      'degrees': degrees,
    });
    return _requireOutputPath('rotate', result);
  }

  /// Crops the video at [path] to the specified pixel rectangle.
  ///
  /// Returns the absolute path of the cropped video file.
  /// Throws [PlatformException] with contract error codes on failure.
  @override
  Future<String> crop({
    required String path,
    required int left,
    required int top,
    required int width,
    required int height,
  }) async {
    final result = await _invokeNative('crop', {
      'path': path,
      'left': left,
      'top': top,
      'width': width,
      'height': height,
    });
    return _requireOutputPath('crop', result);
  }

  /// Renders the final exported video from [clipPaths] with optional [captions]
  /// burned in and optional [targetHeight] (720 or 1080).
  ///
  /// Yields [ExportEvent] progress updates (0.0 to 1.0) and finishes with
  /// the output path populated on the final event.
  /// Throws [PlatformException] with contract error codes on failure.
  @override
  Stream<ExportEvent> export({
    required List<String> clipPaths,
    List<Caption> captions = const [],
    int? targetHeight,
  }) {
    final serializedCaptions = captions
        .map(
          (caption) => {
            'startMs': caption.startMs,
            'endMs': caption.endMs,
            'text': caption.text,
          },
        )
        .toList();

    return _exportStream('export', {
      'clipPaths': clipPaths,
      'captions': serializedCaptions,
      ...?(targetHeight == null ? null : {'targetHeight': targetHeight}),
    });
  }

  @override
  Stream<ExportEvent> exportTimeline({
    required List<EditorTimelineItem> items,
    required int targetHeight,
  }) {
    EditorEngine.validateTimelineExportRequest(
      items: items,
      targetHeight: targetHeight,
    );

    return _exportStream('exportTimeline', {
      'items': items.map((item) => item.toMap()).toList(growable: false),
      'targetHeight': targetHeight,
    });
  }

  Stream<ExportEvent> _exportStream(
    String method,
    Map<String, Object?> arguments,
  ) {
    late final StreamController<ExportEvent> controller;
    StreamSubscription<dynamic>? subscription;
    final exportLease = Object();
    var ownsExportChannel = false;
    var exportFinished = false;
    Future<void>? terminalCleanup;

    ExportEvent? parseExportEvent(dynamic event) {
      if (event is! Map) return null;
      final rawProgress = event['progress'];
      if (rawProgress is! num) return null;
      final progress = rawProgress.toDouble();
      if (!progress.isFinite || progress < 0.0 || progress > 1.0) {
        return null;
      }

      final rawOutputPath = event['outputPath'];
      if (rawOutputPath != null && rawOutputPath is! String) return null;
      final outputPath = rawOutputPath as String?;
      if (outputPath != null && progress != 1.0) return null;
      if (outputPath != null && outputPath.trim().isEmpty) return null;
      return ExportEvent(progress, outputPath);
    }

    Future<void> terminate({
      Object? primaryError,
      StackTrace? primaryStackTrace,
      bool cancelEventSubscription = false,
      bool cancelNativeExport = false,
    }) {
      if (terminalCleanup != null) return terminalCleanup!;

      // Set this before any await so competing terminal events cannot start a
      // second cleanup or replace the primary result.
      exportFinished = true;
      terminalCleanup = () async {
        Object? nativeCancellationError;
        StackTrace? nativeCancellationStackTrace;
        try {
          if (cancelEventSubscription) {
            try {
              await subscription?.cancel();
            } catch (_) {
              // EventChannel cancellation is secondary to the export result.
            }
          }
          if (cancelNativeExport) {
            try {
              await _invokeNative('cancelExport');
            } catch (error, stackTrace) {
              nativeCancellationError = error;
              nativeCancellationStackTrace = stackTrace;
            }
          }

          if (primaryError != null && !controller.isClosed) {
            controller.addError(primaryError, primaryStackTrace);
          }
          if (!controller.isClosed) {
            // Closing is synchronous; awaiting its future here can wait on the
            // downstream listener that is currently handling this terminal
            // event. The stream itself still receives its done notification.
            unawaited(controller.close().catchError((Object _) {}));
          }
        } finally {
          if (ownsExportChannel &&
              identical(
                _activeExportChannels[_eventChannel.name],
                exportLease,
              )) {
            _activeExportChannels.remove(_eventChannel.name);
            ownsExportChannel = false;
          }
        }

        // Preserve the existing listener-cancel behavior for a native cancel
        // failure, after the stream guard and output stream have been cleaned.
        if (nativeCancellationError != null) {
          Error.throwWithStackTrace(
            nativeCancellationError,
            nativeCancellationStackTrace!,
          );
        }
      }();
      return terminalCleanup!;
    }

    controller = StreamController<ExportEvent>(
      onListen: () async {
        final eventChannelName = _eventChannel.name;
        if (_activeExportChannels.containsKey(eventChannelName)) {
          exportFinished = true;
          controller.addError(
            PlatformException(
              code: 'EXPORT_FAILED',
              message: 'An export is already running.',
            ),
          );
          await controller.close();
          return;
        }
        _activeExportChannels[eventChannelName] = exportLease;
        ownsExportChannel = true;
        try {
          subscription = _eventChannel.receiveBroadcastStream().listen(
            (dynamic event) {
              if (exportFinished || controller.isClosed) return;
              final exportEvent = parseExportEvent(event);
              if (exportEvent == null) return;
              controller.add(exportEvent);
              if (exportEvent.outputPath != null) {
                unawaited(terminate(cancelEventSubscription: true));
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!exportFinished && !controller.isClosed) {
                unawaited(
                  terminate(
                    primaryError: _normalizeError(error),
                    primaryStackTrace: stackTrace,
                    cancelEventSubscription: true,
                  ),
                );
              }
            },
            onDone: () => unawaited(terminate()),
            cancelOnError: false,
          );

          await _invokeNative(method, arguments);
        } catch (e, st) {
          if (!exportFinished && !controller.isClosed) {
            await terminate(
              primaryError: _normalizeError(e),
              primaryStackTrace: st,
              cancelEventSubscription: true,
            );
          }
        }
      },
      onCancel: () async {
        final shouldCancelNative = !exportFinished;
        await terminate(
          cancelEventSubscription: true,
          cancelNativeExport: shouldCancelNative,
        );
      },
    );

    return controller.stream;
  }

  PlatformException _normalizeError(Object error) => error is PlatformException
      ? _normalizePlatformException(error)
      : _asExportFailed(error);

  /// Cancels an in-progress export operation.
  ///
  /// Completes normally when no export is running. An active export's stream
  /// receives a [PlatformException] with code `CANCELLED`.
  @override
  Future<void> cancelExport() async {
    await _invokeNative('cancelExport');
  }

  /// Retrieves normalized loudness samples (0.0 silent to 1.0 loud)
  /// calculated every 100 ms for the audio in the video at [path].
  ///
  /// Throws [PlatformException] with contract error codes on failure.
  @override
  Future<List<double>> getLoudnessSamples(String path) async {
    final result = await _invokeNative('getLoudnessSamples', {'path': path});
    if (result is List && result.every((sample) => sample is num)) {
      return result.map((sample) => (sample as num).toDouble()).toList();
    }
    throw PlatformException(
      code: 'EXPORT_FAILED',
      message: 'Native getLoudnessSamples returned a non-numeric result list.',
    );
  }
}
