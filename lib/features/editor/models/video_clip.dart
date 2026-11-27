
import 'dart:typed_data';

import 'clip_background.dart';
import 'crop_rect.dart';

class VideoClip {
  const VideoClip({
    required this.path,
    required this.name,
    required this.duration,
    this.sourceClipId,
    this.timelineItemId,
    this.sourceStart = Duration.zero,
    Duration? sourceDuration,
    this.thumbnail,
    this.rotationDegrees = 0,
    this.crop,
    this.background = ClipBackground.none,
  }) : sourceDuration = sourceDuration ?? duration;

  final String path;
  final String name;
  final Duration duration;
  final String? sourceClipId;
  final String? timelineItemId;
  final Duration sourceStart;
  final Duration sourceDuration;
  final Uint8List? thumbnail;
  final int rotationDegrees;
  final CropRect? crop;
  final ClipBackground background;

  Duration get sourceEnd => sourceStart + duration;

  VideoClip copyWith({
    String? path,
    String? name,
    Duration? duration,
    String? sourceClipId,
    String? timelineItemId,
    Duration? sourceStart,
    Duration? sourceDuration,
    Uint8List? thumbnail,
    int? rotationDegrees,
    CropRect? crop,
    bool clearCrop = false,
    ClipBackground? background,
  }) => VideoClip(
    path: path ?? this.path,
    name: name ?? this.name,
    duration: duration ?? this.duration,
    sourceClipId: sourceClipId ?? this.sourceClipId,
    timelineItemId: timelineItemId ?? this.timelineItemId,
    sourceStart: sourceStart ?? this.sourceStart,
    sourceDuration: sourceDuration ?? this.sourceDuration,
    thumbnail: thumbnail ?? this.thumbnail,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    crop: clearCrop ? null : (crop ?? this.crop),
    background: background ?? this.background,
  );

  Map<String, Object> toJson() => {
    'path': path,
    'name': name,
    'durationMs': duration.inMilliseconds,
    'sourceClipId': ?sourceClipId,
    'timelineItemId': ?timelineItemId,
    'sourceStartMs': sourceStart.inMilliseconds,
    'sourceDurationMs': sourceDuration.inMilliseconds,
    'rotationDegrees': rotationDegrees,
    if (crop != null) 'crop': crop!.toJson(),
    'background': background.toJson(),
  };

  factory VideoClip.fromJson(Map<String, Object?> json) => VideoClip(
    path: json['path']! as String,
    name: json['name']! as String,
    duration: Duration(milliseconds: json['durationMs']! as int),
    sourceClipId: json['sourceClipId'] as String?,
    timelineItemId: json['timelineItemId'] as String?,
    sourceStart: Duration(
      milliseconds: json['sourceStartMs'] as int? ?? 0,
    ),
    sourceDuration: Duration(
      milliseconds:
          json['sourceDurationMs'] as int? ??
          json['durationMs']! as int,
    ),
    rotationDegrees: json['rotationDegrees'] as int? ?? 0,
    crop: json['crop'] is Map
        ? CropRect.fromJson(
            Map<String, dynamic>.from(json['crop']! as Map),
          )
        : null,
    background: json['background'] is Map
        ? ClipBackground.fromJson(
            Map<String, dynamic>.from(json['background']! as Map),
          )
        : ClipBackground.none,
  );
}
