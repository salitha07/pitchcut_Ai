import 'trim_range.dart';
import 'video_clip.dart';

/// Immutable editor state stored for one undo or redo step.
class EditorStateSnapshot {
  EditorStateSnapshot({
    required List<VideoClip> clips,
    required this.selectedClipIndex,
    required this.trimRange,
    required this.timelinePosition,
  }) : clips = List.unmodifiable(clips);

  final List<VideoClip> clips;
  final int selectedClipIndex;
  final TrimRange trimRange;
  final Duration timelinePosition;
}
