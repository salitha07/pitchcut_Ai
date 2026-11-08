import 'dart:typed_data';

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
  }) : sourceDuration = sourceDuration ?? duration;

  final String path;
  final String name;
  final Duration duration;

  /// Stable M2 [Clip.id] for the original source, when this item came from M2.
  final String? sourceClipId;

  /// Stable identity for this particular timeline segment.
  final String? timelineItemId;
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
    String? sourceClipId,
    String? timelineItemId,
    Duration? sourceStart,
    Duration? sourceDuration,
    Uint8List? thumbnail,
    int? rotationDegrees,
    CropRect? crop,
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
    crop: crop ?? this.crop,
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
  };

  factory VideoClip.fromJson(Map<String, Object?> json) => VideoClip(
    path: json['path']! as String,
    name: json['name']! as String,
    duration: Duration(milliseconds: json['durationMs']! as int),
    sourceClipId: json['sourceClipId'] as String?,
    timelineItemId: json['timelineItemId'] as String?,
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
