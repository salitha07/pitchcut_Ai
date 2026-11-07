import 'dart:typed_data';

import 'crop_rect.dart';

class VideoClip {
  const VideoClip({
    required this.path,
    required this.name,
    required this.duration,
    this.sourceStart = Duration.zero,
    Duration? sourceDuration,
    this.thumbnail,
    this.rotationDegrees = 0,
    this.crop,
  }) : sourceDuration = sourceDuration ?? duration;

  final String path;
  final String name;
  final Duration duration;
  final Duration sourceStart;
  final Duration sourceDuration;
  final Uint8List? thumbnail;
  final int rotationDegrees;
  final CropRect? crop;

  Duration get sourceEnd => sourceStart + duration;

  VideoClip copyWith({
    String? path,
    String? name,
    Duration? duration,
    Duration? sourceStart,
    Duration? sourceDuration,
    Uint8List? thumbnail,
    int? rotationDegrees,
    CropRect? crop,
  }) => VideoClip(
    path: path ?? this.path,
    name: name ?? this.name,
    duration: duration ?? this.duration,
    sourceStart: sourceStart ?? this.sourceStart,
    sourceDuration: sourceDuration ?? this.sourceDuration,
    thumbnail: thumbnail ?? this.thumbnail,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    crop: crop ?? this.crop,
  );

  Map<String, Object> toJson() => {
    'path': path,
    'name': name,
    'durationMs': duration.inMilliseconds,
    'sourceStartMs': sourceStart.inMilliseconds,
    'sourceDurationMs': sourceDuration.inMilliseconds,
    'rotationDegrees': rotationDegrees,
    if (crop != null) 'crop': crop!.toJson(),
  };

  factory VideoClip.fromJson(Map<String, Object?> json) => VideoClip(
    path: json['path']! as String,
    name: json['name']! as String,
    duration: Duration(milliseconds: json['durationMs']! as int),
    sourceStart: Duration(milliseconds: json['sourceStartMs'] as int? ?? 0),
    sourceDuration: Duration(
      milliseconds:
          json['sourceDurationMs'] as int? ?? json['durationMs']! as int,
    ),
    rotationDegrees: json['rotationDegrees'] as int? ?? 0,
    crop: json['crop'] is Map<String, dynamic>
        ? CropRect.fromJson(json['crop']! as Map<String, dynamic>)
        : null,
  );
}
