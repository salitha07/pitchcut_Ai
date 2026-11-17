import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/analysis/pause_detection_service.dart';

void main() {
  group('PauseDetectionService', () {
    const service = PauseDetectionService();

    test('detects a pause lasting exactly 1500ms', () {
      final samples = [
        ...List<double>.filled(5, 0.5),
        ...List<double>.filled(15, 0.0),
        ...List<double>.filled(5, 0.5),
      ];

      final pauses = service.detectPauses(samples);

      expect(pauses, hasLength(1));
      expect(pauses.first.startMs, 500);
      expect(pauses.first.endMs, 2000);
    });

    test('ignores pauses shorter than 1500ms', () {
      final samples = [
        ...List<double>.filled(5, 0.5),
        ...List<double>.filled(14, 0.0),
        ...List<double>.filled(5, 0.5),
      ];

      final pauses = service.detectPauses(samples);

      expect(pauses, isEmpty);
    });

    test('detects multiple pauses', () {
      final samples = [
        ...List<double>.filled(5, 0.5),
        ...List<double>.filled(15, 0.0),
        ...List<double>.filled(5, 0.5),
        ...List<double>.filled(20, 0.0),
      ];

      final pauses = service.detectPauses(samples);

      expect(pauses, hasLength(2));
      expect(pauses[0].startMs, 500);
      expect(pauses[0].endMs, 2000);
      expect(pauses[1].startMs, 2500);
      expect(pauses[1].endMs, 4500);
    });

    test('detects a pause continuing to the final sample', () {
      final samples = [
        ...List<double>.filled(5, 0.5),
        ...List<double>.filled(15, 0.0),
      ];

      final pauses = service.detectPauses(samples);

      expect(pauses, hasLength(1));
      expect(pauses.first.startMs, 500);
      expect(pauses.first.endMs, 2000);
    });

    test('treats loudness above threshold as speech', () {
      final samples = List<double>.filled(20, 0.03);

      expect(service.detectPauses(samples), isEmpty);
    });

    test('rejects invalid minimum pause duration', () {
      expect(
        () => service.detectPauses([], minPauseMs: 0),
        throwsArgumentError,
      );
    });
  });
}
