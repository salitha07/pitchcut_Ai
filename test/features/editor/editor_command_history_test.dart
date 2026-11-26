import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/models/crop_rect.dart';
import 'package:pitchcut_ai/features/editor/models/editor_state_snapshot.dart';
import 'package:pitchcut_ai/features/editor/models/trim_range.dart';
import 'package:pitchcut_ai/features/editor/models/video_clip.dart';
import 'package:pitchcut_ai/features/editor/services/editor_command_history.dart';
import 'package:pitchcut_ai/features/editor/services/timeline_operations.dart';

EditorStateSnapshot snapshot(
  List<VideoClip> clips, {
  int selected = 0,
  required int trimStartMs,
  required int trimEndMs,
  required int playheadMs,
}) => EditorStateSnapshot(
  clips: clips,
  selectedClipIndex: selected,
  trimRange: TrimRange(
    start: Duration(milliseconds: trimStartMs),
    end: Duration(milliseconds: trimEndMs),
  ),
  timelinePosition: Duration(milliseconds: playheadMs),
);

void expectSameState(EditorStateSnapshot actual, EditorStateSnapshot expected) {
  expect(actual.clips, expected.clips);
  expect(actual.selectedClipIndex, expected.selectedClipIndex);
  expect(actual.trimRange.start, expected.trimRange.start);
  expect(actual.trimRange.end, expected.trimRange.end);
  expect(actual.timelinePosition, expected.timelinePosition);
}

void main() {
  test('undoes and redoes a multi-step sequence with full editor state', () {
    const original = VideoClip(
      path: '/video/a.mp4',
      name: 'a.mp4',
      duration: Duration(seconds: 10),
    );
    const second = VideoClip(
      path: '/video/b.mp4',
      name: 'b.mp4',
      duration: Duration(seconds: 5),
    );
    const third = VideoClip(
      path: '/video/c.mp4',
      name: 'c.mp4',
      duration: Duration(seconds: 3),
    );
    final initialClips = [original, second, third];
    final trimmedClip = original.copyWith(
      sourceStart: const Duration(seconds: 1),
      duration: const Duration(seconds: 8),
      sourceDuration: const Duration(seconds: 8),
    );
    final trimmedClips = [trimmedClip, second, third];
    final splitClips = TimelineOperations.split(
      trimmedClips,
      0,
      const Duration(seconds: 4),
    );
    final mergeRendered = const VideoClip(
      path: '/editor/merged.mp4',
      name: 'b + c',
      duration: Duration(seconds: 8),
    );
    final mergedClips = TimelineOperations.merge(
      splitClips,
      2,
      renderedClip: mergeRendered,
    );
    final reorderedClips = TimelineOperations.reorder(mergedClips, 2, 0);
    final rotatedClips = List<VideoClip>.of(reorderedClips)
      ..[0] = TimelineOperations.rotate(reorderedClips[0]);
    const crop = CropRect(left: 0.1, top: 0.15, right: 0.9, bottom: 0.85);
    final croppedClips = List<VideoClip>.of(rotatedClips)
      ..[0] = TimelineOperations.crop(rotatedClips[0], crop);
    final deletedClips = TimelineOperations.delete(croppedClips, 0);

    final states = [
      snapshot(
        initialClips,
        trimStartMs: 0,
        trimEndMs: 10000,
        playheadMs: 2000,
      ),
      snapshot(trimmedClips, trimStartMs: 0, trimEndMs: 8000, playheadMs: 1000),
      snapshot(
        splitClips,
        selected: 1,
        trimStartMs: 0,
        trimEndMs: 4000,
        playheadMs: 4000,
      ),
      snapshot(
        mergedClips,
        selected: 2,
        trimStartMs: 0,
        trimEndMs: 8000,
        playheadMs: 12000,
      ),
      snapshot(reorderedClips, trimStartMs: 0, trimEndMs: 8000, playheadMs: 0),
      snapshot(rotatedClips, trimStartMs: 0, trimEndMs: 8000, playheadMs: 1000),
      snapshot(croppedClips, trimStartMs: 0, trimEndMs: 8000, playheadMs: 2000),
      snapshot(deletedClips, trimStartMs: 0, trimEndMs: 4000, playheadMs: 0),
    ];
    final history = EditorCommandHistory<EditorStateSnapshot>();
    for (var index = 0; index < states.length - 1; index++) {
      history.record(before: states[index], after: states[index + 1]);
    }

    expect(history.canUndo, isTrue);
    for (var index = states.length - 2; index >= 0; index--) {
      final restored = history.undo();
      expect(restored, isNotNull);
      expectSameState(restored!, states[index]);
    }
    expect(history.canUndo, isFalse);
    expect(history.canRedo, isTrue);

    for (var index = 1; index < states.length; index++) {
      final restored = history.redo();
      expect(restored, isNotNull);
      expectSameState(restored!, states[index]);
    }
    expect(history.canRedo, isFalse);
  });

  test('a new edit after undo clears redo history', () {
    final history = EditorCommandHistory<int>();
    history.record(before: 0, after: 1);
    history.record(before: 1, after: 2);
    expect(history.undo(), 1);
    expect(history.canRedo, isTrue);

    history.record(before: 1, after: 3);
    expect(history.canRedo, isFalse);
    expect(history.undo(), 1);
    expect(history.redo(), 3);
  });
}
