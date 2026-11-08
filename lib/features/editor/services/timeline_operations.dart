import '../models/video_clip.dart';
import '../models/trim_range.dart';
import '../models/crop_rect.dart';

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
      timelineItemId: _splitTimelineId(clip, clip.sourceStart, clipPosition),
    );
    final second = clip.copyWith(
      name: '${clip.name} (2)',
      duration: clip.duration - clipPosition,
      sourceStart: clip.sourceStart + clipPosition,
      timelineItemId: _splitTimelineId(
        clip,
        clip.sourceStart + clipPosition,
        clip.duration - clipPosition,
      ),
    );
    return [...clips.take(index), first, second, ...clips.skip(index + 1)];
  }

  static String? _splitTimelineId(
    VideoClip clip,
    Duration sourceStart,
    Duration duration,
  ) {
    final sourceId = clip.sourceClipId;
    if (sourceId == null) return null;
    final segmentId = clip.timelineItemId ?? 'source:$sourceId';
    return '$segmentId@${sourceStart.inMilliseconds}+'
        '${duration.inMilliseconds}';
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

  static bool canMerge(VideoClip first, VideoClip second) =>
      first.rotationDegrees == second.rotationDegrees &&
      first.crop == second.crop;

  static bool canMergeWithoutRendering(VideoClip first, VideoClip second) =>
      canMerge(first, second) &&
      first.path == second.path &&
      first.sourceEnd == second.sourceStart;

  static List<VideoClip> merge(
    List<VideoClip> clips,
    int firstIndex, {
    VideoClip? renderedClip,
  }) {
    if (firstIndex < 0 || firstIndex + 1 >= clips.length) {
      throw RangeError.index(firstIndex, clips, 'firstIndex');
    }
    final first = clips[firstIndex];
    final second = clips[firstIndex + 1];
    if (!canMerge(first, second)) {
      throw ArgumentError('Only clips with matching edits can merge.');
    }
    final merged = canMergeWithoutRendering(first, second)
        ? first.copyWith(
            name: '${first.name} + ${second.name}',
            duration: first.duration + second.duration,
            sourceDuration: first.duration + second.duration,
          )
        : renderedClip?.copyWith(name: '${first.name} + ${second.name}') ??
              (throw ArgumentError(
                'A rendered clip is required to merge separate source ranges.',
              ));
    return [...clips.take(firstIndex), merged, ...clips.skip(firstIndex + 2)];
  }

  static VideoClip rotate(VideoClip clip) =>
      clip.copyWith(rotationDegrees: (clip.rotationDegrees + 90) % 360);

  static VideoClip crop(VideoClip clip, CropRect crop) {
    if (!crop.isValid) throw ArgumentError('Crop rectangle is invalid.');
    return clip.copyWith(crop: crop);
  }
}
