import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/models/video_clip.dart';
import 'package:pitchcut_ai/features/editor/services/timeline_operations.dart';

void main() {
  const first = VideoClip(
    path: '/recordings/first.mp4',
    name: 'first.mp4',
    duration: Duration(seconds: 8),
  );
  const second = VideoClip(
    path: '/recordings/second.mp4',
    name: 'second.mp4',
    duration: Duration(seconds: 5),
  );
  const third = VideoClip(
    path: '/recordings/third.mp4',
    name: 'third.mp4',
    duration: Duration(seconds: 3),
  );

  group('TimelineOperations.split', () {
    test('creates adjacent source ranges with matching timeline duration', () {
      final result = TimelineOperations.split(
        [first, second],
        0,
        const Duration(seconds: 3),
      );

      expect(result, hasLength(3));
      expect(result[0].path, first.path);
      expect(result[0].sourceStart, Duration.zero);
      expect(result[0].duration, const Duration(seconds: 3));
      expect(result[1].path, first.path);
      expect(result[1].sourceStart, const Duration(seconds: 3));
      expect(result[1].duration, const Duration(seconds: 5));
      expect(
        result.map((clip) => clip.duration).reduce((a, b) => a + b),
        const Duration(seconds: 13),
      );
      expect(result.last.path, second.path);
    });

    test('rejects splits that would create a zero or too-short segment', () {
      expect(TimelineOperations.canSplit(first, Duration.zero), isFalse);
      expect(
        TimelineOperations.canSplit(first, const Duration(milliseconds: 499)),
        isFalse,
      );
      expect(
        () => TimelineOperations.split(
          [first],
          0,
          const Duration(milliseconds: 499),
        ),
        throwsArgumentError,
      );
    });
  });

  group('TimelineOperations.delete', () {
    test('removes the requested clip and can safely remove the last one', () {
      expect(TimelineOperations.delete([first, second, third], 1), [
        first,
        third,
      ]);
      expect(TimelineOperations.delete([first], 0), isEmpty);
    });
  });

  test('reorders clips without changing source ranges or durations', () {
    final result = TimelineOperations.reorder([first, second, third], 0, 2);

    expect(result, [second, third, first]);
    expect(result.last.path, first.path);
    expect(result.last.duration, first.duration);
    expect(result.last.sourceStart, first.sourceStart);
  });
}
