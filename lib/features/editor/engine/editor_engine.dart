import 'package:pitchcut_ai/models/caption.dart';

/// Normalized crop bounds in the rotated frame, with the origin at top-left.
/// Each edge is in the inclusive range 0.0 to 1.0 and each dimension must be
/// at least 0.05 of the frame.
class EditorCrop {
  factory EditorCrop({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    final values = [left, top, right, bottom];
    if (values.any((value) => !value.isFinite) ||
        left < 0 ||
        top < 0 ||
        right > 1 ||
        bottom > 1 ||
        right <= left ||
        bottom <= top) {
      throw ArgumentError('Crop coordinates must form a normalized rectangle.');
    }
    if (right - left < minimumDimension || bottom - top < minimumDimension) {
      throw ArgumentError(
        'Crop width and height must each be at least $minimumDimension.',
      );
    }
    return EditorCrop._(left, top, right, bottom);
  }

  const EditorCrop._(this.left, this.top, this.right, this.bottom);

  static const minimumDimension = 0.05;

  final double left;
  final double top;
  final double right;
  final double bottom;

  Map<String, Object> toMap() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };
}

/// One ordered source segment in a timeline export request.
class EditorTimelineItem {
  factory EditorTimelineItem({
    required String path,
    required int startMs,
    required int endMs,
    int rotationDegrees = 0,
    EditorCrop? crop,
  }) {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'Must not be empty.');
    }
    if (startMs < 0 || endMs <= startMs) {
      throw ArgumentError(
        'Timeline item must have startMs >= 0 and endMs > startMs.',
      );
    }
    if (!const {0, 90, 180, 270}.contains(rotationDegrees)) {
      throw ArgumentError.value(
        rotationDegrees,
        'rotationDegrees',
        'Must be 0, 90, 180, or 270.',
      );
    }
    return EditorTimelineItem._(path, startMs, endMs, rotationDegrees, crop);
  }

  const EditorTimelineItem._(
    this.path,
    this.startMs,
    this.endMs,
    this.rotationDegrees,
    this.crop,
  );

  final String path;
  final int startMs;
  final int endMs;
  final int rotationDegrees;
  final EditorCrop? crop;

  Map<String, Object> toMap() => {
    'path': path,
    'startMs': startMs,
    'endMs': endMs,
    'rotationDegrees': rotationDegrees,
    if (crop != null) 'crop': crop!.toMap(),
  };
}

class ExportEvent {
  final double progress; // 0.0 to 1.0
  final String? outputPath; // set only on the final event

  const ExportEvent(this.progress, [this.outputPath]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportEvent &&
          runtimeType == other.runtimeType &&
          progress == other.progress &&
          outputPath == other.outputPath;

  @override
  int get hashCode => progress.hashCode ^ outputPath.hashCode;

  @override
  String toString() =>
      'ExportEvent(progress: $progress, outputPath: $outputPath)';
}

abstract class EditorEngine {
  /// Keeps the part between startMs and endMs. Returns the new file path.
  Future<String> trim({
    required String path,
    required int startMs,
    required int endMs,
  });

  /// Splits one clip at atMs. Returns [firstPartPath, secondPartPath].
  Future<List<String>> cut({required String path, required int atMs});

  /// Joins clips end to end, in the order given.
  Future<String> merge({required List<String> paths});

  /// degrees is 90, 180 or 270 (clockwise).
  Future<String> rotate({required String path, required int degrees});

  /// Crop rectangle in pixels of the source video.
  Future<String> crop({
    required String path,
    required int left,
    required int top,
    required int width,
    required int height,
  });

  /// Renders the final video. Captions are burned in when the list is not empty.
  Stream<ExportEvent> export({
    required List<String> clipPaths,
    List<Caption> captions = const [],
    int? targetHeight, // e.g. 720 or 1080
  });

  /// Renders ordered timeline segments with per-item trims and video effects.
  ///
  /// Repeated paths are valid for split segments. Crop bounds are normalized
  /// in the rotated frame; rotation is applied before crop. Source audio is
  /// preserved. [targetHeight] must be 480, 720, or 1080.
  Stream<ExportEvent> exportTimeline({
    required List<EditorTimelineItem> items,
    required int targetHeight,
  });

  static void validateTimelineExportRequest({
    required List<EditorTimelineItem> items,
    required int targetHeight,
  }) {
    if (items.isEmpty) {
      throw ArgumentError.value(items, 'items', 'Must not be empty.');
    }
    if (!const {480, 720, 1080}.contains(targetHeight)) {
      throw ArgumentError.value(
        targetHeight,
        'targetHeight',
        'Must be 480, 720, or 1080.',
      );
    }
  }

  Future<void> cancelExport();

  /// One loudness value (0.0 silent to 1.0 loud) every 100 ms.
  Future<List<double>> getLoudnessSamples(String path);
}
