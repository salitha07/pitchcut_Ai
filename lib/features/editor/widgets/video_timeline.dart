import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/video_clip.dart';
import '../models/trim_range.dart';

/// A horizontally scrollable timeline. The editor owns playback state and
/// supplies the current time; this widget reports user seeks back to the editor.
class VideoTimeline extends StatefulWidget {
  const VideoTimeline({
    super.key,
    required this.clips,
    required this.selectedClipIndex,
    required this.position,
    required this.trimRange,
    required this.onSeek,
    required this.onClipSelected,
    required this.onTrimChanged,
  });

  final List<VideoClip> clips;
  final int selectedClipIndex;
  final Duration position;
  final TrimRange trimRange;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<int> onClipSelected;
  final ValueChanged<TrimRange> onTrimChanged;

  @override
  State<VideoTimeline> createState() => _VideoTimelineState();
}

class _VideoTimelineState extends State<VideoTimeline> {
  final ScrollController _scrollController = ScrollController();
  double _pixelsPerSecond = 36;
  double _dragPositionMs = 0;
  double _trimDragPositionMs = 0;
  bool _draggingPlayhead = false;

  Duration get _totalDuration =>
      widget.clips.fold(Duration.zero, (total, clip) => total + clip.duration);

  @override
  void didUpdateWidget(covariant VideoTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_draggingPlayhead && oldWidget.position != widget.position) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _keepPlayheadVisible(),
      );
    }
  }

  void _keepPlayheadVisible() {
    if (!_scrollController.hasClients || !mounted) return;
    final target = widget.position.inMilliseconds / 1000 * _pixelsPerSecond;
    final currentOffset = _scrollController.offset;
    final viewport = _scrollController.position.viewportDimension;
    if (target > currentOffset + viewport - 40) {
      _scrollController.jumpTo(
        math
            .min(
              target - viewport + 40,
              _scrollController.position.maxScrollExtent,
            )
            .toDouble(),
      );
    } else if (target < currentOffset) {
      _scrollController.jumpTo(
        target.clamp(0, _scrollController.position.maxScrollExtent).toDouble(),
      );
    }
  }

  void _startPlayheadDrag() {
    _draggingPlayhead = true;
    _dragPositionMs = widget.position.inMilliseconds.toDouble();
  }

  void _updatePlayheadDrag(DragUpdateDetails details) {
    final totalMs = _totalDuration.inMilliseconds;
    if (totalMs <= 0) return;
    _dragPositionMs =
        (_dragPositionMs + details.delta.dx / _pixelsPerSecond * 1000)
            .clamp(0, totalMs)
            .toDouble();
    widget.onSeek(Duration(milliseconds: _dragPositionMs.round()));
  }

  void _endPlayheadDrag() {
    _draggingPlayhead = false;
  }

  void _startTrimDrag(Duration position) {
    _trimDragPositionMs = position.inMilliseconds.toDouble();
  }

  void _updateTrimStart(DragUpdateDetails details, VideoClip clip) {
    _trimDragPositionMs += details.delta.dx / _pixelsPerSecond * 1000;
    widget.onTrimChanged(
      TrimRange.clampStart(
        Duration(milliseconds: _trimDragPositionMs.round()),
        widget.trimRange.end,
        clip.duration,
      ),
    );
  }

  void _updateTrimEnd(DragUpdateDetails details, VideoClip clip) {
    _trimDragPositionMs += details.delta.dx / _pixelsPerSecond * 1000;
    widget.onTrimChanged(
      TrimRange.clampEnd(
        widget.trimRange.start,
        Duration(milliseconds: _trimDragPositionMs.round()),
        clip.duration,
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.clips.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalMs = _totalDuration.inMilliseconds;
        final totalSeconds = math.max(0.001, totalMs / 1000).toDouble();
        _pixelsPerSecond = math
            .max(36.0, constraints.maxWidth / totalSeconds)
            .toDouble();
        final contentWidth = math
            .max(constraints.maxWidth, totalSeconds * _pixelsPerSecond)
            .toDouble();
        final playheadX =
            (widget.position.inMilliseconds / 1000 * _pixelsPerSecond)
                .clamp(0, contentWidth)
                .toDouble();
        final markerInterval = _markerInterval(totalSeconds);

        return SizedBox(
          height: 148,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              height: 148,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 27,
                    child: _TimeRuler(
                      duration: _totalDuration,
                      pixelsPerSecond: _pixelsPerSecond,
                      intervalSeconds: markerInterval,
                    ),
                  ),
                  Positioned(
                    top: 30,
                    left: 0,
                    right: 0,
                    height: 88,
                    child: Row(
                      children: [
                        for (var i = 0; i < widget.clips.length; i++)
                          _buildClip(context, i),
                      ],
                    ),
                  ),
                  Positioned(
                    key: const ValueKey('timeline-playhead'),
                    left: playheadX - 1,
                    top: 20,
                    bottom: 10,
                    child: IgnorePointer(
                      child: Container(
                        key: const ValueKey('timeline-playhead-line'),
                        width: 2,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  Positioned(
                    left: (playheadX - 18)
                        .clamp(0, math.max(0.0, contentWidth - 36))
                        .toDouble(),
                    top: 5,
                    child: GestureDetector(
                      key: const ValueKey('timeline-playhead-handle'),
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (_) => _startPlayheadDrag(),
                      onHorizontalDragUpdate: _updatePlayheadDrag,
                      onHorizontalDragEnd: (_) => _endPlayheadDrag(),
                      onHorizontalDragCancel: _endPlayheadDrag,
                      child: Container(
                        width: 36,
                        height: 28,
                        alignment: Alignment.topCenter,
                        child: Icon(
                          Icons.arrow_drop_down,
                          size: 30,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildClip(BuildContext context, int index) {
    final clip = widget.clips[index];
    final width = clip.duration.inMilliseconds / 1000 * _pixelsPerSecond;
    final selected = index == widget.selectedClipIndex;
    final trimStartX =
        width *
        (widget.trimRange.start.inMilliseconds /
            math.max(1, clip.duration.inMilliseconds));
    final trimEndX =
        width *
        (widget.trimRange.end.inMilliseconds /
            math.max(1, clip.duration.inMilliseconds));
    return GestureDetector(
      key: ValueKey('timeline-clip-$index'),
      onTap: () => widget.onClipSelected(index),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.white38,
            width: selected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: clip.thumbnail == null
                      ? const Center(child: Icon(Icons.movie_outlined))
                      : Image.memory(
                          clip.thumbnail!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  child: Text(
                    clip.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 5, right: 5, bottom: 3),
                  child: Text(
                    _formatDuration(clip.duration),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            if (selected) ...[
              if (trimStartX > 0)
                Positioned.fill(
                  right: width - trimStartX,
                  child: const ColoredBox(color: Color(0x77000000)),
                ),
              if (trimEndX < width)
                Positioned.fill(
                  left: trimEndX,
                  child: const ColoredBox(color: Color(0x77000000)),
                ),
              Positioned(
                left: trimStartX,
                right: width - trimEndX,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.amber, width: 2),
                    ),
                  ),
                ),
              ),
              _trimHandle(
                key: const ValueKey('trim-start-handle'),
                left: trimStartX - 7,
                clip: clip,
                position: widget.trimRange.start,
                onStart: _startTrimDrag,
                onUpdate: _updateTrimStart,
              ),
              _trimHandle(
                key: const ValueKey('trim-end-handle'),
                left: trimEndX - 7,
                clip: clip,
                position: widget.trimRange.end,
                onStart: _startTrimDrag,
                onUpdate: _updateTrimEnd,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _trimHandle({
    required Key key,
    required double left,
    required VideoClip clip,
    required Duration position,
    required void Function(Duration) onStart,
    required void Function(DragUpdateDetails, VideoClip) onUpdate,
  }) {
    return Positioned(
      key: key,
      left: left
          .clamp(
            0,
            math.max(
              0.0,
              _pixelsPerSecond * clip.duration.inMilliseconds / 1000 - 14,
            ),
          )
          .toDouble(),
      top: 0,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => onStart(position),
        onHorizontalDragUpdate: (details) => onUpdate(details, clip),
        child: Container(
          width: 14,
          decoration: BoxDecoration(
            color: Colors.amber,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(
            Icons.drag_indicator,
            size: 12,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  int _markerInterval(double totalSeconds) {
    if (totalSeconds > 900) return 120;
    if (totalSeconds > 300) return 60;
    if (totalSeconds > 120) return 30;
    if (totalSeconds > 60) return 15;
    if (totalSeconds > 30) return 10;
    if (totalSeconds > 10) return 5;
    return 1;
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    final minutes = seconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

class _TimeRuler extends StatelessWidget {
  const _TimeRuler({
    required this.duration,
    required this.pixelsPerSecond,
    required this.intervalSeconds,
  });

  final Duration duration;
  final double pixelsPerSecond;
  final int intervalSeconds;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = duration.inMilliseconds / 1000;
    final markerCount = (totalSeconds / intervalSeconds).ceil();
    return Stack(
      children: [
        for (var marker = 0; marker <= markerCount; marker++)
          Positioned(
            left: marker * intervalSeconds * pixelsPerSecond,
            top: 0,
            bottom: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatTime(Duration(seconds: marker * intervalSeconds)),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Expanded(
                  child: Container(
                    width: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _formatTime(Duration duration) {
    final seconds = duration.inSeconds;
    final minutes = seconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
