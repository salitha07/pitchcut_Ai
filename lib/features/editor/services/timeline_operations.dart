import '../models/video_clip.dart';
import '../models/trim_range.dart';

class TimelineOperations {
  static const minimumSegmentDuration = TrimRange.minimumDuration;

  static bool canSplit(VideoClip clip, Duration clipPosition) =>
      clipPosition >= minimumSegmentDuration &&
      clip.duration - clipPosition >= minimumSegmentDuration;

  static List<VideoClip> split(
    List<VideoClip> clips,
    int index,
    Duration clipPosition,
  ) {
    if (index < 0 || index >= clips.length) {
      throw RangeError.index(index, clips, 'index');
    }
    final clip = clips[index];
    if (!canSplit(clip, clipPosition)) {
      throw ArgumentError(
        'Split point must leave at least 0.5 seconds per segment.',
      );
    }
    final first = clip.copyWith(
      name: '${clip.name} (1)',
      duration: clipPosition,
    );
    final second = clip.copyWith(
      name: '${clip.name} (2)',
      duration: clip.duration - clipPosition,
      sourceStart: clip.sourceStart + clipPosition,
    );
    return [...clips.take(index), first, second, ...clips.skip(index + 1)];
  }

  static List<VideoClip> delete(List<VideoClip> clips, int index) {
    if (index < 0 || index >= clips.length) {
      throw RangeError.index(index, clips, 'index');
    }
    return [...clips]..removeAt(index);
  }

  static List<VideoClip> reorder(List<VideoClip> clips, int from, int to) {
    if (from < 0 || from >= clips.length) {
      throw RangeError.index(from, clips, 'from');
    }
    if (to < 0 || to >= clips.length) {
      throw RangeError.index(to, clips, 'to');
    }
    if (from == to) return List.of(clips);
    final result = List<VideoClip>.of(clips);
    final clip = result.removeAt(from);
    result.insert(to, clip);
    return result;
  }
}
