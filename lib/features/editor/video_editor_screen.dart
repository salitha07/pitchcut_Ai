import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pitchcut_ai/features/editor/models/trim_range.dart';
import 'package:pitchcut_ai/features/editor/models/crop_rect.dart';
import 'package:pitchcut_ai/features/editor/models/editor_state_snapshot.dart';
import 'package:pitchcut_ai/features/editor/models/editor_suggestion.dart';
import 'package:pitchcut_ai/features/editor/models/video_clip.dart';
import 'package:pitchcut_ai/features/editor/services/editor_command_history.dart';
import 'package:pitchcut_ai/features/editor/services/editor_project_store.dart';
import 'package:pitchcut_ai/features/editor/services/timeline_operations.dart';
import 'package:pitchcut_ai/features/editor/services/video_trim_service.dart';
import 'package:pitchcut_ai/features/editor/video_export_screen.dart';
import 'package:pitchcut_ai/features/editor/widgets/video_timeline.dart';
import 'package:pitchcut_ai/features/editor/widgets/crop_frame_editor.dart';
import 'package:pitchcut_ai/features/editor/widgets/suggestion_bar.dart';
import 'package:video_player/video_player.dart';

/// A local video editor preview with a multi-clip playback timeline.
class VideoEditorScreen extends StatefulWidget {
  const VideoEditorScreen({
    super.key,
    required this.videoPath,
    this.videoName,
    this.suggestions = const [],
    this.onSuggestionAccepted,
    this.onSuggestionDismissed,
  });

  final String videoPath;
  final String? videoName;
  final List<EditorSuggestion> suggestions;
  final ValueChanged<EditorSuggestion>? onSuggestionAccepted;
  final ValueChanged<EditorSuggestion>? onSuggestionDismissed;

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  final List<VideoClip> _clips = [];
  final EditorCommandHistory<EditorStateSnapshot> _history =
      EditorCommandHistory<EditorStateSnapshot>();
  final EditorProjectStore _projectStore = EditorProjectStore();
  final VideoTrimService _trimService = VideoTrimService();
  List<SavedExport> _savedExports = const [];
  final Set<String> _dismissedSuggestionIds = {};
  VideoPlayerController? _controller;
  String? _loadError;
  bool _isLoading = true;
  bool _isTransitioning = false;
  bool _isPlaybackActive = false;
  bool _isTrimming = false;
  bool _isExporting = false;
  bool _isCropping = false;
  CropRect _draftCrop = CropRect.full;
  int? _mergeFirstIndex;
  int _selectedClipIndex = 0;
  int _controllerGeneration = 0;
  Duration _timelinePosition = Duration.zero;
  Future<void> _persistenceQueue = Future<void>.value();
  TrimRange _trimRange = const TrimRange(
    start: Duration.zero,
    end: Duration.zero,
  );

  Duration get _totalDuration =>
      _clips.fold(Duration.zero, (total, clip) => total + clip.duration);

  bool get _isBusy => _isTrimming || _isExporting;

  EditorStateSnapshot _captureState() => EditorStateSnapshot(
    clips: _clips,
    selectedClipIndex: _selectedClipIndex,
    trimRange: _trimRange,
    timelinePosition: _timelinePosition,
  );

  void _recordEdit(EditorStateSnapshot before) {
    _history.record(before: before, after: _captureState());
  }

  @override
  void initState() {
    super.initState();
    _initializeFirstClip();
  }

  Future<void> _initializeFirstClip() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    VideoPlayerController? controller;
    try {
      final savedProject = await _projectStore.load(widget.videoPath);
      if (savedProject != null) {
        _savedExports = savedProject.exports;
        final savedClips = <VideoClip>[];
        for (final savedClip in savedProject.clips) {
          if (!await File(savedClip.path).exists()) continue;
          Uint8List? thumbnail;
          try {
            thumbnail = await _trimService.generateThumbnail(
              savedClip.path,
              time:
                  savedClip.sourceStart +
                  Duration(
                    milliseconds: savedClip.duration.inMilliseconds ~/ 3,
                  ),
            );
          } catch (_) {
            // A missing thumbnail does not invalidate a saved media clip.
          }
          savedClips.add(savedClip.copyWith(thumbnail: thumbnail));
        }
        if (savedClips.isNotEmpty || savedProject.clips.isEmpty) {
          _clips.addAll(savedClips);
          _selectedClipIndex = savedClips.isEmpty
              ? 0
              : savedProject.selectedClipIndex.clamp(0, savedClips.length - 1);
          final savedRange = savedProject.trimRange;
          _trimRange =
              savedClips.isNotEmpty &&
                  savedRange.isValidFor(savedClips[_selectedClipIndex].duration)
              ? savedRange
              : TrimRange(
                  start: Duration.zero,
                  end: savedClips.isEmpty
                      ? Duration.zero
                      : savedClips[_selectedClipIndex].duration,
                );
          if (savedClips.isEmpty) {
            setState(() => _isLoading = false);
          } else {
            final requestedRange = _trimRange;
            await _activateClip(
              _selectedClipIndex,
              position: requestedRange.start,
            );
            if (requestedRange.isValidFor(
              _clips[_selectedClipIndex].duration,
            )) {
              setState(() => _trimRange = requestedRange);
            }
          }
          await _persistProject();
          return;
        }
      }
      final probed = await _probeClip(widget.videoPath, widget.videoName);
      controller = probed.controller;
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _clips
        ..clear()
        ..add(probed.clip);
      _trimRange = TrimRange(start: Duration.zero, end: probed.clip.duration);
      _controller = controller;
      controller.addListener(_onVideoChanged);
      setState(() => _isLoading = false);
      await _persistProject();
    } catch (error) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = _friendlyError(error);
      });
    }
  }

  Future<_ProbedClip> _probeClip(String path, String? name) async {
    if (path.trim().isEmpty || !await File(path).exists()) {
      throw const FileSystemException('The selected video file was not found.');
    }

    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      final duration = controller.value.duration;
      final thumbnail = await _trimService.generateThumbnail(
        path,
        time: Duration(milliseconds: duration.inMilliseconds ~/ 3),
      );
      return _ProbedClip(
        VideoClip(
          path: path,
          name: name ?? path.split(Platform.pathSeparator).last,
          duration: duration,
          thumbnail: thumbnail,
        ),
        controller,
      );
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }

  String _friendlyError(Object error) {
    if (error is FileSystemException) {
      return 'This video could not be found. Choose another recorded video.';
    }
    final description = _controller?.value.errorDescription;
    if (description != null && description.isNotEmpty) {
      return 'This video could not be played. $description';
    }
    return 'This video could not be loaded. Choose another video or try again.';
  }

  Future<void> _addClip() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Add a video clip',
        type: FileType.video,
      );
      if (!mounted || file == null) return;
      final path = file.path;
      if (path == null || path.isEmpty) {
        _showMessage('Could not access the selected video.');
        return;
      }

      final probed = await _probeClip(path, file.name);
      await probed.controller.dispose();
      if (!mounted) return;
      final before = _captureState();
      setState(() {
        _clips.add(probed.clip);
        _loadError = null;
      });
      _recordEdit(before);
      await _persistProject();
    } catch (error) {
      if (mounted) _showMessage('Could not add this video: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _persistProject() async {
    final clips = List<VideoClip>.unmodifiable(_clips);
    final selectedClipIndex = _selectedClipIndex;
    final trimRange = _trimRange;
    final write = _persistenceQueue.then(
      (_) => _projectStore.save(
        projectId: widget.videoPath,
        clips: clips,
        selectedClipIndex: selectedClipIndex,
        trimRange: trimRange,
      ),
    );
    _persistenceQueue = write.catchError((Object error) {
      if (mounted) _showMessage('Could not save editor state: $error');
    });
    await _persistenceQueue;
  }

  Future<void> _splitSelectedClip() async {
    if (_clips.isEmpty) return;
    final index = _selectedClipIndex;
    final clip = _clips[index];
    final clipPosition = _timelinePosition - _clipStart(index);
    if (!TimelineOperations.canSplit(clip, clipPosition)) {
      _showMessage(
        'Move the playhead so both new clips are at least 0.5 seconds.',
      );
      return;
    }
    final before = _captureState();
    final after = TimelineOperations.split(_clips, index, clipPosition);
    _isPlaybackActive = false;
    await _controller?.pause();
    _clips
      ..clear()
      ..addAll(after);
    _selectedClipIndex = index + 1;
    _trimRange = TrimRange(
      start: Duration.zero,
      end: _clips[_selectedClipIndex].duration,
    );
    setState(() => _timelinePosition = _clipStart(_selectedClipIndex));
    _recordEdit(before);
    await _persistProject();
  }

  Future<void> _deleteSelectedClip() async {
    if (_clips.isEmpty) return;
    final before = _captureState();
    final after = TimelineOperations.delete(_clips, _selectedClipIndex);
    _isPlaybackActive = false;
    final previous = _controller;
    _controller = null;
    previous?.removeListener(_onVideoChanged);
    await previous?.pause();
    await previous?.dispose();
    _clips
      ..clear()
      ..addAll(after);

    if (_clips.isEmpty) {
      _selectedClipIndex = 0;
      _trimRange = const TrimRange(start: Duration.zero, end: Duration.zero);
      setState(() {
        _timelinePosition = Duration.zero;
        _isLoading = false;
        _loadError = null;
      });
    } else {
      _selectedClipIndex = _selectedClipIndex.clamp(0, _clips.length - 1);
      await _activateClip(_selectedClipIndex);
    }
    _recordEdit(before);
    await _persistProject();
  }

  Future<void> _reorderClips(int from, int to) async {
    if (from < 0 || from >= _clips.length || to < 0 || to >= _clips.length) {
      return;
    }
    if (from == to) return;
    final selectedClip = _clips[_selectedClipIndex];
    final controllerPosition =
        _controller?.value.position ?? selectedClip.sourceStart;
    final localPosition = controllerPosition - selectedClip.sourceStart;
    final before = _captureState();
    final after = TimelineOperations.reorder(_clips, from, to);
    _clips
      ..clear()
      ..addAll(after);
    _selectedClipIndex = _clips.indexOf(selectedClip);
    setState(
      () => _timelinePosition = _clipStart(_selectedClipIndex) + localPosition,
    );
    _recordEdit(before);
    await _persistProject();
  }

  Future<void> _mergeAdjacentClips() async {
    if (_mergeFirstIndex == null) {
      setState(() => _mergeFirstIndex = _selectedClipIndex);
      _showMessage('Now select the adjacent clip to merge.');
      return;
    }
    final first = _mergeFirstIndex!;
    final second = _selectedClipIndex;
    setState(() => _mergeFirstIndex = null);
    if ((first - second).abs() != 1) {
      _showMessage('Choose a clip directly next to the selected clip.');
      return;
    }
    final firstIndex = first < second ? first : second;
    final firstClip = _clips[firstIndex];
    final secondClip = _clips[firstIndex + 1];
    if (!TimelineOperations.canMerge(firstClip, secondClip)) {
      _showMessage(
        'Merge requires both clips to use the same rotation and crop.',
      );
      return;
    }
    final before = _captureState();
    List<VideoClip> after;
    if (TimelineOperations.canMergeWithoutRendering(firstClip, secondClip)) {
      after = TimelineOperations.merge(_clips, firstIndex);
    } else {
      setState(() => _isExporting = true);
      _isPlaybackActive = false;
      await _controller?.pause();
      try {
        final outputPath = await _trimService.exportTimeline([
          firstClip,
          secondClip,
        ]);
        if (!await File(outputPath).exists()) {
          throw const FileSystemException('The merged video was not created.');
        }
        final probed = await _probeClip(
          outputPath,
          '${firstClip.name} + ${secondClip.name}',
        );
        await probed.controller.dispose();
        after = TimelineOperations.merge(
          _clips,
          firstIndex,
          renderedClip: probed.clip,
        );
      } catch (error) {
        if (mounted) _showMessage('Could not merge these clips: $error');
        return;
      } finally {
        if (mounted) setState(() => _isExporting = false);
      }
    }
    _clips
      ..clear()
      ..addAll(after);
    _selectedClipIndex = firstIndex;
    await _activateClip(_selectedClipIndex);
    _recordEdit(before);
    await _persistProject();
  }

  Future<void> _rotateSelectedClip() async {
    if (_clips.isEmpty) return;
    final before = _captureState();
    final after = List<VideoClip>.of(_clips);
    after[_selectedClipIndex] = TimelineOperations.rotate(
      after[_selectedClipIndex],
    );
    _clips
      ..clear()
      ..addAll(after);
    setState(() {});
    _recordEdit(before);
    await _persistProject();
  }

  Future<void> _beginCrop() async {
    if (_clips.isEmpty) return;
    _isPlaybackActive = false;
    await _controller?.pause();
    setState(() {
      _draftCrop = _clips[_selectedClipIndex].crop ?? CropRect.full;
      _isCropping = true;
    });
  }

  Future<void> _applyCrop() async {
    if (_clips.isEmpty || !_draftCrop.isValid) return;
    final before = _captureState();
    final after = List<VideoClip>.of(_clips);
    after[_selectedClipIndex] = TimelineOperations.crop(
      after[_selectedClipIndex],
      _draftCrop,
    );
    _clips
      ..clear()
      ..addAll(after);
    setState(() => _isCropping = false);
    _recordEdit(before);
    await _persistProject();
  }

  Future<void> _openExportScreen() async {
    if (_clips.isEmpty || _isBusy || _isCropping) return;
    _isPlaybackActive = false;
    await _controller?.pause();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VideoExportScreen(
          clips: List.unmodifiable(_clips),
          duration: _totalDuration,
          sourceAspectRatio: _previewAspectRatio(_controller?.value),
          projectId: widget.videoPath,
          projectClips: List.unmodifiable(_clips),
          selectedClipIndex: _selectedClipIndex,
          trimRange: _trimRange,
        ),
      ),
    );
    final project = await _projectStore.load(widget.videoPath);
    if (mounted && project != null)
      setState(() => _savedExports = project.exports);
  }

  List<EditorSuggestion> get _visibleSuggestions => widget.suggestions
      .where((suggestion) => !_dismissedSuggestionIds.contains(suggestion.id))
      .toList(growable: false);

  void _dismissSuggestion(EditorSuggestion suggestion) {
    setState(() => _dismissedSuggestionIds.add(suggestion.id));
    widget.onSuggestionDismissed?.call(suggestion);
  }

  Future<void> _acceptSuggestion(EditorSuggestion suggestion) async {
    final action = suggestion.action;
    if (action is SeekSuggestionAction) {
      if (_isValidTimelinePosition(action.position)) {
        await _seekToTimeline(action.position);
      } else {
        _showMessage('That suggestion points outside the current timeline.');
      }
    } else if (action is SplitSuggestionAction) {
      if (_isValidTimelinePosition(action.position)) {
        await _seekToTimeline(action.position);
        if (_clips.isNotEmpty) await _splitSelectedClip();
      } else {
        _showMessage('That split point is outside the current timeline.');
      }
    } else if (action is TrimSuggestionAction) {
      if (action.clipIndex >= 0 &&
          action.clipIndex < _clips.length &&
          action.range.isValidFor(_clips[action.clipIndex].duration)) {
        await _selectClip(action.clipIndex);
        _onTrimRangeChanged(action.range);
        await _trimSelectedClip();
      } else {
        _showMessage('That trim range is no longer valid for the timeline.');
      }
    }
    setState(() => _dismissedSuggestionIds.add(suggestion.id));
    widget.onSuggestionAccepted?.call(suggestion);
  }

  bool _isValidTimelinePosition(Duration position) =>
      position >= Duration.zero && position <= _totalDuration;

  void _onVideoChanged() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.hasError) {
      if (_loadError == null) {
        setState(() {
          _isLoading = false;
          _loadError = _friendlyError(StateError('Video playback failed'));
        });
      }
      return;
    }

    final start = _clipStart(_selectedClipIndex);
    final localPosition =
        controller.value.position - _clips[_selectedClipIndex].sourceStart;
    final clip = _clips[_selectedClipIndex];
    if (localPosition < _trimRange.start && _isPlaybackActive) {
      controller.seekTo(_trimRange.start);
      return;
    }
    if (localPosition >= _trimRange.end &&
        _trimRange.end < clip.duration &&
        _isPlaybackActive) {
      _isPlaybackActive = false;
      controller.pause();
      setState(() => _timelinePosition = start + _trimRange.end);
      return;
    }
    if (localPosition >= clip.duration && _isPlaybackActive) {
      if (!_isTransitioning) _advanceToNextClip();
      return;
    }
    setState(() => _timelinePosition = start + localPosition);
  }

  Future<void> _advanceToNextClip() async {
    if (_isTransitioning) return;
    _isTransitioning = true;
    try {
      final nextIndex = _selectedClipIndex + 1;
      if (nextIndex >= _clips.length) {
        _isPlaybackActive = false;
        await _controller?.pause();
        if (mounted) setState(() => _timelinePosition = _totalDuration);
        return;
      }
      await _activateClip(nextIndex, autoPlay: true);
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> _activateClip(
    int index, {
    Duration position = Duration.zero,
    bool autoPlay = false,
  }) async {
    if (index < 0 || index >= _clips.length) return;
    final clip = _clips[index];
    final generation = ++_controllerGeneration;
    final previous = _controller;
    _controller = null;
    previous?.removeListener(_onVideoChanged);
    await previous?.dispose();
    if (!mounted || generation != _controllerGeneration) return;

    setState(() {
      _isLoading = true;
      _loadError = null;
      _selectedClipIndex = index;
      _trimRange = TrimRange(start: Duration.zero, end: _clips[index].duration);
      _timelinePosition = _clipStart(index) + position;
    });

    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(File(_clips[index].path));
      await controller.initialize();
      if (!mounted || generation != _controllerGeneration) {
        await controller.dispose();
        return;
      }
      final maxPosition = clip.duration;
      final safePosition = position > maxPosition ? maxPosition : position;
      final sourcePosition = clip.sourceStart + safePosition;
      if (sourcePosition > controller.value.duration) {
        throw StateError('This clip range exceeds its source video duration.');
      }
      if (sourcePosition > Duration.zero)
        await controller.seekTo(sourcePosition);
      _controller = controller;
      controller.addListener(_onVideoChanged);
      setState(() => _isLoading = false);
      if (autoPlay) {
        _isPlaybackActive = true;
        await controller.play();
      }
    } catch (error) {
      await controller?.dispose();
      if (!mounted || generation != _controllerGeneration) return;
      setState(() {
        _isLoading = false;
        _loadError = _friendlyError(error);
      });
    }
  }

  Duration _clipStart(int index) {
    var start = Duration.zero;
    for (var i = 0; i < index && i < _clips.length; i++) {
      start += _clips[i].duration;
    }
    return start;
  }

  Future<void> _seekToTimeline(Duration requestedPosition) async {
    if (_clips.isEmpty) return;
    final total = _totalDuration;
    final absoluteMs = requestedPosition.inMilliseconds
        .clamp(0, total.inMilliseconds)
        .toInt();
    var startMs = 0;
    var targetIndex = _clips.length - 1;
    var localMs = _clips.last.duration.inMilliseconds;
    for (var i = 0; i < _clips.length; i++) {
      final endMs = startMs + _clips[i].duration.inMilliseconds;
      if (absoluteMs < endMs || i == _clips.length - 1) {
        targetIndex = i;
        localMs = (absoluteMs - startMs)
            .clamp(0, _clips[i].duration.inMilliseconds)
            .toInt();
        break;
      }
      startMs = endMs;
    }

    final localPosition = Duration(milliseconds: localMs);
    if (targetIndex == _selectedClipIndex &&
        _controller?.value.isInitialized == true) {
      final boundedPosition = localPosition < _trimRange.start
          ? _trimRange.start
          : localPosition > _trimRange.end
          ? _trimRange.end
          : localPosition;
      setState(
        () => _timelinePosition = _clipStart(targetIndex) + boundedPosition,
      );
      await _controller!.seekTo(
        _clips[targetIndex].sourceStart + boundedPosition,
      );
      return;
    }
    final keepPlaying = _isPlaybackActive;
    await _activateClip(
      targetIndex,
      position: localPosition,
      autoPlay: keepPlaying,
    );
  }

  Future<void> _selectClip(int index) async {
    await _seekToTimeline(_clipStart(index));
    await _persistProject();
  }

  void _onTrimRangeChanged(TrimRange range) {
    final clip = _clips[_selectedClipIndex];
    if (!range.isValidFor(clip.duration)) return;
    setState(() => _trimRange = range);
    final position = _controller?.value.position;
    final localPosition = position == null ? null : position - clip.sourceStart;
    if (localPosition != null && localPosition < range.start) {
      _controller?.seekTo(clip.sourceStart + range.start);
      setState(
        () => _timelinePosition = _clipStart(_selectedClipIndex) + range.start,
      );
    } else if (localPosition != null && localPosition > range.end) {
      _controller?.seekTo(clip.sourceStart + range.end);
      setState(
        () => _timelinePosition = _clipStart(_selectedClipIndex) + range.end,
      );
    }
    unawaited(_persistProject());
  }

  Future<void> _trimSelectedClip() async {
    if (_clips.isEmpty || _isTrimming) return;
    final clip = _clips[_selectedClipIndex];
    if (!_trimRange.isValidFor(clip.duration)) {
      _showMessage('Choose a trim range of at least 0.5 seconds.');
      return;
    }
    if (_trimRange.start == Duration.zero && _trimRange.end == clip.duration) {
      _showMessage('Adjust the trim handles before applying the trim.');
      return;
    }

    final before = _captureState();
    setState(() => _isTrimming = true);
    _isPlaybackActive = false;
    await _controller?.pause();
    try {
      final outputPath = await _trimService.trim(
        inputPath: clip.path,
        start: clip.sourceStart + _trimRange.start,
        end: clip.sourceStart + _trimRange.end,
      );
      if (!await File(outputPath).exists()) {
        throw const FileSystemException('The trimmed video was not created.');
      }
      final probed = await _probeClip(outputPath, clip.name);
      await probed.controller.dispose();

      final afterClips = List<VideoClip>.of(_clips);
      afterClips[_selectedClipIndex] = probed.clip.copyWith(
        rotationDegrees: clip.rotationDegrees,
        crop: clip.crop,
      );
      final index = _selectedClipIndex;
      _clips
        ..clear()
        ..addAll(afterClips);
      setState(() => _timelinePosition = _clipStart(index));
      await _activateClip(index);
      _recordEdit(before);
      await _persistProject();
      if (mounted) _showMessage('Trim applied to ${clip.name}.');
    } catch (error) {
      if (mounted) _showMessage('Could not trim this video: $error');
    } finally {
      if (mounted) setState(() => _isTrimming = false);
    }
  }

  Future<void> _restoreHistory({required bool undo}) async {
    final snapshot = undo ? _history.undo() : _history.redo();
    if (snapshot == null) return;
    _isPlaybackActive = false;
    if (snapshot.clips.isEmpty) {
      final previous = _controller;
      _controller = null;
      previous?.removeListener(_onVideoChanged);
      await previous?.dispose();
      _clips.clear();
      _selectedClipIndex = snapshot.selectedClipIndex;
      if (mounted) {
        setState(() {
          _timelinePosition = snapshot.timelinePosition;
          _trimRange = snapshot.trimRange;
          _isLoading = false;
          _loadError = null;
        });
      }
      await _persistProject();
      return;
    }
    _clips
      ..clear()
      ..addAll(snapshot.clips);
    final index = snapshot.selectedClipIndex.clamp(0, _clips.length - 1);
    final clipStart = _clipStart(index);
    final clip = _clips[index];
    final range = snapshot.trimRange.isValidFor(clip.duration)
        ? snapshot.trimRange
        : TrimRange(start: Duration.zero, end: clip.duration);
    final requestedLocal = snapshot.timelinePosition - clipStart;
    final localPosition = Duration(
      milliseconds: requestedLocal.inMilliseconds
          .clamp(range.start.inMilliseconds, range.end.inMilliseconds)
          .toInt(),
    );
    await _activateClip(index, position: localPosition);
    _selectedClipIndex = index;
    _trimRange = range;
    _timelinePosition = clipStart + localPosition;
    if (mounted) setState(() {});
    await _persistProject();
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      _isPlaybackActive = false;
      await controller.pause();
    } else {
      if (_timelinePosition >= _totalDuration) {
        await _seekToTimeline(Duration.zero);
      } else if (controller.value.position <
              _clips[_selectedClipIndex].sourceStart + _trimRange.start ||
          controller.value.position >=
              _clips[_selectedClipIndex].sourceStart + _trimRange.end) {
        await controller.seekTo(
          _clips[_selectedClipIndex].sourceStart + _trimRange.start,
        );
        setState(
          () => _timelinePosition =
              _clipStart(_selectedClipIndex) + _trimRange.start,
        );
      }
      _isPlaybackActive = true;
      await _controller?.play();
    }
  }

  String _formatTime(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final secondsText = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$secondsText';
    }
    return '${minutes.toString().padLeft(2, '0')}:$secondsText';
  }

  @override
  void dispose() {
    _controllerGeneration++;
    _controller?.removeListener(_onVideoChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final value = controller?.value;
    final ready = value?.isInitialized ?? false;
    final totalDuration = _totalDuration;
    final totalSeconds = totalDuration.inMilliseconds > 0
        ? totalDuration.inMilliseconds / 1000
        : 1.0;
    final positionSeconds = _timelinePosition.inMilliseconds / 1000;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.videoName ?? 'Video Editor'),
        actions: [
          IconButton(
            tooltip: 'Undo',
            onPressed: _history.canUndo && !_isBusy && !_isCropping
                ? () => _restoreHistory(undo: true)
                : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: _history.canRedo && !_isBusy && !_isCropping
                ? () => _restoreHistory(undo: false)
                : null,
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            key: const ValueKey('add-video-clip'),
            tooltip: 'Add video clip',
            onPressed: !_isBusy && !_isCropping ? _addClip : null,
            icon: const Icon(Icons.add_to_photos_outlined),
          ),
          IconButton(
            key: const ValueKey('open-video-export-screen'),
            tooltip: 'Export video',
            onPressed: _clips.isNotEmpty && !_isBusy && !_isCropping
                ? _openExportScreen
                : null,
            icon: _isExporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_upload_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _previewAspectRatio(value),
                  child: ColoredBox(
                    color: Colors.black,
                    child: _buildPreview(controller, ready),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SuggestionBar(
                suggestions: _visibleSuggestions,
                onAccept: _acceptSuggestion,
                onDismiss: _dismissSuggestion,
              ),
            ),
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  children: [
                    Text(
                      _loadError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _activateClip(_selectedClipIndex),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(_formatTime(_timelinePosition)),
                        Expanded(
                          child: Slider(
                            key: const ValueKey('video-seek-bar'),
                            min: 0,
                            max: totalSeconds,
                            value: positionSeconds
                                .clamp(0, totalSeconds)
                                .toDouble(),
                            onChanged:
                                _clips.isNotEmpty && !_isCropping && !_isBusy
                                ? (seconds) => _seekToTimeline(
                                    Duration(
                                      milliseconds: (seconds * 1000).round(),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        Text(_formatTime(totalDuration)),
                      ],
                    ),
                    IconButton.filledTonal(
                      key: const ValueKey('video-play-pause'),
                      tooltip: value?.isPlaying ?? false ? 'Pause' : 'Play',
                      onPressed: ready && !_isCropping && !_isBusy
                          ? _togglePlayback
                          : null,
                      iconSize: 32,
                      icon: Icon(
                        value?.isPlaying ?? false
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('merge-selected-clips'),
                          onPressed:
                              _clips.length >= 2 && !_isCropping && !_isBusy
                              ? _mergeAdjacentClips
                              : null,
                          icon: const Icon(Icons.merge_type),
                          label: Text(
                            _mergeFirstIndex == null
                                ? 'Select merge pair'
                                : 'Merge with selected',
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('rotate-selected-clip'),
                          onPressed:
                              _clips.isNotEmpty && !_isCropping && !_isBusy
                              ? _rotateSelectedClip
                              : null,
                          icon: const Icon(Icons.rotate_right),
                          label: Text(
                            'Rotate ${_clips.isEmpty ? 0 : (_clips[_selectedClipIndex].rotationDegrees + 90) % 360}°',
                          ),
                        ),
                        if (!_isCropping)
                          OutlinedButton.icon(
                            key: const ValueKey('crop-selected-clip'),
                            onPressed: _clips.isNotEmpty && !_isBusy
                                ? _beginCrop
                                : null,
                            icon: const Icon(Icons.crop),
                            label: const Text('Crop'),
                          )
                        else ...[
                          FilledButton(
                            key: const ValueKey('apply-video-crop'),
                            onPressed: _applyCrop,
                            child: const Text('Apply crop'),
                          ),
                          TextButton(
                            key: const ValueKey('cancel-video-crop'),
                            onPressed: () =>
                                setState(() => _isCropping = false),
                            child: const Text('Cancel'),
                          ),
                        ],
                        OutlinedButton.icon(
                          key: const ValueKey('split-selected-clip'),
                          onPressed:
                              !_isCropping &&
                                  !_isBusy &&
                                  _clips.isNotEmpty &&
                                  TimelineOperations.canSplit(
                                    _clips[_selectedClipIndex],
                                    _timelinePosition -
                                        _clipStart(_selectedClipIndex),
                                  )
                              ? _splitSelectedClip
                              : null,
                          icon: const Icon(Icons.call_split),
                          label: const Text('Split'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('delete-selected-clip'),
                          onPressed:
                              _clips.isNotEmpty && !_isCropping && !_isBusy
                              ? _deleteSelectedClip
                              : null,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                        ),
                        FilledButton.icon(
                          key: const ValueKey('apply-video-trim'),
                          onPressed:
                              !_isCropping &&
                                  !_isBusy &&
                                  _clips.isNotEmpty &&
                                  _trimRange.isValidFor(
                                    _clips[_selectedClipIndex].duration,
                                  )
                              ? _trimSelectedClip
                              : null,
                          icon: _isTrimming
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.content_cut),
                          label: Text(_isTrimming ? 'Trimming…' : 'Trim'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (_clips.isNotEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    const Expanded(child: Text('Timeline')),
                    Text(
                      '${_clips.length} ${_clips.length == 1 ? 'clip' : 'clips'}',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: VideoTimeline(
                  clips: List.unmodifiable(_clips),
                  selectedClipIndex: _selectedClipIndex,
                  position: _timelinePosition,
                  trimRange: _trimRange,
                  onSeek: _isCropping || _isBusy ? (_) {} : _seekToTimeline,
                  onClipSelected: _isCropping || _isBusy ? (_) {} : _selectClip,
                  onTrimChanged: _isCropping || _isBusy
                      ? (_) {}
                      : _onTrimRangeChanged,
                  onReorder: _isCropping || _isBusy ? (_, _) {} : _reorderClips,
                ),
              ),
              if (_savedExports.isNotEmpty)
                SizedBox(
                  height: 94,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _savedExports.length,
                    itemBuilder: (context, index) {
                      final saved = _savedExports[index];
                      return Card(
                        child: InkWell(
                          onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  SavedVideoPlayerScreen(path: saved.filePath),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Edited video ${index + 1}'),
                                Text(
                                  '${saved.quality.label} · ${_formatTime(saved.duration)}',
                                ),
                                const Text(
                                  'Tap to play',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(VideoPlayerController? controller, bool ready) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return const Center(
        child: Icon(
          Icons.videocam_off_outlined,
          color: Colors.white70,
          size: 48,
        ),
      );
    }
    if (ready && controller != null) {
      final clip = _clips[_selectedClipIndex];
      final crop = _isCropping ? CropRect.full : (clip.crop ?? CropRect.full);
      final quarterTurns = (clip.rotationDegrees ~/ 90) % 4;
      final media = RotatedBox(
        quarterTurns: quarterTurns,
        child: VideoPlayer(controller),
      );
      return LayoutBuilder(
        builder: (context, box) {
          final cropped = ClipRect(
            child: Align(
              alignment: Alignment(
                crop.left + crop.right - 1,
                crop.top + crop.bottom - 1,
              ),
              child: SizedBox(
                width: box.maxWidth / crop.width,
                height: box.maxHeight / crop.height,
                child: media,
              ),
            ),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              cropped,
              if (_isCropping)
                CropFrameEditor(
                  crop: _draftCrop,
                  onChanged: (crop) => setState(() => _draftCrop = crop),
                ),
            ],
          );
        },
      );
    }
    return const SizedBox.shrink();
  }

  double _previewAspectRatio(VideoPlayerValue? value) {
    if (_clips.isEmpty || value == null || value.aspectRatio <= 0)
      return 16 / 9;
    final clip = _clips[_selectedClipIndex];
    final rotated = clip.rotationDegrees % 180 == 0
        ? value.aspectRatio
        : 1 / value.aspectRatio;
    final crop = _isCropping ? null : clip.crop;
    return crop == null ? rotated : (rotated * crop.width / crop.height);
  }
}

class _ProbedClip {
  const _ProbedClip(this.clip, this.controller);

  final VideoClip clip;
  final VideoPlayerController controller;
}
