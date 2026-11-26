import 'package:flutter/foundation.dart';

import 'trim_range.dart';

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

class RemovePauseSuggestionAction extends EditorSuggestionAction {
  const RemovePauseSuggestionAction({
    required this.clipId,
    required this.startMs,
    required this.endMs,
  });

  final String clipId;
  final int startMs;
  final int endMs;

  bool get isValid => clipId.isNotEmpty && startMs >= 0 && endMs > startMs;
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

  final String id;
  final String title;
  final String? details;
  final Duration? startTime;
  final Duration? endTime;
  final EditorSuggestionAction? action;
}
