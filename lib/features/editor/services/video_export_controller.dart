import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/video_clip.dart';
import '../models/video_export_state.dart';

typedef ExportProgressCallback = void Function(double progress);

abstract class VideoExportBackend {
  Future<String> exportTimeline(
    List<VideoClip> clips,
    VideoExportQuality quality, {
    required ExportProgressCallback onProgress,
  });

  Future<void> cancelExport();
  Future<bool> verifyOutput(String path);
  Future<void> discardOutput(String path);
}

class VideoExportCancelled implements Exception {
  const VideoExportCancelled();
}

/// Coordinates export state while delegating media work to a real platform backend.
class VideoExportController extends ChangeNotifier {
  VideoExportController({required this.backend});

  final VideoExportBackend backend;
  VideoExportState _state = const VideoExportState();
  VideoExportState get state => _state;
  bool _cancelRequested = false;

  Future<void> start(List<VideoClip> clips, VideoExportQuality quality) async {
    if (_state.isBusy || clips.isEmpty) return;
    _cancelRequested = false;
    String? outputPath;
    _setState(const VideoExportState(status: VideoExportStatus.exporting));
    try {
      final path = await backend.exportTimeline(
        List.unmodifiable(clips),
        quality,
        onProgress: (progress) {
          if (_cancelRequested ||
              _state.status != VideoExportStatus.exporting) {
            return;
          }
          final value = progress.clamp(0.0, 1.0).toDouble();
          final previous = _state.progress ?? 0;
          _setState(
            VideoExportState(
              status: VideoExportStatus.exporting,
              progress: value < previous ? previous : value,
            ),
          );
        },
      );
      outputPath = path;
      if (_cancelRequested) {
        await backend.discardOutput(path);
        _setState(const VideoExportState(status: VideoExportStatus.cancelled));
        return;
      }
      if (!await backend.verifyOutput(path)) {
        throw StateError(
          'The exported video could not be verified as playable.',
        );
      }
      if (_cancelRequested) {
        await backend.discardOutput(path);
        _setState(const VideoExportState(status: VideoExportStatus.cancelled));
        return;
      }
      _setState(
        VideoExportState(
          status: VideoExportStatus.succeeded,
          progress: 1,
          outputPath: path,
        ),
      );
    } on VideoExportCancelled {
      _setState(const VideoExportState(status: VideoExportStatus.cancelled));
    } catch (error) {
      if (outputPath != null) {
        try {
          await backend.discardOutput(outputPath);
        } catch (_) {
          // Keep the export error visible if best-effort cleanup also fails.
        }
      }
      if (_cancelRequested) {
        _setState(const VideoExportState(status: VideoExportStatus.cancelled));
      } else {
        _setState(
          VideoExportState(
            status: VideoExportStatus.failed,
            errorMessage: _errorMessage(error),
          ),
        );
      }
    }
  }

  Future<void> cancel() async {
    if (_state.status != VideoExportStatus.exporting) return;
    _cancelRequested = true;
    _setState(
      VideoExportState(
        status: VideoExportStatus.cancelling,
        progress: _state.progress,
      ),
    );
    try {
      await backend.cancelExport();
    } catch (error) {
      _setState(
        VideoExportState(
          status: VideoExportStatus.cancelling,
          progress: _state.progress,
          errorMessage: 'Could not cancel the export: ${_errorMessage(error)}',
        ),
      );
    }
  }

  String _errorMessage(Object error) {
    final message = error.toString();
    return message.startsWith('Bad state: ')
        ? message.substring('Bad state: '.length)
        : message;
  }

  void _setState(VideoExportState state) {
    _state = state;
    notifyListeners();
  }
}
