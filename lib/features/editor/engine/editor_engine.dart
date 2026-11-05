import 'package:pitchcut_ai/models/caption.dart';

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
  Future<List<String>> cut({
    required String path,
    required int atMs,
  });

  /// Joins clips end to end, in the order given.
  Future<String> merge({
    required List<String> paths,
  });

  /// degrees is 90, 180 or 270 (clockwise).
  Future<String> rotate({
    required String path,
    required int degrees,
  });

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

  Future<void> cancelExport();

  /// One loudness value (0.0 silent to 1.0 loud) every 100 ms.
  Future<List<double>> getLoudnessSamples(String path);
}

