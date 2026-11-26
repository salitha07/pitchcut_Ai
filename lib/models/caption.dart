class Caption {
  final String id;
  final int startMs;
  final int endMs;
  final String text;

  const Caption({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'startMs': startMs,
    'endMs': endMs,
    'text': text,
  };

  factory Caption.fromJson(Map<String, dynamic> json) {
    return Caption(
      id: json['id'] as String,
      startMs: json['startMs'] as int,
      endMs: json['endMs'] as int,
      text: json['text'] as String,
    );
  }

  Caption copyWith({String? id, int? startMs, int? endMs, String? text}) {
    return Caption(
      id: id ?? this.id,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      text: text ?? this.text,
    );
  }
}
