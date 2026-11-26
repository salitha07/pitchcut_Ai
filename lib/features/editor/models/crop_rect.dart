/// A crop rectangle in normalized video coordinates (0.0 to 1.0).
class CropRect {
  const CropRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  static const full = CropRect(left: 0, top: 0, right: 1, bottom: 1);
  static const minimumSize = 0.05;

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  bool get isFull => this == full;
  bool get isValid =>
      left >= 0 &&
      top >= 0 &&
      right <= 1 &&
      bottom <= 1 &&
      width + 1e-9 >= minimumSize &&
      height + 1e-9 >= minimumSize;

  CropRect move(double dx, double dy) {
    final newLeft = (left + dx).clamp(0.0, 1.0 - width).toDouble();
    final newTop = (top + dy).clamp(0.0, 1.0 - height).toDouble();
    return CropRect(
      left: newLeft,
      top: newTop,
      right: newLeft + width,
      bottom: newTop + height,
    );
  }

  CropRect resize({double? left, double? top, double? right, double? bottom}) {
    final newLeft = (left ?? this.left)
        .clamp(0.0, this.right - minimumSize)
        .toDouble();
    final newRight = (right ?? this.right)
        .clamp(newLeft + minimumSize, 1.0)
        .toDouble();
    final newTop = (top ?? this.top)
        .clamp(0.0, this.bottom - minimumSize)
        .toDouble();
    final newBottom = (bottom ?? this.bottom)
        .clamp(newTop + minimumSize, 1.0)
        .toDouble();
    return CropRect(
      left: newLeft,
      top: newTop,
      right: newRight,
      bottom: newBottom,
    );
  }

  Map<String, double> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  factory CropRect.fromJson(Map<String, dynamic> json) => CropRect(
    left: (json['left'] as num).toDouble(),
    top: (json['top'] as num).toDouble(),
    right: (json['right'] as num).toDouble(),
    bottom: (json['bottom'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is CropRect &&
      left == other.left &&
      top == other.top &&
      right == other.right &&
      bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}
