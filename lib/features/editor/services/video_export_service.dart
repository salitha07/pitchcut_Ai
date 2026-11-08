import 'dart:io';

import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../engine/editor_engine.dart';
import '../engine/method_channel_editor_engine.dart';
import '../models/crop_rect.dart';
import '../models/video_clip.dart';
import '../models/video_export_state.dart';
import 'video_export_controller.dart';

/// Adapts the M5 timeline to the shared editor engine export contract.
class VideoExportService implements VideoExportBackend {
  VideoExportService({EditorEngine? engine})
    : _engine = engine ?? MethodChannelEditorEngine();

  final EditorEngine _engine;
  bool _isExporting = false;
  bool _cancelRequested = false;

  @override
  Future<String> exportTimeline(
    List<VideoClip> clips,
    VideoExportQuality quality, {
    required ExportProgressCallback onProgress,
  }) async {
    if (clips.isEmpty) throw ArgumentError('There are no clips to export.');
    if (_isExporting) throw StateError('An export is already running.');
    _isExporting = true;
    _cancelRequested = false;

    try {
      final items = clips
          .map((clip) {
            final crop = clip.crop;
            return EditorTimelineItem(
              path: clip.path,
              startMs: clip.sourceStart.inMilliseconds,
              endMs: clip.sourceEnd.inMilliseconds,
              rotationDegrees: clip.rotationDegrees,
              crop: crop == null ? null : _engineCrop(crop),
            );
          })
          .toList(growable: false);
      String? outputPath;
      await for (final event in _engine.exportTimeline(
        items: items,
        targetHeight: quality.height,
      )) {
        onProgress(event.progress);
        if (event.outputPath != null) outputPath = event.outputPath;
      }
      if (_cancelRequested) {
        if (outputPath != null) await discardOutput(outputPath);
        throw const VideoExportCancelled();
      }
      if (outputPath == null || outputPath.isEmpty) {
        throw StateError('The exporter did not return an output file.');
      }
      return outputPath;
    } on PlatformException catch (error) {
      if (error.code == 'CANCELLED') throw const VideoExportCancelled();
      throw StateError(error.message ?? 'Video export failed (${error.code}).');
    } finally {
      _isExporting = false;
      _cancelRequested = false;
    }
  }

  EditorCrop _engineCrop(CropRect crop) {
    var left = crop.left;
    var right = crop.right;
    var top = crop.top;
    var bottom = crop.bottom;
    // M5 permits this tolerance at its minimum crop size. Expand only that
    // boundary case so both Dart and Kotlin's strict minimum checks agree.
    const tolerance = 1e-9;
    if (right - left < EditorCrop.minimumDimension &&
        right - left + tolerance >= EditorCrop.minimumDimension) {
      if (right + tolerance <= 1) {
        right += tolerance;
      } else {
        left -= tolerance;
      }
    }
    if (bottom - top < EditorCrop.minimumDimension &&
        bottom - top + tolerance >= EditorCrop.minimumDimension) {
      if (bottom + tolerance <= 1) {
        bottom += tolerance;
      } else {
        top -= tolerance;
      }
    }
    return EditorCrop(left: left, top: top, right: right, bottom: bottom);
  }

  @override
  Future<void> cancelExport() async {
    if (!_isExporting) return;
    _cancelRequested = true;
    await _engine.cancelExport();
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
