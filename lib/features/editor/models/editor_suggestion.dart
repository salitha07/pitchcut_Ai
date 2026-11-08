import 'package:flutter/foundation.dart';

import 'trim_range.dart';

/// A typed editing action that can be attached to a suggestion.
///
/// Actions are data only. The editor validates them against its current
/// timeline before executing them.
sealed class EditorSuggestionAction {
  const EditorSuggestionAction();
}

class SeekSuggestionAction extends EditorSuggestionAction {
  const SeekSuggestionAction(this.position);
  final Duration position;
}

class SplitSuggestionAction extends EditorSuggestionAction {
  const SplitSuggestionAction(this.position);
  final Duration position;
}

class TrimSuggestionAction extends EditorSuggestionAction {
  const TrimSuggestionAction({required this.clipIndex, required this.range});
  final int clipIndex;
  final TrimRange range;
}

@immutable
class EditorSuggestion {
  const EditorSuggestion({
    required this.id,
    required this.title,
    this.details,
    this.startTime,
    this.endTime,
    this.action,
  });

  /// Stable identifier supplied by the producer, used when dismissing items.
  final String id;
  final String title;
  final String? details;
  final Duration? startTime;
  final Duration? endTime;
  final EditorSuggestionAction? action;
}
