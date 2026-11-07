import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/models/video_clip.dart';
import 'package:pitchcut_ai/features/editor/models/trim_range.dart';
import 'package:pitchcut_ai/features/editor/widgets/video_timeline.dart';

void main() {
  const clips = [
    VideoClip(
      path: '/recordings/first.mp4',
      name: 'first.mp4',
      duration: Duration(seconds: 10),
    ),
    VideoClip(
      path: '/recordings/second.mp4',
      name: 'second.mp4',
      duration: Duration(seconds: 10),
    ),
  ];

  testWidgets('playhead follows the editor playback position', (tester) async {
    Duration playbackPosition = Duration.zero;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: VideoTimeline(
              clips: clips,
              selectedClipIndex: 0,
              position: playbackPosition,
              trimRange: const TrimRange(
                start: Duration.zero,
                end: Duration(seconds: 10),
              ),
              onSeek: (_) {},
              onClipSelected: (_) {},
              onTrimChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    final initialX = tester
        .getTopLeft(find.byKey(const ValueKey('timeline-playhead-line')))
        .dx;

    playbackPosition = const Duration(seconds: 5);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: VideoTimeline(
              clips: clips,
              selectedClipIndex: 0,
              position: playbackPosition,
              trimRange: const TrimRange(
                start: Duration.zero,
                end: Duration(seconds: 10),
              ),
              onSeek: (_) {},
              onClipSelected: (_) {},
              onTrimChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final movedX = tester
        .getTopLeft(find.byKey(const ValueKey('timeline-playhead-line')))
        .dx;

    expect(movedX - initialX, closeTo(180, 1));
  });

  testWidgets('dragging the playhead seeks along the timeline', (tester) async {
    Duration? requestedPosition;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: VideoTimeline(
              clips: clips,
              selectedClipIndex: 0,
              position: Duration.zero,
              trimRange: const TrimRange(
                start: Duration.zero,
                end: Duration(seconds: 10),
              ),
              onSeek: (position) => requestedPosition = position,
              onClipSelected: (_) {},
              onTrimChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey('timeline-playhead-handle')),
      const Offset(92, 0),
    );

    expect(requestedPosition, isNotNull);
    expect(requestedPosition!.inMilliseconds, closeTo(2000, 100));
  });

  testWidgets('tapping a clip selects it', (tester) async {
    int? selectedIndex;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: VideoTimeline(
              clips: clips,
              selectedClipIndex: 0,
              position: Duration.zero,
              trimRange: const TrimRange(
                start: Duration.zero,
                end: Duration(seconds: 10),
              ),
              onSeek: (_) {},
              onClipSelected: (index) => selectedIndex = index,
              onTrimChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final secondClip = find.byKey(const ValueKey('timeline-clip-1'));
    await tester.ensureVisible(secondClip);
    await tester.pumpAndSettle();
    await tester.tap(secondClip);

    expect(selectedIndex, 1);
    expect(find.text('00:10'), findsWidgets);
  });
}
