import 'package:flutter/material.dart';

import 'models/video_clip.dart';
import 'models/video_export_state.dart';
import 'services/video_export_controller.dart';
import 'services/video_export_service.dart';

class VideoExportScreen extends StatefulWidget {
  const VideoExportScreen({
    super.key,
    required this.clips,
    required this.duration,
    required this.sourceAspectRatio,
  });

  final List<VideoClip> clips;
  final Duration duration;
  final double sourceAspectRatio;

  @override
  State<VideoExportScreen> createState() => _VideoExportScreenState();
}

class _VideoExportScreenState extends State<VideoExportScreen> {
  late final VideoExportController _exportController;
  VideoExportQuality _quality = VideoExportQuality.p720;
  bool _openingSuccess = false;

  @override
  void initState() {
    super.initState();
    _exportController = VideoExportController(backend: VideoExportService())
      ..addListener(_onExportStateChanged);
  }

  void _onExportStateChanged() {
    if (!mounted) return;
    setState(() {});
    final state = _exportController.state;
    if (state.status == VideoExportStatus.succeeded && !_openingSuccess) {
      _openingSuccess = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || state.outputPath == null) return;
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => VideoExportSuccessScreen(
              outputPath: state.outputPath!,
              quality: _quality,
              duration: widget.duration,
            ),
          ),
        );
      });
    }
  }

  double get _estimatedMegabytes {
    final bitsPerSecond = _quality.videoBitrate + 128000;
    return widget.duration.inSeconds * bitsPerSecond / 8 / (1024 * 1024);
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _exportController.removeListener(_onExportStateChanged);
    _exportController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _exportController.state;
    final isBusy = state.isBusy;
    final ratio = widget.sourceAspectRatio > 0
        ? widget.sourceAspectRatio
        : 16 / 9;
    final outputWidth = (ratio * _quality.height).round();

    return PopScope(
      canPop: !isBusy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Export video')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Video information',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(label: 'Clips', value: '${widget.clips.length}'),
                      _InfoRow(
                        label: 'Edited duration',
                        value: _formatDuration(widget.duration),
                      ),
                      _InfoRow(
                        label: 'Sources',
                        value: widget.clips.map((clip) => clip.name).join(', '),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Export quality',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<VideoExportQuality>(
                segments: VideoExportQuality.values
                    .map(
                      (quality) => ButtonSegment(
                        value: quality,
                        label: Text(quality.label),
                      ),
                    )
                    .toList(growable: false),
                selected: {_quality},
                onSelectionChanged: isBusy
                    ? null
                    : (value) => setState(() => _quality = value.first),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estimated output',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(
                        label: 'Resolution target',
                        value:
                            '$outputWidth × ${_quality.height} (${_quality.label})',
                      ),
                      const _InfoRow(label: 'Format', value: 'MP4'),
                      const _InfoRow(
                        label: 'Video / audio',
                        value: 'H.264 / AAC',
                      ),
                      _InfoRow(
                        label: 'Estimated file size',
                        value: '~${_estimatedMegabytes.toStringAsFixed(1)} MB',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Estimate varies with source resolution, motion, and device encoder support.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (state.status == VideoExportStatus.exporting ||
                  state.status == VideoExportStatus.cancelling) ...[
                LinearProgressIndicator(value: state.progress),
                const SizedBox(height: 8),
                Text(
                  state.status == VideoExportStatus.cancelling
                      ? 'Cancelling export…'
                      : state.progress == null
                      ? 'Preparing export…'
                      : '${(state.progress! * 100).round()}% exported',
                  textAlign: TextAlign.center,
                ),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('cancel-video-export'),
                  onPressed: state.status == VideoExportStatus.exporting
                      ? _exportController.cancel
                      : null,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel export'),
                ),
              ] else if (state.status == VideoExportStatus.failed) ...[
                Text(
                  state.errorMessage ?? 'Video export failed.',
                  key: const ValueKey('video-export-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      _exportController.start(widget.clips, _quality),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ] else if (state.status == VideoExportStatus.cancelled) ...[
                const Text('Export cancelled. No output was kept.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      _exportController.start(widget.clips, _quality),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Export again'),
                ),
              ] else ...[
                FilledButton.icon(
                  key: const ValueKey('start-video-export'),
                  onPressed: widget.clips.isEmpty
                      ? null
                      : () => _exportController.start(widget.clips, _quality),
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Start export'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class VideoExportSuccessScreen extends StatelessWidget {
  const VideoExportSuccessScreen({
    super.key,
    required this.outputPath,
    required this.quality,
    required this.duration,
  });

  final String outputPath;
  final VideoExportQuality quality;
  final Duration duration;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Export complete')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
              size: 72,
            ),
            const SizedBox(height: 16),
            Text(
              'Video exported successfully',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text('${quality.label} · MP4 · ${_durationText(duration)}'),
            const SizedBox(height: 8),
            SelectableText(outputPath, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    ),
  );

  static String _durationText(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 145, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
