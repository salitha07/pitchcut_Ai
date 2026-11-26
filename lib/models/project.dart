class Project {
  final String id;
  final String userId;
  final String title;
  final String createdAt;
  final String updatedAt;
  final List<String> clipIds;
  final String? exportedVideoPath;
  final String? latestReportId;

  const Project({
    required this.id,
    required this.userId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.clipIds = const [],
    this.exportedVideoPath,
    this.latestReportId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'title': title,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'clipIds': clipIds,
    'exportedVideoPath': exportedVideoPath,
    'latestReportId': latestReportId,
  };

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
      clipIds: List<String>.from(json['clipIds'] as List? ?? []),
      exportedVideoPath: json['exportedVideoPath'] as String?,
      latestReportId: json['latestReportId'] as String?,
    );
  }

  Project copyWith({
    String? id,
    String? userId,
    String? title,
    String? createdAt,
    String? updatedAt,
    List<String>? clipIds,
    String? exportedVideoPath,
    String? latestReportId,
    bool clearExportedVideoPath = false,
    bool clearLatestReportId = false,
  }) {
    return Project(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      clipIds: clipIds ?? this.clipIds,
      exportedVideoPath: clearExportedVideoPath
          ? null
          : exportedVideoPath ?? this.exportedVideoPath,
      latestReportId: clearLatestReportId
          ? null
          : latestReportId ?? this.latestReportId,
    );
  }
}
