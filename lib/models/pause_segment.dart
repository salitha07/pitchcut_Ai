class PauseSegment {
  final int startMs;
  final int endMs;
  final String? clipId;
  final int? clipIndex;

  const PauseSegment({
    required this.startMs,
    required this.endMs,
    this.clipId,
    this.clipIndex,
  });

  int get durationMs => endMs - startMs;

  bool get isValid => startMs >= 0 && endMs > startMs;

  Map<String, dynamic> toJson() => {
    'startMs': startMs,
    'endMs': endMs,
    if (clipId != null) 'clipId': clipId,
    if (clipIndex != null) 'clipIndex': clipIndex,
  };

  factory PauseSegment.fromJson(Map<String, dynamic> json) {
    return PauseSegment(
      startMs: json['startMs'] as int,
      endMs: json['endMs'] as int,
      clipId: json['clipId'] as String?,
      clipIndex: json['clipIndex'] as int?,
    );
  }

  PauseSegment copyWith({
    int? startMs,
    int? endMs,
    String? clipId,
    int? clipIndex,
  }) {
    return PauseSegment(
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      clipId: clipId ?? this.clipId,
      clipIndex: clipIndex ?? this.clipIndex,
    );
  }
}
