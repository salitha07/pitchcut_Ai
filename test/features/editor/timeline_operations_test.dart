import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/models/video_clip.dart';
import 'package:pitchcut_ai/features/editor/models/crop_rect.dart';
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

  group('TimelineOperations.merge', () {
    test('combines adjacent contiguous ranges from the same source', () {
      const left = VideoClip(
        path: '/recordings/joined.mp4',
        name: 'joined (1)',
        duration: Duration(seconds: 3),
        sourceStart: Duration(seconds: 2),
      );
      const right = VideoClip(
        path: '/recordings/joined.mp4',
        name: 'joined (2)',
        duration: Duration(seconds: 4),
        sourceStart: Duration(seconds: 5),
      );
      expect(TimelineOperations.canMerge(left, right), isTrue);
      final result = TimelineOperations.merge([first, left, right, third], 1);
      expect(result, hasLength(3));
      expect(result[1].sourceStart, const Duration(seconds: 2));
      expect(result[1].duration, const Duration(seconds: 7));
      expect(result[1].sourceEnd, const Duration(seconds: 9));
    });

    test('merges different media into one rendered clip preserving order', () {
      expect(TimelineOperations.canMerge(first, second), isTrue);
      expect(
        TimelineOperations.canMergeWithoutRendering(first, second),
        isFalse,
      );
      expect(
        () => TimelineOperations.merge([first, second], 0),
        throwsArgumentError,
      );
      const rendered = VideoClip(
        path: '/editor/merged.mp4',
        name: 'rendered',
        duration: Duration(seconds: 13),
      );
      final result = TimelineOperations.merge(
        [first, second, third],
        0,
        renderedClip: rendered,
      );
      expect(result, hasLength(2));
      expect(result.first.path, rendered.path);
      expect(result.first.name, 'first.mp4 + second.mp4');
      expect(result.first.duration, const Duration(seconds: 13));
      expect(result.last, third);
    });

    test('rejects clips with different rotation or crop edits', () {
      const contiguous = VideoClip(
        path: '/recordings/first.mp4',
        name: 'next segment',
        duration: Duration(seconds: 2),
        sourceStart: Duration(seconds: 8),
      );
      expect(
        TimelineOperations.canMerge(
          first,
          contiguous.copyWith(rotationDegrees: 90),
        ),
        isFalse,
      );
      expect(
        TimelineOperations.canMerge(
          first,
          contiguous.copyWith(
            crop: const CropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
          ),
        ),
        isFalse,
      );
    });
  });

  test('rotation cycles in 90 degree steps and crop clamps coordinates', () {
    var clip = first;
    for (final expected in [90, 180, 270, 0]) {
      clip = TimelineOperations.rotate(clip);
      expect(clip.rotationDegrees, expected);
    }
    const crop = CropRect(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8);
    final moved = crop.move(0.8, -0.5);
    expect(moved.left, closeTo(0.4, 0.000001));
    expect(moved.top, 0);
    expect(moved.right, 1);
    expect(moved.bottom, closeTo(0.6, 0.000001));
    final resized = crop.resize(left: 0.95, bottom: 0.01);
    expect(resized.isValid, isTrue);
    expect(resized.right, lessThanOrEqualTo(1));
    expect(resized.bottom, lessThanOrEqualTo(1));
    expect(TimelineOperations.crop(first, crop).crop, crop);
    expect(
      () => TimelineOperations.crop(
        first,
        const CropRect(left: 0, top: 0, right: 0.02, bottom: 1),
      ),
      throwsArgumentError,
    );
  });
}
