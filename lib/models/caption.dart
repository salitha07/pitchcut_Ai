
class Caption {
  final String id;
  final int startMs;
  final int endMs;
  final String text;

  /// ID of the original source video.
  /// Null for manually created captions or older captions.
  final String? sourceClipId;

  /// Caption start time in the original source video.
  /// Null for manually created captions or older captions.
  final int? sourceStartMs;

  const Caption({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.text,
    this.sourceClipId,
    this.sourceStartMs,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'startMs': startMs,
    'endMs': endMs,
    'text': text,
    'sourceClipId': sourceClipId,
    'sourceStartMs': sourceStartMs,
  };

  factory Caption.fromJson(Map<String, dynamic> json) {
    return Caption(
      id: json['id'] as String,
      startMs: json['startMs'] as int,
      endMs: json['endMs'] as int,
      text: json['text'] as String,
      sourceClipId: json['sourceClipId'] as String?,
      sourceStartMs: json['sourceStartMs'] as int?,
    );
  }

  Caption copyWith({
    String? id,
    int? startMs,
    int? endMs,
    String? text,
    String? sourceClipId,
    int? sourceStartMs,
  }) {
    return Caption(
      id: id ?? this.id,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      text: text ?? this.text,
      sourceClipId: sourceClipId ?? this.sourceClipId,
      sourceStartMs: sourceStartMs ?? this.sourceStartMs,
    );
  }
}
