import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/models/crop_rect.dart';
import 'package:pitchcut_ai/features/editor/widgets/crop_frame_editor.dart';

void main() {
  testWidgets('dragging inside moves the frame without leaving video bounds', (
    tester,
  ) async {
    var crop = const CropRect(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: CropFrameEditor(
                crop: crop,
                onChanged: (value) => crop = value,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(CropFrameEditor), const Offset(50, -60));
    expect(crop.left, closeTo(0.4, 0.000001));
    expect(crop.top, 0);
    expect(crop.right, 1);
    expect(crop.bottom, closeTo(0.6, 0.000001));
    expect(crop.isValid, isTrue);
  });

  testWidgets('dragging a crop edge resizes the frame', (tester) async {
    var crop = const CropRect(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: CropFrameEditor(
                crop: crop,
                onChanged: (value) => crop = value,
              ),
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(CropFrameEditor));
    final gesture = await tester.startGesture(topLeft + const Offset(40, 100));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pump();
    expect(crop.left, greaterThan(0.2));
    expect(crop.isValid, isTrue);
  });
}
