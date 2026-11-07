import 'dart:typed_data';

class VideoClip {
  const VideoClip({
    required this.path,
    required this.name,
    required this.duration,
    this.sourceStart = Duration.zero,
    Duration? sourceDuration,
    this.thumbnail,
  }) : sourceDuration = sourceDuration ?? duration;

  final String path;
  final String name;
  final Duration duration;
  final Duration sourceStart;
  final Duration sourceDuration;
  final Uint8List? thumbnail;

  Duration get sourceEnd => sourceStart + duration;

  VideoClip copyWith({
    String? path,
    String? name,
    Duration? duration,
    Duration? sourceStart,
    Duration? sourceDuration,
    Uint8List? thumbnail,
  }) => VideoClip(
    path: path ?? this.path,
    name: name ?? this.name,
    duration: duration ?? this.duration,
    sourceStart: sourceStart ?? this.sourceStart,
    sourceDuration: sourceDuration ?? this.sourceDuration,
    thumbnail: thumbnail ?? this.thumbnail,
  );

  Map<String, Object> toJson() => {
    'path': path,
    'name': name,
    'durationMs': duration.inMilliseconds,
    'sourceStartMs': sourceStart.inMilliseconds,
    'sourceDurationMs': sourceDuration.inMilliseconds,
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
  );
}
