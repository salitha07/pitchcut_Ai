import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../models/video_clip.dart';
import '../models/video_export_state.dart';
import 'video_export_controller.dart';

/// Native Android Media3 / iOS AVFoundation export bridge.
class VideoExportService implements VideoExportBackend {
  static const _control = MethodChannel('pitchcut_ai/video_trim');
  static const _events = EventChannel('pitchcut_ai/video_export_progress');

  String? _activeExportId;
  bool _cancelRequested = false;
  bool _nativeStarted = false;

  @override
  Future<String> exportTimeline(
    List<VideoClip> clips,
    VideoExportQuality quality, {
    required ExportProgressCallback onProgress,
  }) async {
    if (clips.isEmpty) throw ArgumentError('There are no clips to export.');
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final outputPath = '${directory.path}/video_export_$timestamp.mp4';
    final exportId = timestamp.toString();
    _activeExportId = exportId;
    _cancelRequested = false;
    _nativeStarted = false;
    final ready = Completer<void>();

    final progressSubscription = _events.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        if (event['type'] == 'ready') {
          if (!ready.isCompleted) ready.complete();
          return;
        }
        if (event['exportId'] != exportId || event['type'] != 'progress')
          return;
        final progress = event['progress'];
        if (progress is num) onProgress(progress.toDouble());
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!ready.isCompleted) ready.completeError(error, stackTrace);
      },
    );

    try {
      await ready.future.timeout(const Duration(seconds: 5));
      if (_cancelRequested) throw const VideoExportCancelled();
      _nativeStarted = true;
      final result = await _control.invokeMethod<String>(
        'startExportTimeline',
        {
          'exportId': exportId,
          'outputPath': outputPath,
          'qualityHeight': quality.height,
          'clips': clips
              .map(
                (clip) => {
                  'inputPath': clip.path,
                  'startMs': clip.sourceStart.inMilliseconds,
                  'endMs': clip.sourceEnd.inMilliseconds,
                  'rotationDegrees': clip.rotationDegrees,
                  if (clip.crop != null) 'crop': clip.crop!.toJson(),
                },
              )
              .toList(growable: false),
        },
      );
      if (result == null || result.isEmpty) {
        throw StateError('The exporter did not return an output file.');
      }
      return result;
    } on PlatformException catch (error) {
      if (error.code == 'export_cancelled') throw const VideoExportCancelled();
      throw StateError(error.message ?? 'Video export failed (${error.code}).');
    } finally {
      await progressSubscription.cancel();
      _activeExportId = null;
      _nativeStarted = false;
      _cancelRequested = false;
    }
  }

  @override
  Future<void> cancelExport() async {
    final exportId = _activeExportId;
    if (exportId == null) return;
    _cancelRequested = true;
    if (!_nativeStarted) return;
    await _control.invokeMethod<void>('cancelExport', {'exportId': exportId});
  }

  @override
  Future<bool> verifyOutput(String path) async {
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) return false;
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      return controller.value.isInitialized &&
          !controller.value.hasError &&
          controller.value.duration > Duration.zero &&
          controller.value.size.width > 0 &&
          controller.value.size.height > 0;
    } catch (_) {
      return false;
    } finally {
      await controller.dispose();
    }
  }

  @override
  Future<void> discardOutput(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
