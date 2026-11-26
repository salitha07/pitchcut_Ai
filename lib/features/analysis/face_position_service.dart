import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Detects faces in extracted frames and evaluates their positioning.
class FacePositionService {
  const FacePositionService();

  /// Returns an average positioning score, or null if no faces are detected.
  Future<int?> analyseFrames(List<String> framePaths) async {
    if (framePaths.isEmpty) return null;

    final detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: false,
        enableContours: false,
      ),
    );

    final frameScores = <double>[];

    try {
      for (final path in framePaths) {
        final file = File(path);
        if (!await file.exists()) continue;

        final bytes = await file.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final imageWidth = frame.image.width.toDouble();
        final imageHeight = frame.image.height.toDouble();

        frame.image.dispose();
        codec.dispose();

        final inputImage = InputImage.fromFilePath(path);
        final faces = await detector.processImage(inputImage);

        if (faces.isEmpty || imageWidth <= 0 || imageHeight <= 0) {
          continue;
        }

        // Evaluate the largest detected face in each frame.
        faces.sort(
          (a, b) => b.boundingBox.width.compareTo(a.boundingBox.width),
        );

        final face = faces.first;
        final centerX = face.boundingBox.center.dx / imageWidth;
        final centerY = face.boundingBox.center.dy / imageHeight;

        // Target: horizontally centred and slightly above vertical centre.
        final horizontalDeviation = (centerX - 0.5).abs();
        final verticalDeviation = (centerY - 0.4).abs();

        final penalty = horizontalDeviation * 120 + verticalDeviation * 80;

        frameScores.add((100 - penalty).clamp(0.0, 100.0));
      }

      if (frameScores.isEmpty) return null;

      final average = frameScores.reduce((a, b) => a + b) / frameScores.length;

      return average.round().clamp(0, 100);
    } finally {
      await detector.close();
    }
  }
}
