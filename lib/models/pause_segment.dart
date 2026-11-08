class PauseSegment {
  final int startMs;
  final int endMs;

  const PauseSegment({required this.startMs, required this.endMs});

  Map<String, dynamic> toJson() => {'startMs': startMs, 'endMs': endMs};

  factory PauseSegment.fromJson(Map<String, dynamic> json) {
    return PauseSegment(
      startMs: json['startMs'] as int,
      endMs: json['endMs'] as int,
    );
  }

  PauseSegment copyWith({int? startMs, int? endMs}) {
    return PauseSegment(
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
    );
  }
}
