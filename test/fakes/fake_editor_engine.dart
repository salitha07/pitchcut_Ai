import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pitchcut_ai/features/editor/engine/editor_engine.dart';
import 'package:pitchcut_ai/models/caption.dart';

/// By default editing methods return their input path after [delay]. Set
/// [useSyntheticPaths] to true to return transformed-style dummy paths instead.
/// Export still streams progress and loudness returns a normalized sample list
/// in either mode.
///
/// Example:
/// ```dart
/// final engine = FakeEditorEngine(
///   delay: Duration.zero,
///   methodErrors: {'trim': 'INVALID_RANGE'},
///   useSyntheticPaths: true,
/// );
/// await engine.trim(path: '/video.mp4', startMs: 0, endMs: 1000);
/// ```
/// A mock implementation of [EditorEngine] used for testing and UI development
/// until the native Android Media3 implementation is complete.
///
/// Simulates asynchronous delays, supports contract-style pass-through results
/// or opt-in synthetic paths, and allows configuring contract error codes for
/// error UI verification.
class FakeEditorEngine implements EditorEngine {
  /// The simulated delay before returning results. Defaults to 50 ms.
  final Duration delay;

  /// Whether path-returning methods should return transformed-style dummy paths.
  ///
  /// Defaults to false, so path-preserving operations return their input path.
  final bool useSyntheticPaths;

  /// Global error code to throw on any operation (e.g. 'FILE_NOT_FOUND', 'EXPORT_FAILED').
  String? simulatedErrorCode;

  /// Method-specific error codes (e.g. {'trim': 'INVALID_RANGE', 'export': 'EXPORT_FAILED'}).
  final Map<String, String> simulatedMethodErrors = {};

  /// Name and arguments of the most recently called engine method.
  String? lastMethod;
  Map<String, Object?>? lastCallArguments;

  /// Active export controllers and their timers to support cancellation.
  final Map<StreamController<ExportEvent>, Timer?> _activeExports = {};

  FakeEditorEngine({
    this.delay = const Duration(milliseconds: 50),
    this.useSyntheticPaths = false,
    this.simulatedErrorCode,
    Map<String, String>? methodErrors,
  }) {
    if (methodErrors != null) {
      simulatedMethodErrors.addAll(methodErrors);
    }
  }

  /// Sets or clears an error code for a specific method (e.g. 'trim', 'cut', 'export').
  void setMethodError(String methodName, String? errorCode) {
    if (errorCode != null) {
      simulatedMethodErrors[methodName] = errorCode;
    } else {
      simulatedMethodErrors.remove(methodName);
    }
  }

  /// Clears all global and method-specific simulated errors.
  void clearErrors() {
    simulatedErrorCode = null;
    simulatedMethodErrors.clear();
  }

  void _recordCall(String method, Map<String, Object?> arguments) {
    lastMethod = method;
    lastCallArguments = Map<String, Object?>.unmodifiable(arguments);
  }

  void _throwConfiguredError(String methodName) {
    final configuredError =
        simulatedMethodErrors[methodName] ?? simulatedErrorCode;
    if (configuredError == null) return;
    final error = _normalizeErrorCode(configuredError);
    throw PlatformException(
      code: error,
      message: 'Simulated failure for $methodName: $error',
    );
  }

  Future<void> _simulateDelay(String methodName) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    _throwConfiguredError(methodName);
  }

  @override
  Future<String> trim({
    required String path,
    required int startMs,
    required int endMs,
  }) async {
    _recordCall('trim', {'path': path, 'startMs': startMs, 'endMs': endMs});
    await _simulateDelay('trim');
    if (!useSyntheticPaths) return path;
    return '${path.replaceAll('.mp4', '')}_trimmed_${startMs}_$endMs.mp4';
  }

  @override
  Future<List<String>> cut({required String path, required int atMs}) async {
    _recordCall('cut', {'path': path, 'atMs': atMs});
    await _simulateDelay('cut');
    if (!useSyntheticPaths) {
      if (path.trim().isNotEmpty) return [path, path];
      return ['/fake/cut_part1.mp4', '/fake/cut_part2.mp4'];
    }
    final basePath = path.replaceAll('.mp4', '');
    return [
      '${basePath}_part1_${atMs}ms.mp4',
      '${basePath}_part2_${atMs}ms.mp4',
    ];
  }

  @override
  Future<String> merge({required List<String> paths}) async {
    _recordCall('merge', {'paths': List<String>.of(paths)});
    await _simulateDelay('merge');
    if (!useSyntheticPaths) {
      return paths.isNotEmpty ? paths.first : '/fake/merged_output.mp4';
    }
    if (paths.isEmpty) {
      return '/storage/emulated/0/Movies/PitchCut/merged_output.mp4';
    }
    return '${paths.first.replaceAll('.mp4', '')}_merged.mp4';
  }

  @override
  Future<String> rotate({required String path, required int degrees}) async {
    _recordCall('rotate', {'path': path, 'degrees': degrees});
    await _simulateDelay('rotate');
    if (!useSyntheticPaths) return path;
    return '${path.replaceAll('.mp4', '')}_rot$degrees.mp4';
  }

  @override
  Future<String> crop({
    required String path,
    required int left,
    required int top,
    required int width,
    required int height,
  }) async {
    _recordCall('crop', {
      'path': path,
      'left': left,
      'top': top,
      'width': width,
      'height': height,
    });
    await _simulateDelay('crop');
    if (!useSyntheticPaths) return path;
    return '${path.replaceAll('.mp4', '')}_crop_${width}x$height.mp4';
  }

  /// Emits progress events in steps from 0.0 to 1.0.
  ///
  /// [outputPath] is null on all intermediate progress events and is only
  /// populated on the final event (progress == 1.0).
  /// Calling [cancelExport] stops the stream and emits a `CANCELLED` [PlatformException].
  @override
  Stream<ExportEvent> export({
    required List<String> clipPaths,
    List<Caption> captions = const [],
    int? targetHeight,
  }) {
    _recordCall('export', {
      'clipPaths': List<String>.of(clipPaths),
      'captions': List<Caption>.of(captions),
      'targetHeight': targetHeight,
    });

    late final StreamController<ExportEvent> controller;
    Timer? stepTimer;
    int stepIndex = 0;
    const progressSteps = [0.0, 0.25, 0.50, 0.75, 1.0];
    final stepDuration = Duration(
      milliseconds: delay.inMilliseconds > 0
          ? (delay.inMilliseconds / progressSteps.length).ceil()
          : 10,
    );

    void emitNextStep() {
      if (controller.isClosed) return;

      if (stepIndex >= progressSteps.length) {
        stepTimer?.cancel();
        _activeExports.remove(controller);
        if (!controller.isClosed) {
          controller.close();
        }
        return;
      }

      final progress = progressSteps[stepIndex];
      final isLast = stepIndex == progressSteps.length - 1;
      final outputPath = isLast ? _exportOutputPath(clipPaths) : null;

      controller.add(ExportEvent(progress, outputPath));
      stepIndex++;

      if (isLast) {
        stepTimer?.cancel();
        _activeExports.remove(controller);
        if (!controller.isClosed) {
          controller.close();
        }
      }
    }

    controller = StreamController<ExportEvent>(
      onListen: () {
        final error = simulatedMethodErrors['export'] ?? simulatedErrorCode;
        if (error != null) {
          controller.addError(
            PlatformException(
              code: _normalizeErrorCode(error),
              message:
                  'Simulated failure for export: ${_normalizeErrorCode(error)}',
            ),
          );
          controller.close();
          return;
        }

        stepTimer = Timer.periodic(stepDuration, (_) => emitNextStep());
        _activeExports[controller] = stepTimer;
      },
      onCancel: () {
        stepTimer?.cancel();
        _activeExports.remove(controller);
      },
    );

    return controller.stream;
  }

  /// Cancels any active export streams, emitting a `CANCELLED` [PlatformException]
  /// and terminating the stream.
  @override
  Future<void> cancelExport() async {
    _recordCall('cancelExport', const {});
    final activeEntries = _activeExports.entries.toList();
    if (activeEntries.isEmpty) return;
    _throwConfiguredError('cancelExport');

    for (final entry in activeEntries) {
      entry.value?.cancel();
      final controller = entry.key;
      if (!controller.isClosed) {
        controller.addError(
          PlatformException(
            code: 'CANCELLED',
            message: 'Export was cancelled.',
          ),
        );
        controller.close();
      }
    }
    _activeExports.clear();
  }

  @override
  Future<List<double>> getLoudnessSamples(String path) async {
    _recordCall('getLoudnessSamples', {'path': path});
    await _simulateDelay('getLoudnessSamples');
    // Return 50 plausible loudness values between 0.0 and 1.0 (one per 100 ms = 5.0 seconds)
    return List<double>.generate(50, (index) {
      final value = 0.45 + 0.35 * (index % 10 - 5).abs() / 5.0;
      return double.parse(value.clamp(0.0, 1.0).toStringAsFixed(2));
    });
  }

  String _exportOutputPath(List<String> clipPaths) {
    if (!useSyntheticPaths) {
      return clipPaths.isNotEmpty
          ? clipPaths.first
          : '/fake/exported_video.mp4';
    }
    return clipPaths.isNotEmpty
        ? '${clipPaths.first.replaceAll('.mp4', '')}_export.mp4'
        : '/storage/emulated/0/Movies/PitchCut/exported_video.mp4';
  }

  String _normalizeErrorCode(String code) =>
      _contractErrorCodes.contains(code) ? code : 'EXPORT_FAILED';

  static const _contractErrorCodes = {
    'FILE_NOT_FOUND',
    'INVALID_RANGE',
    'UNSUPPORTED_FORMAT',
    'EXPORT_FAILED',
    'CANCELLED',
  };
}
