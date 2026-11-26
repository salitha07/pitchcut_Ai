class Clip {
  final String id;
  final String projectId;
  final String localPath;
  final int durationMs;
  final int width;
  final int height;
  final String? sensorDataPath;
  final int order;

  const Clip({
    required this.id,
    required this.projectId,
    required this.localPath,
    required this.durationMs,
    required this.width,
    required this.height,
    this.sensorDataPath,
    required this.order,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'localPath': localPath,
    'durationMs': durationMs,
    'width': width,
    'height': height,
    'sensorDataPath': sensorDataPath,
    'order': order,
  };

  factory Clip.fromJson(Map<String, dynamic> json) {
    return Clip(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      localPath: json['localPath'] as String,
      durationMs: json['durationMs'] as int,
      width: json['width'] as int,
      height: json['height'] as int,
      sensorDataPath: json['sensorDataPath'] as String?,
      order: json['order'] as int,
    );
  }

  Clip copyWith({
    String? id,
    String? projectId,
    String? localPath,
    int? durationMs,
    int? width,
    int? height,
    String? sensorDataPath,
    int? order,
    bool clearSensorDataPath = false,
  }) {
    return Clip(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      localPath: localPath ?? this.localPath,
      durationMs: durationMs ?? this.durationMs,
      width: width ?? this.width,
      height: height ?? this.height,
      sensorDataPath: clearSensorDataPath
          ? null
          : sensorDataPath ?? this.sensorDataPath,
      order: order ?? this.order,
    );
  }
}
