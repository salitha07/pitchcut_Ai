import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchcut_ai/features/captions/ui/caption_overlay.dart';
import 'package:pitchcut_ai/models/caption.dart';

void main() {
  const captions = [
    Caption(id: '1', startMs: 1000, endMs: 3000, text: 'Hello'),
    Caption(id: '2', startMs: 3000, endMs: 5000, text: 'World'),
  ];

  Future<void> pump(WidgetTester tester, int positionMs) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaptionOverlay(captions: captions, positionMs: positionMs),
        ),
      ),
    );
  }

  testWidgets('shows the caption active at the position', (tester) async {
    await pump(tester, 2000);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('World'), findsNothing);
  });

  testWidgets('switches to the next caption at its start time', (tester) async {
    await pump(tester, 3000);
    expect(find.text('Hello'), findsNothing);
    expect(find.text('World'), findsOneWidget);
  });

  testWidgets('shows nothing when no caption is active', (tester) async {
    await pump(tester, 500);
    expect(find.text('Hello'), findsNothing);
    expect(find.text('World'), findsNothing);
  });
}