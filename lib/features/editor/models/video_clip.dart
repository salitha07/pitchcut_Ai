import 'dart:typed_data';

class VideoClip {
  const VideoClip({
    required this.path,
    required this.name,
    required this.duration,
    this.thumbnail,
  });

  final String path;
  final String name;
  final Duration duration;
  final Uint8List? thumbnail;
}
