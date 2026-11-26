import 'package:flutter/foundation.dart';

enum VideoExportQuality {
  p480(label: '480p', height: 480, videoBitrate: 1_500_000),
  p720(label: '720p', height: 720, videoBitrate: 3_500_000),
  p1080(label: '1080p', height: 1080, videoBitrate: 6_000_000);

  const VideoExportQuality({
    required this.label,
    required this.height,
    required this.videoBitrate,
  });

  final String label;
  final int height;
  final int videoBitrate;
}

enum VideoExportStatus {
  idle,
  exporting,
  cancelling,
  cancelled,
  failed,
  succeeded,
}

@immutable
class VideoExportState {
  const VideoExportState({
    this.status = VideoExportStatus.idle,
    this.progress,
    this.outputPath,
    this.errorMessage,
  });

  final VideoExportStatus status;

  /// Real native progress, normalized to 0.0 through 1.0. Null until reported.
  final double? progress;
  final String? outputPath;
  final String? errorMessage;

  bool get isBusy =>
      status == VideoExportStatus.exporting ||
      status == VideoExportStatus.cancelling;
}
