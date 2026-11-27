
enum ClipBackgroundType {
  none,
  image,
  solid,
  gradient,
  preset,
}

class ClipBackground {
  const ClipBackground({
    required this.type,
    this.imagePath,
    this.solidColor,
    this.gradientStartColor,
    this.gradientEndColor,
    this.presetId,
  });

  final ClipBackgroundType type;
  final String? imagePath;
  final int? solidColor;
  final int? gradientStartColor;
  final int? gradientEndColor;
  final String? presetId;

  Map<String, Object> toJson() => {
        'type': type.name,
        'imagePath': ?imagePath,
        'solidColor': ?solidColor,
        'gradientStartColor': ?gradientStartColor,
        'gradientEndColor': ?gradientEndColor,
        'presetId': ?presetId,
      };

  factory ClipBackground.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'none';

    final type = ClipBackgroundType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => ClipBackgroundType.none,
    );

    return ClipBackground(
      type: type,
      imagePath: json['imagePath'] as String?,
      solidColor: json['solidColor'] as int?,
      gradientStartColor: json['gradientStartColor'] as int?,
      gradientEndColor: json['gradientEndColor'] as int?,
      presetId: json['presetId'] as String?,
    );
  }

  static const none = ClipBackground(
    type: ClipBackgroundType.none,
  );

  ClipBackground copyWith({
    ClipBackgroundType? type,
    String? imagePath,
    int? solidColor,
    int? gradientStartColor,
    int? gradientEndColor,
    String? presetId,
  }) {
    return ClipBackground(
      type: type ?? this.type,
      imagePath: imagePath ?? this.imagePath,
      solidColor: solidColor ?? this.solidColor,
      gradientStartColor:
          gradientStartColor ?? this.gradientStartColor,
      gradientEndColor:
          gradientEndColor ?? this.gradientEndColor,
      presetId: presetId ?? this.presetId,
    );
  }

  // Compare background settings by their actual values.
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ClipBackground &&
            type == other.type &&
            imagePath == other.imagePath &&
            solidColor == other.solidColor &&
            gradientStartColor == other.gradientStartColor &&
            gradientEndColor == other.gradientEndColor &&
            presetId == other.presetId;
  }

  // Generate a hash from all background properties.
  @override
  int get hashCode => Object.hash(
        type,
        imagePath,
        solidColor,
        gradientStartColor,
        gradientEndColor,
        presetId,
      );
}
