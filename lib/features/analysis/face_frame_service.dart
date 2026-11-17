import 'package:flutter/services.dart';

class FaceFrameService {
  static const MethodChannel _channel = MethodChannel('pitchcut_ai/video_trim');

  Future<List<String>> extractFrames(
    String videoPath, {
    int intervalMs = 1000,
  }) async {
    if (intervalMs <= 0) {
      throw ArgumentError.value(
        intervalMs,
        'intervalMs',
        'Must be greater than zero.',
      );
    }

    final paths = await _channel
        .invokeListMethod<String>('extractFrames', {
          'inputPath': videoPath,
          'intervalMs': intervalMs,
        })
        .timeout(const Duration(seconds: 60));

    return paths ?? <String>[];
  }
}
