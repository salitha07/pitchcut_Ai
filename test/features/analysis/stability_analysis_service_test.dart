import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/analysis/stability_analysis_service.dart';

void main() {
  group('StabilityAnalysisService', () {
    const service = StabilityAnalysisService();

    Map<String, dynamic> sample({
      int tMs = 0,
      double ax = 0,
      double ay = 0,
      double az = 9.81,
      double gx = 0,
      double gy = 0,
      double gz = 0,
    }) {
      return {
        'tMs': tMs,
        'ax': ax,
        'ay': ay,
        'az': az,
        'gx': gx,
        'gy': gy,
        'gz': gz,
      };
    }

    test('returns 100 for perfectly stable sensor samples', () {
      final samples = [sample(tMs: 0), sample(tMs: 100), sample(tMs: 200)];

      expect(service.calculateScore(samples), 100);
    });

    test('returns a lower score when camera rotation increases', () {
      final stableSamples = [sample(tMs: 0), sample(tMs: 100)];

      final movingSamples = [
        sample(tMs: 0, gx: 0.5),
        sample(tMs: 100, gx: 0.5),
      ];

      final stableScore = service.calculateScore(stableSamples);
      final movingScore = service.calculateScore(movingSamples);

      expect(movingScore, lessThan(stableScore!));
    });

    test('returns a lower score when acceleration changes', () {
      final stableSamples = [sample(tMs: 0), sample(tMs: 100)];

      final movingSamples = [sample(tMs: 0, ax: 3), sample(tMs: 100, ax: 3)];

      final stableScore = service.calculateScore(stableSamples);
      final movingScore = service.calculateScore(movingSamples);

      expect(movingScore, lessThan(stableScore!));
    });

    test('returns null for empty sensor data', () {
      expect(service.calculateScore([]), isNull);
    });

    test('returns null for invalid sensor values', () {
      final samples = [sample(tMs: 0, gx: double.nan)];

      expect(service.calculateScore(samples), isNull);
    });

    test('returns null for duplicate timestamps', () {
      final samples = [sample(tMs: 100), sample(tMs: 100)];

      expect(service.calculateScore(samples), isNull);
    });
  });
}
