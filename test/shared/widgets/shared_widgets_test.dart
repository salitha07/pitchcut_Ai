import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/shared/widgets/widgets.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('ErrorView shows message and calls onRetry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      wrap(
        ErrorView(
          message: 'Something went wrong',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Something went wrong'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('EmptyState shows title and message', (tester) async {
    await tester.pumpWidget(
      wrap(
        const EmptyState(
          title: 'No projects yet',
          message: 'Record your first video',
        ),
      ),
    );

    expect(find.text('No projects yet'), findsOneWidget);
    expect(find.text('Record your first video'), findsOneWidget);
  });

  testWidgets('AppButton calls onPressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      wrap(AppButton(label: 'Save', onPressed: () => pressed = true)),
    );

    await tester.tap(find.text('Save'));
    expect(pressed, isTrue);
  });
}
