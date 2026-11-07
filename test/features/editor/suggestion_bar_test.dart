import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitchcut_ai/features/editor/models/editor_suggestion.dart';
import 'package:pitchcut_ai/features/editor/widgets/suggestion_bar.dart';

void main() {
  testWidgets('shows an empty state when there are no suggestions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SuggestionBar(
            suggestions: const [],
            onAccept: (_) {},
            onDismiss: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('No suggestions available'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('suggestion-empty-state')),
      findsOneWidget,
    );
  });

  testWidgets('renders details and timestamps and delegates both decisions', (
    tester,
  ) async {
    const suggestion = EditorSuggestion(
      id: 'pause-1',
      title: 'Cut this pause?',
      details: 'There is a long pause after this sentence.',
      startTime: Duration(seconds: 12),
      endTime: Duration(seconds: 16),
      action: SplitSuggestionAction(Duration(seconds: 12)),
    );
    final accepted = <EditorSuggestion>[];
    final dismissed = <EditorSuggestion>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SuggestionBar(
            suggestions: const [suggestion],
            onAccept: accepted.add,
            onDismiss: dismissed.add,
          ),
        ),
      ),
    );

    expect(find.text('Cut this pause?'), findsOneWidget);
    expect(find.text(suggestion.details!), findsOneWidget);
    expect(find.text('0:12 – 0:16'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('accept-suggestion-pause-1')));
    await tester.tap(find.byKey(const ValueKey('dismiss-suggestion-pause-1')));
    expect(accepted, [suggestion]);
    expect(dismissed, [suggestion]);
  });
}
