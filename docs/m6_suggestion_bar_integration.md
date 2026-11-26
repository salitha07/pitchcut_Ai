# M6 integration: editor suggestions

M6 can pass suggestions into `VideoEditorScreen` without adding suggestion
generation to the editor. Keep suggestion generation in M6 and provide a stable
`id` for each item so the editor can hide it after acceptance or dismissal.

```dart
VideoEditorScreen(
  videoPath: projectVideoPath,
  suggestions: suggestionsFromM6,
  onSuggestionAccepted: (suggestion) {
    // Record acceptance or update M6 state.
  },
  onSuggestionDismissed: (suggestion) {
    // Record dismissal or request the next M6 suggestion.
  },
)
```

Each item is an `EditorSuggestion` from
`features/editor/models/editor_suggestion.dart`. Supply a title, optional
details, optional `startTime` / `endTime` timeline markers, and optionally a
typed action:

- `SeekSuggestionAction(position)` seeks to a timeline position.
- `SplitSuggestionAction(position)` seeks and splits if the current timeline
  permits a split there.
- `TrimSuggestionAction(clipIndex: ..., range: ...)` selects that clip and
  applies the valid source-relative trim range.

The editor checks action positions and ranges against its current timeline
before executing them. An item without an action still invokes the accepted
callback. Acceptance removes the suggestion from the current editor view;
dismissal removes it and invokes the dismissal callback. The M6 owner remains
responsible for persisting or regenerating suggestion data across editor
restarts.
