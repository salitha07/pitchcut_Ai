import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/video_clip.dart';

class VideoTrimService {
  static const _channel = MethodChannel('pitchcut_ai/video_trim');

  Future<Uint8List?> generateThumbnail(
    String inputPath, {
    Duration time = Duration.zero,
  }) => _channel.invokeMethod<Uint8List>('generateThumbnail', {
    'inputPath': inputPath,
    'timeMs': time.inMilliseconds,
  });

  Future<String> trim({
    required String inputPath,
    required Duration start,
    required Duration end,
  }) async {
    if (start < Duration.zero || end <= start) {
      throw ArgumentError('Trim end must be after trim start.');
    }
    final outputDirectory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final outputPath = '${outputDirectory.path}/trimmed_$timestamp.mp4';
    final result = await _channel.invokeMethod<String>('trimVideo', {
      'inputPath': inputPath,
      'outputPath': outputPath,
      'startMs': start.inMilliseconds,
      'endMs': end.inMilliseconds,
    });
    if (result == null || result.isEmpty) {
      throw PlatformException(
        code: 'trim_failed',
        message: 'The video trimmer did not return an output file.',
      );
    }
    return result;
  }

  Future<String> exportTimeline(List<VideoClip> clips) async {
    if (clips.isEmpty) throw ArgumentError('There are no clips to export.');
    final outputDirectory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final outputPath = '${outputDirectory.path}/video_edit_$timestamp.mp4';
    final result = await _channel.invokeMethod<String>('exportTimeline', {
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
      'outputPath': outputPath,
    });
    if (result == null || result.isEmpty) {
      throw PlatformException(
        code: 'export_failed',
        message: 'The editor did not return an exported video.',
      );
    }
    return result;
  }
}
