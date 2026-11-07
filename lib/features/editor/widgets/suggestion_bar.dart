import 'package:flutter/material.dart';

import '../models/editor_suggestion.dart';

/// Displays producer-supplied suggestions and delegates their decisions.
///
/// The widget does not generate suggestions or perform editor operations.
class SuggestionBar extends StatelessWidget {
  const SuggestionBar({
    super.key,
    required this.suggestions,
    required this.onAccept,
    required this.onDismiss,
  });

  final List<EditorSuggestion> suggestions;
  final ValueChanged<EditorSuggestion> onAccept;
  final ValueChanged<EditorSuggestion> onDismiss;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return Card(
        key: const ValueKey('suggestion-empty-state'),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline),
              SizedBox(width: 12),
              Expanded(child: Text('No suggestions available')),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      key: const ValueKey('suggestion-bar'),
      height: 148,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final suggestion in suggestions)
            SizedBox(
              width: 300,
              child: Card(
                key: ValueKey('suggestion-${suggestion.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (suggestion.details?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            suggestion.details!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else
                        const Spacer(),
                      if (suggestion.startTime != null ||
                          suggestion.endTime != null)
                        Text(_timeLabel(suggestion)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            key: ValueKey(
                              'dismiss-suggestion-${suggestion.id}',
                            ),
                            onPressed: () => onDismiss(suggestion),
                            child: const Text('Dismiss'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            key: ValueKey('accept-suggestion-${suggestion.id}'),
                            onPressed: () => onAccept(suggestion),
                            child: const Text('Accept'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _timeLabel(EditorSuggestion suggestion) {
    final start = suggestion.startTime;
    final end = suggestion.endTime;
    if (start != null && end != null) {
      return '${_format(start)} – ${_format(end)}';
    }
    return 'At ${_format(start ?? end!)}';
  }

  String _format(Duration duration) =>
      '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
}
