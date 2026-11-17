import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../models/clip.dart';

/// Calculates camera stability from recorded motion sensor samples.
class StabilityAnalysisService {
  const StabilityAnalysisService({
    this.maxAngularSpeed = 0.5,
    this.maxAccelerationDeviation = 3.0,
  }) : assert(maxAngularSpeed > 0),
       assert(maxAccelerationDeviation > 0);

  /// Initial tuning thresholds. Validate with real sample videos.
  final double maxAngularSpeed;
  final double maxAccelerationDeviation;

  /// Returns null when sensor data is unavailable.
  Future<int?> analyse(Clip clip) async {
    final sensorPath = clip.sensorDataPath;

    if (sensorPath == null || sensorPath.trim().isEmpty) {
      return null;
    }

    final file = File(sensorPath);

    if (!await file.exists()) {
      return null;
    }

    final decoded = jsonDecode(await file.readAsString());

    if (decoded is! List) {
      throw const FormatException('Sensor data must be a JSON list.');
    }

    final samples = <Map<String, dynamic>>[];

    for (final item in decoded) {
      if (item is! Map) {
        throw const FormatException('Invalid sensor sample.');
      }

      samples.add(Map<String, dynamic>.from(item));
    }

    return calculateScore(samples);
  }

  /// Calculates a score from validated sensor samples.
  ///
  /// Accelerometer magnitude is compared with gravity (9.81 m/s²).
  /// Gyroscope magnitude represents rotational movement in rad/s.
  int? calculateScore(List<Map<String, dynamic>> samples) {
    if (samples.isEmpty) return null;

    double totalAngularSpeed = 0;
    double totalAccelerationDeviation = 0;

    int? previousTimestamp;

    for (final sample in samples) {
      const requiredKeys = {'tMs', 'ax', 'ay', 'az', 'gx', 'gy', 'gz'};

      if (sample.keys.toSet().difference(requiredKeys).isNotEmpty ||
          requiredKeys.difference(sample.keys.toSet()).isNotEmpty) {
        return null;
      }

      final timestamp = sample['tMs'];
      if (timestamp is! int ||
          timestamp < 0 ||
          (previousTimestamp != null && timestamp <= previousTimestamp)) {
        return null;
      }
      previousTimestamp = timestamp;

      final values = <String>[
        'ax',
        'ay',
        'az',
        'gx',
        'gy',
        'gz',
      ].map((key) => sample[key]).toList();

      if (values.any((value) => value is! num || !value.isFinite)) {
        return null;
      }

      final ax = (sample['ax'] as num).toDouble();
      final ay = (sample['ay'] as num).toDouble();
      final az = (sample['az'] as num).toDouble();

      final gx = (sample['gx'] as num).toDouble();
      final gy = (sample['gy'] as num).toDouble();
      final gz = (sample['gz'] as num).toDouble();

      final accelerationMagnitude = math.sqrt(ax * ax + ay * ay + az * az);

      final angularSpeed = math.sqrt(gx * gx + gy * gy + gz * gz);

      totalAccelerationDeviation += (accelerationMagnitude - 9.81).abs();
      totalAngularSpeed += angularSpeed;
    }

    final count = samples.length;
    final averageAngularSpeed = totalAngularSpeed / count;
    final averageAccelerationDeviation = totalAccelerationDeviation / count;

    final rotationPenalty = (averageAngularSpeed / maxAngularSpeed).clamp(
      0.0,
      1.0,
    );

    final movementPenalty =
        (averageAccelerationDeviation / maxAccelerationDeviation).clamp(
          0.0,
          1.0,
        );

    final stability =
        100 * (1 - (rotationPenalty * 0.6 + movementPenalty * 0.4));

    return stability.round().clamp(0, 100);
  }
}
