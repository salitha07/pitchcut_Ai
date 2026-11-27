import 'package:flutter/services.dart';
import 'package:pitchcut_ai/features/editor/models/clip_background.dart';

class BackgroundPreviewService {
  static const MethodChannel _channel = MethodChannel('pitchcut/editor');

  Future<Uint8List?> generate({
    required String path,
    required Duration position,
    required ClipBackground background,
  }) async {
    if (background.type == ClipBackgroundType.none) {
      return null;
    }

    final result = await _channel.invokeMethod<Uint8List>(
      'generateBackgroundPreview',
      {
        'path': path,
        'timeMs': position.inMilliseconds,
        'background': background.toJson(),
      },
    );

    return result;
  }
}
