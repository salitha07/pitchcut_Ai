import '../../models/caption.dart';

/// Calculates speaking pace using caption timestamps and text.
class SpeakingPaceService {
  const SpeakingPaceService();

  /// Returns words per minute, or null when captions are unavailable.
  double? calculateWpm(List<Caption> captions) {
    if (captions.isEmpty) return null;

    var totalWords = 0;
    int? earliestStart;
    int? latestEnd;

    for (final caption in captions) {
      if (caption.startMs < 0 || caption.endMs <= caption.startMs) {
        continue;
      }

      final words = caption.text
          .trim()
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .length;

      if (words == 0) continue;

      totalWords += words;

      earliestStart = earliestStart == null
          ? caption.startMs
          : (caption.startMs < earliestStart ? caption.startMs : earliestStart);

      latestEnd = latestEnd == null
          ? caption.endMs
          : (caption.endMs > latestEnd ? caption.endMs : latestEnd);
    }

    if (totalWords == 0 || earliestStart == null || latestEnd == null) {
      return null;
    }

    final durationMs = latestEnd - earliestStart;

    if (durationMs <= 0) return null;

    return totalWords / (durationMs / 60000);
  }

  /// Returns a pace score between 0 and 100.
  ///
  /// 100–160 WPM is treated as the target speaking range.
  int? calculateScore(List<Caption> captions) {
    final wpm = calculateWpm(captions);

    if (wpm == null) return null;

    if (wpm >= 100 && wpm <= 160) return 100;

    if (wpm < 100) {
      return (wpm / 100 * 100).round().clamp(0, 100);
    }

    return (160 / wpm * 100).round().clamp(0, 100);
  }
}
