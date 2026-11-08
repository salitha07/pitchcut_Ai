class TrimRange {
  const TrimRange({required this.start, required this.end});

  final Duration start;
  final Duration end;

  Duration get duration => end - start;

  bool isValidFor(
    Duration sourceDuration, {
    Duration minimum = minimumDuration,
  }) =>
      start >= Duration.zero &&
      end <= sourceDuration &&
      start < end &&
      duration >= minimum;

  static const minimumDuration = Duration(milliseconds: 500);

  static TrimRange clampStart(
    Duration requested,
    Duration end,
    Duration sourceDuration, {
    Duration minimum = minimumDuration,
  }) {
    if (sourceDuration < minimum) {
      return TrimRange(start: Duration.zero, end: sourceDuration);
    }
    final safeEnd = end < minimum
        ? minimum
        : end > sourceDuration
        ? sourceDuration
        : end;
    final maxStart = safeEnd - minimum;
    final start = requested < Duration.zero
        ? Duration.zero
        : requested > maxStart
        ? maxStart
        : requested;
    return TrimRange(start: start, end: safeEnd);
  }

  static TrimRange clampEnd(
    Duration start,
    Duration requested,
    Duration sourceDuration, {
    Duration minimum = minimumDuration,
  }) {
    if (sourceDuration < minimum) {
      return TrimRange(start: Duration.zero, end: sourceDuration);
    }
    final safeStart = start < Duration.zero
        ? Duration.zero
        : start > sourceDuration - minimum
        ? sourceDuration - minimum
        : start;
    final minEnd = safeStart + minimum;
    final end = requested < minEnd
        ? minEnd
        : requested > sourceDuration
        ? sourceDuration
        : requested;
    return TrimRange(start: safeStart, end: end);
  }
}
