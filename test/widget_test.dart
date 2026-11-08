import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/debug/engine_debug_screen.dart';

void main() {
  testWidgets('debug screen displays engine controls when pumped directly', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: EngineDebugScreen()));

    expect(find.text('Editor Engine Debug'), findsOneWidget);
    expect(find.text('TEMPORARY, M4 engine debug'), findsOneWidget);
    expect(find.text('Burn Captions'), findsOneWidget);
    expect(find.text('Hello PitchCut'), findsOneWidget);
    expect(find.text('Start (ms)'), findsOneWidget);
    expect(find.text('End (ms)'), findsOneWidget);
    expect(find.text('Pick video clip'), findsOneWidget);
  });

  testWidgets('caption timing is validated before export', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EngineDebugScreen()));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('caption-start-ms')),
      '-1',
    );

    await tester.ensureVisible(find.byKey(const ValueKey('export-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('export-button')));
    await tester.pumpAndSettle();

    expect(find.text('Start time must be 0 or greater.'), findsOneWidget);
    expect(find.text('Pick a video clip before exporting.'), findsNothing);
  });
}
