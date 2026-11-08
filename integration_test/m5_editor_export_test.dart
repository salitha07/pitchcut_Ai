import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pitchcut_ai/features/editor/services/editor_project_store.dart';
import 'package:pitchcut_ai/features/editor/video_editor_screen.dart';
import 'package:video_player/video_player.dart';

const _videoPath = String.fromEnvironment('M5_VIDEO_PATH');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'opens a real video, controls playback, exports, saves, and plays output',
    (tester) async {
      expect(
        _videoPath,
        isNotEmpty,
        reason:
            'Run with --dart-define=M5_VIDEO_PATH=<device-local-video-path>.',
      );
      expect(await File(_videoPath).exists(), isTrue);

      await tester.pumpWidget(
        MaterialApp(home: VideoEditorScreen(videoPath: _videoPath)),
      );
      for (
        var attempt = 0;
        attempt < 60 &&
            find.byKey(const ValueKey('video-play-pause')).evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      expect(find.byKey(const ValueKey('video-play-pause')), findsOneWidget);
      expect(find.byKey(const ValueKey('video-seek-bar')), findsOneWidget);
      expect(
        find.byType(Image),
        findsWidgets,
        reason: 'Timeline thumbnail is shown.',
      );

      await tester.tap(find.byKey(const ValueKey('video-play-pause')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('video-play-pause')))
            .tooltip,
        'Pause',
      );
      await tester.tap(find.byKey(const ValueKey('video-play-pause')));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('video-play-pause')))
            .tooltip,
        'Play',
      );

      final seekBar = find.byKey(const ValueKey('video-seek-bar'));
      await tester.tapAt(tester.getCenter(seekBar));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Slider>(seekBar).value, greaterThan(0));

      await tester.tap(find.byKey(const ValueKey('open-video-export-screen')));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('Export video'), findsOneWidget);
      await tester.tap(find.text('480p'));
      await tester.pump();
      expect(find.textContaining('(480p)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('start-video-export')));
      for (
        var attempt = 0;
        attempt < 120 &&
            find.text('Video exported successfully').evaluate().isEmpty &&
            find.byKey(const ValueKey('video-export-error')).evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byKey(const ValueKey('video-export-error')), findsNothing);
      expect(find.text('Video exported successfully'), findsOneWidget);
      expect(find.text('Saved to this project'), findsOneWidget);

      final project = await EditorProjectStore().load(_videoPath);
      expect(project, isNotNull);
      expect(project!.exports, isNotEmpty);
      final saved = project.exports.last;
      final savedFile = File(saved.filePath);
      expect(await savedFile.exists(), isTrue);
      expect(await savedFile.length(), greaterThan(0));
      expect(saved.projectId, _videoPath);
      expect(saved.quality.label, '480p');

      await tester.tap(find.text('Play saved video'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('Saved edited video'), findsOneWidget);
      expect(find.byType(VideoPlayer), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
