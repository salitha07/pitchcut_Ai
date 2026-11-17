import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/analysis/speaking_pace_service.dart';
import 'package:pitchcut_ai/models/caption.dart';

void main() {
  group('SpeakingPaceService', () {
    const service = SpeakingPaceService();

    test('calculates 120 WPM correctly', () {
      final captions = [
        Caption(
          id: '1',
          startMs: 0,
          endMs: 60000,
          text: List.filled(120, 'word').join(' '),
        ),
      ];

      expect(service.calculateWpm(captions), 120);
    });

    test('returns 100 score for normal speaking pace', () {
      final captions = [
        Caption(
          id: '1',
          startMs: 0,
          endMs: 60000,
          text: List.filled(120, 'word').join(' '),
        ),
      ];

      expect(service.calculateScore(captions), 100);
    });

    test('returns lower score for slow speaking pace', () {
      final captions = [
        Caption(
          id: '1',
          startMs: 0,
          endMs: 60000,
          text: List.filled(60, 'word').join(' '),
        ),
      ];

      expect(service.calculateScore(captions), 60);
    });

    test('returns lower score for fast speaking pace', () {
      final captions = [
        Caption(
          id: '1',
          startMs: 0,
          endMs: 60000,
          text: List.filled(200, 'word').join(' '),
        ),
      ];

      expect(service.calculateScore(captions), 80);
    });

    test('returns null when captions are empty', () {
      expect(service.calculateWpm([]), isNull);
      expect(service.calculateScore([]), isNull);
    });

    test('ignores invalid caption timestamps', () {
      final captions = [
        const Caption(
          id: '1',
          startMs: 1000,
          endMs: 500,
          text: 'Invalid caption',
        ),
      ];

      expect(service.calculateWpm(captions), isNull);
    });
  });
}
