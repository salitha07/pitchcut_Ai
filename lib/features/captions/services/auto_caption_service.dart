import 'dart:io';

import 'package:whisper_wrapper/whisper_wrapper.dart';

import '../../../models/caption.dart';
import '../../../models/clip.dart';
import '../../editor/models/video_clip.dart';

class AutoCaptionService {
  final WhisperController _whisper = WhisperController();

  static const WhisperModel _model = WhisperModel.tiny;

  Future<List<Caption>> generateCaptions({
    required List<Clip> sourceClips,
    required List<VideoClip> timelineClips,
    void Function(String message)? onStatus,
    void Function(int progress)? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Automatic captions are currently supported on Android only.',
      );
    }

    if (timelineClips.isEmpty) {
      throw StateError('The video timeline is empty.');
    }

    final usedSources = <String, Clip>{};

    for (final timelineClip in timelineClips) {
      Clip? source;

      for (final candidate in sourceClips) {
        if (timelineClip.sourceClipId != null &&
            candidate.id == timelineClip.sourceClipId) {
          source = candidate;
          break;
        }
      }

      source ??= sourceClips.cast<Clip?>().firstWhere(
        (candidate) => candidate?.localPath == timelineClip.path,
        orElse: () => null,
      );

      if (source == null) {
        throw StateError(
          'Could not find the original video for ${timelineClip.name}.',
        );
      }

      usedSources[source.id] = source;
    }

    onStatus?.call('Preparing speech recognition model...');
    onProgress?.call(0);

    await _whisper.downloadModel(_model);

    final segmentsBySource = <String, List<dynamic>>{};
    final sources = usedSources.values.toList();

    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];

      onStatus?.call('Transcribing video ${i + 1} of ${sources.length}...');

      final wavFile = File('${source.localPath}.wav');
      final wavExistedBefore = await wavFile.exists();

      try {
        final result = await _whisper.transcribe(
          model: _model,
          audioPath: source.localPath,
          lang: 'auto',
          withSegments: true,
          splitOnWord: false,
          onProgress: (percent) {
            final overall = (((i + percent / 100) / sources.length) * 100)
                .round();

            onProgress?.call(overall.clamp(0, 100));
          },
        );

        if (result == null) {
          throw StateError(
            'Speech recognition failed for ${source.localPath}.',
          );
        }

        final segments = result.transcription.segments;

        if (segments == null || segments.isEmpty) {
          throw StateError(
            'No timestamped speech was detected in ${source.localPath}. '
            'The video may contain no audio.',
          );
        }

        segmentsBySource[source.id] = segments;
      } finally {
        if (!wavExistedBefore && await wavFile.exists()) {
          await wavFile.delete();
        }
      }
    }

    final captions = <Caption>[];
    var timelineOffsetMs = 0;

    for (final timelineClip in timelineClips) {
      Clip? source;

      for (final candidate in sources) {
        if (candidate.id == timelineClip.sourceClipId ||
            candidate.localPath == timelineClip.path) {
          source = candidate;
          break;
        }
      }

      if (source == null) {
        throw StateError('Timeline source mapping was lost.');
      }

      final segments = segmentsBySource[source.id] ?? [];

      final sourceStartMs = timelineClip.sourceStart.inMilliseconds;
      final sourceEndMs = sourceStartMs + timelineClip.duration.inMilliseconds;

      for (final segment in segments) {
        final segmentStartMs = segment.fromTs.inMilliseconds;
        final segmentEndMs = segment.toTs.inMilliseconds;

        if (segmentEndMs <= sourceStartMs || segmentStartMs >= sourceEndMs) {
          continue;
        }

        final clippedStartMs = segmentStartMs < sourceStartMs
            ? sourceStartMs
            : segmentStartMs;

        final clippedEndMs = segmentEndMs > sourceEndMs
            ? sourceEndMs
            : segmentEndMs;

        final text = (segment.text as String).trim();

        if (text.isEmpty || clippedEndMs <= clippedStartMs) {
          continue;
        }

        captions.add(
          Caption(
            id: 'auto_${DateTime.now().microsecondsSinceEpoch}_${captions.length}',
            startMs: (timelineOffsetMs + clippedStartMs - sourceStartMs)
                .toInt(),
            endMs: (timelineOffsetMs + clippedEndMs - sourceStartMs).toInt(),
            text: text,

            // Preserve the original source video identity.
            sourceClipId: source.id,

            // Preserve the caption's timestamp in the original video.
            sourceStartMs: clippedStartMs,
          ),
        );
      }

      timelineOffsetMs += timelineClip.duration.inMilliseconds;
    }

    captions.sort((a, b) => a.startMs.compareTo(b.startMs));

    onProgress?.call(100);
    onStatus?.call('Captions generated successfully.');

    return captions;
  }
}
