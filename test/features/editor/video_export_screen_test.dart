import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/models/video_clip.dart';
import 'package:pitchcut_ai/features/editor/video_editor_screen.dart';
import 'package:pitchcut_ai/features/editor/video_export_screen.dart';

void main() {
  const clip = VideoClip(
    path: '/recordings/scene.mp4',
    name: 'scene.mp4',
    duration: Duration(seconds: 45),
  );

  test('video editor widget remains available for navigation to Export', () {
    const editor = VideoEditorScreen(videoPath: '/recordings/scene.mp4');
    expect(editor.videoPath, '/recordings/scene.mp4');
  });

  testWidgets('shows timeline details and updates estimated quality settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VideoExportScreen(
          clips: [clip],
          duration: Duration(seconds: 45),
          sourceAspectRatio: 16 / 9,
        ),
      ),
    );

    expect(find.text('scene.mp4'), findsOneWidget);
    expect(find.text('0:45'), findsOneWidget);
    expect(find.text('MP4'), findsOneWidget);
    expect(find.text('1280 × 720 (720p)'), findsOneWidget);

    await tester.tap(find.text('1080p'));
    await tester.pump();
    expect(find.text('1920 × 1080 (1080p)'), findsOneWidget);
  });
}
