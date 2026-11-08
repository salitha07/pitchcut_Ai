import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/models/trim_range.dart';
import 'package:pitchcut_ai/features/editor/services/editor_command_history.dart';

void main() {
  const sourceDuration = Duration(seconds: 12);

  group('TrimRange', () {
    test('calculates the selected duration from in and out points', () {
      const range = TrimRange(
        start: Duration(seconds: 2),
        end: Duration(seconds: 9),
      );

      expect(range.duration, const Duration(seconds: 7));
      expect(range.isValidFor(sourceDuration), isTrue);
    });

    test('clamps the start to preserve the minimum duration', () {
      final negative = TrimRange.clampStart(
        const Duration(milliseconds: -200),
        const Duration(seconds: 4),
        sourceDuration,
      );
      final pastEnd = TrimRange.clampStart(
        const Duration(seconds: 8),
        const Duration(seconds: 4),
        sourceDuration,
      );

      expect(negative.start, Duration.zero);
      expect(pastEnd.start, const Duration(milliseconds: 3500));
      expect(pastEnd.duration, TrimRange.minimumDuration);
    });

    test(
      'clamps the end to source duration and preserves minimum duration',
      () {
        final tooEarly = TrimRange.clampEnd(
          const Duration(seconds: 3),
          const Duration(seconds: 2),
          sourceDuration,
        );
        final tooLate = TrimRange.clampEnd(
          const Duration(seconds: 3),
          const Duration(seconds: 20),
          sourceDuration,
        );

        expect(tooEarly.end, const Duration(milliseconds: 3500));
        expect(tooEarly.duration, TrimRange.minimumDuration);
        expect(tooLate.end, sourceDuration);
      },
    );

    test('rejects zero length and out of source ranges', () {
      expect(
        const TrimRange(
          start: Duration(seconds: 4),
          end: Duration(seconds: 4),
        ).isValidFor(sourceDuration),
        isFalse,
      );
      expect(
        const TrimRange(
          start: Duration(seconds: 11),
          end: Duration(seconds: 13),
        ).isValidFor(sourceDuration),
        isFalse,
      );
    });
  });

  test('trim commands restore source state through undo and redo', () {
    final history = EditorCommandHistory<String>();
    history.record(before: 'original.mp4', after: 'trimmed.mp4');

    expect(history.canUndo, isTrue);
    expect(history.undo(), 'original.mp4');
    expect(history.canRedo, isTrue);
    expect(history.redo(), 'trimmed.mp4');
  });
}
