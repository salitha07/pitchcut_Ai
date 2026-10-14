import 'pause_segment.dart';

class PerformanceReport {
  final String id;
  final String projectId;
  final String createdAt;
  final int score;
  final List<PauseSegment> pauses;
  final int faceScore;
  final int stabilityScore;
  final int paceScore;
  final List<String> tips;

  const PerformanceReport({
    required this.id,
    required this.projectId,
    required this.createdAt,
    required this.score,
    this.pauses = const [],
    required this.faceScore,
    required this.stabilityScore,
    required this.paceScore,
    this.tips = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'createdAt': createdAt,
    'score': score,
    'pauses': pauses.map((pause) => pause.toJson()).toList(),
    'faceScore': faceScore,
    'stabilityScore': stabilityScore,
    'paceScore': paceScore,
    'tips': tips,
  };

  factory PerformanceReport.fromJson(Map<String, dynamic> json) {
    final rawPauses = json['pauses'] as List? ?? [];

    return PerformanceReport(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      createdAt: json['createdAt'] as String,
      score: json['score'] as int,
      pauses: rawPauses
          .map(
            (item) =>
                PauseSegment.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      faceScore: json['faceScore'] as int,
      stabilityScore: json['stabilityScore'] as int,
      paceScore: json['paceScore'] as int,
      tips: List<String>.from(json['tips'] as List? ?? []),
    );
  }

  PerformanceReport copyWith({
    String? id,
    String? projectId,
    String? createdAt,
    int? score,
    List<PauseSegment>? pauses,
    int? faceScore,
    int? stabilityScore,
    int? paceScore,
    List<String>? tips,
  }) {
    return PerformanceReport(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      createdAt: createdAt ?? this.createdAt,
      score: score ?? this.score,
      pauses: pauses ?? this.pauses,
      faceScore: faceScore ?? this.faceScore,
      stabilityScore: stabilityScore ?? this.stabilityScore,
      paceScore: paceScore ?? this.paceScore,
      tips: tips ?? this.tips,
    );
  }
}
