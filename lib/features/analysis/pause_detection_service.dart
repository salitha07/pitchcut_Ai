import '../../models/pause_segment.dart';

/// Detects quiet sections from normalized loudness samples.
class PauseDetectionService {
  const PauseDetectionService({
    this.silenceThreshold = 0.02,
    this.sampleIntervalMs = 100,
  }) : assert(silenceThreshold >= 0 && silenceThreshold <= 1),
       assert(sampleIntervalMs > 0);

  /// Initial threshold; tune using real sample videos.
  final double silenceThreshold;

  /// EditorEngine provides one sample every 100 milliseconds.
  final int sampleIntervalMs;

  /// Detects pauses lasting at least [minPauseMs].
  List<PauseSegment> detectPauses(
    List<double> loudnessSamples, {
    int minPauseMs = 1500,
  }) {
    if (minPauseMs <= 0) {
      throw ArgumentError.value(
        minPauseMs,
        'minPauseMs',
        'Must be greater than zero.',
      );
    }

    final pauses = <PauseSegment>[];
    int? pauseStartIndex;

    for (var i = 0; i < loudnessSamples.length; i++) {
      final value = loudnessSamples[i];
      final isQuiet = value.isFinite && value >= 0 && value <= silenceThreshold;

      if (isQuiet) {
        pauseStartIndex ??= i;
      } else if (pauseStartIndex != null) {
        _addPauseIfLongEnough(pauses, pauseStartIndex, i, minPauseMs);
        pauseStartIndex = null;
      }
    }

    if (pauseStartIndex != null) {
      _addPauseIfLongEnough(
        pauses,
        pauseStartIndex,
        loudnessSamples.length,
        minPauseMs,
      );
    }

    return pauses;
  }

  void _addPauseIfLongEnough(
    List<PauseSegment> pauses,
    int startIndex,
    int endIndex,
    int minPauseMs,
  ) {
    final startMs = startIndex * sampleIntervalMs;
    final endMs = endIndex * sampleIntervalMs;

    if (endMs - startMs >= minPauseMs) {
      pauses.add(PauseSegment(startMs: startMs, endMs: endMs));
    }
  }
}
