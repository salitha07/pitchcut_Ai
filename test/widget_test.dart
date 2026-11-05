import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/debug/engine_debug_screen.dart';
import 'package:pitchcut_ai/main.dart';

void main() {
  testWidgets('the original home screen remains the initial route', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Flutter Demo Home Page'), findsOneWidget);
    expect(
      find.text('You have pushed the button this many times:'),
      findsOneWidget,
    );
    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.byTooltip('Increment'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });

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
    await tester.ensureVisible(find.byKey(const ValueKey('export-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('export-button')), findsOneWidget);
    expect(EngineDebugScreen.routeName, '/engine-debug');
    await tester.drag(find.byType(ListView).first, const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(find.text('Copy log'), findsOneWidget);
  });

  testWidgets('debug route is registered in debug mode', (tester) async {
    await tester.pumpWidget(const MyApp());
    final context = tester.element(find.byType(MyHomePage));

    Navigator.of(context).pushNamed(EngineDebugScreen.routeName);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('TEMPORARY, M4 engine debug'), findsOneWidget);
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
