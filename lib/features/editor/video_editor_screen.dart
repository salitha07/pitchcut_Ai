import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pitchcut_ai/features/editor/models/clip_background.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchcut_ai/features/editor/models/trim_range.dart';
import 'package:pitchcut_ai/features/editor/models/crop_rect.dart';
import 'package:pitchcut_ai/features/editor/models/editor_state_snapshot.dart';
import 'package:pitchcut_ai/features/editor/models/editor_suggestion.dart';
import 'package:pitchcut_ai/features/editor/models/video_clip.dart';
import 'package:pitchcut_ai/features/editor/services/editor_command_history.dart';
import 'package:pitchcut_ai/features/editor/services/editor_project_store.dart';
import 'package:pitchcut_ai/features/editor/services/project_clip_adapter.dart';
import 'package:pitchcut_ai/features/editor/services/timeline_operations.dart';
import 'package:pitchcut_ai/features/editor/services/video_trim_service.dart';
import 'package:pitchcut_ai/features/editor/services/native_ai_preview_service.dart';
import 'package:pitchcut_ai/features/editor/video_export_screen.dart';
import 'package:pitchcut_ai/features/editor/widgets/video_timeline.dart';
import 'package:pitchcut_ai/features/editor/widgets/crop_frame_editor.dart';
import 'package:pitchcut_ai/features/editor/widgets/suggestion_bar.dart';
import 'package:pitchcut_ai/features/captions/ui/caption_overlay.dart';
import 'package:pitchcut_ai/models/caption.dart' as m7;
import 'package:pitchcut_ai/models/clip.dart' as m2;
import 'package:pitchcut_ai/models/project.dart' as m2;
import 'package:video_player/video_player.dart';

/// A local video editor preview with a multi-clip playback timeline.
class VideoEditorScreen extends StatefulWidget {
  const VideoEditorScreen({
    super.key,
    required this.videoPath,
    this.videoName,
    this.project,
    this.projectClips,
    this.initialTimeline,
    this.projectStore,
    this.trimService,
    this.fileExists,
    this.suggestions = const [],
    this.onSuggestionAccepted,
    this.onSuggestionDismissed,
    this.captions = const [],
  });

  final String videoPath;
  final String? videoName;
  final m2.Project? project;
  final List<m2.Clip>? projectClips;
  final ProjectEditorTimeline? initialTimeline;
  final EditorProjectStore? projectStore;
  final VideoTrimService? trimService;
  final Future<bool> Function(String path)? fileExists;
  final List<EditorSuggestion> suggestions;
  final ValueChanged<EditorSuggestion>? onSuggestionAccepted;
  final ValueChanged<EditorSuggestion>? onSuggestionDismissed;
  final List<m7.Caption> captions;

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  final List<VideoClip> _clips = [];
  final EditorCommandHistory<EditorStateSnapshot> _history =
      EditorCommandHistory<EditorStateSnapshot>();
  late final EditorProjectStore _projectStore;
  late final VideoTrimService _trimService;
  List<SavedExport> _savedExports = const [];
  final Set<String> _dismissedSuggestionIds = {};
  VideoPlayerController? _controller;
  final NativeAiPreviewService _nativeAiPreviewService =
      NativeAiPreviewService();
  NativePreviewSession? _nativePreviewSession;
  String? _loadError;
  bool _isLoading = true;
  bool _isTransitioning = false;
  bool _isPlaybackActive = false;
  bool _isTrimming = false;
  bool _isExporting = false;
  bool _isCropping = false;
  bool _backgroundApplyToAll = false;
  CropRect _draftCrop = CropRect.full;
  int? _mergeFirstIndex;
  int _selectedClipIndex = 0;
  int _controllerGeneration = 0;
  Duration _timelinePosition = Duration.zero;
  final ValueNotifier<Duration> _playbackPosition = ValueNotifier<Duration>(
    Duration.zero,
  );
  DateTime _lastPlaybackUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      _isPlaybackActive = false;
      await controller.pause();
      await _pauseNativePreview();
      if (mounted) setState(() {});
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
        _setTimelinePosition(_clipStart(_selectedClipIndex) + _trimRange.start);
      }
      _isPlaybackActive = true;
      await controller.play();
      await _playNativePreview();
      if (mounted) setState(() {});
    }
  }

  Future<void> _persistenceQueue = Future<void>.value();
  TrimRange _trimRange = const TrimRange(
    start: Duration.zero,
    end: Duration.zero,
  );

  Duration get _totalDuration =>
      _clips.fold(Duration.zero, (total, clip) => total + clip.duration);

  void _setTimelinePosition(Duration position) {
    _timelinePosition = position;
    if (_playbackPosition.value != position) {
      _playbackPosition.value = position;
    }
  }

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
    _projectStore = widget.projectStore ?? EditorProjectStore();
    _trimService = widget.trimService ?? VideoTrimService();
    _initializeFirstClip();
  }

  Future<void> _initializeFirstClip() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    VideoPlayerController? controller;
    try {
      final initialTimeline = widget.initialTimeline;
      if (initialTimeline != null) {
        await _initializeFromSharedTimeline(initialTimeline);
        return;
      }
      final savedProject = await _projectStore.load(widget.videoPath);
      if (savedProject != null) {
        _savedExports = savedProject.exports;
        final savedClips = <VideoClip>[];
        for (final savedClip in savedProject.clips) {
          if (!await _fileExists(savedClip.path)) continue;
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
                  savedRange.isValidFor(_clips[_selectedClipIndex].duration)
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
      unawaited(_refreshNativePreview());
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

  Future<void> _initializeFromSharedTimeline(
    ProjectEditorTimeline timeline,
  ) async {
    if (widget.project != null && widget.project!.id != timeline.projectId) {
      throw StateError('The selected project does not match its timeline.');
    }
    if (widget.projectClips?.any(
          (clip) => clip.projectId != timeline.projectId,
        ) ??
        false) {
      throw StateError('A source clip belongs to a different project.');
    }
    if (timeline.recoveryDiagnostic != null) {
      throw StateError(timeline.recoveryDiagnostic!);
    }
    if (timeline.unmatchedItems.isNotEmpty ||
        timeline.duplicateTimelineItemIds.isNotEmpty) {
      throw StateError(
        timeline.migrationDiagnostic ?? 'The saved timeline needs review.',
      );
    }
    if (timeline.clips.isEmpty) {
      throw StateError('This project has no editable timeline clips.');
    }

    final missing = <String>[];
    for (final clip in timeline.clips) {
      if (clip.path.trim().isEmpty || !await _fileExists(clip.path)) {
        missing.add(clip.name);
      }
    }
    if (missing.isNotEmpty) {
      throw FileSystemException(
        'Video file(s) are missing from the project: ${missing.join(', ')}.',
      );
    }

    _savedExports = timeline.exports;
    for (final savedClip in timeline.clips) {
      Uint8List? thumbnail;
      try {
        thumbnail = await _trimService.generateThumbnail(
          savedClip.path,
          time:
              savedClip.sourceStart +
              Duration(milliseconds: savedClip.duration.inMilliseconds ~/ 3),
        );
      } catch (_) {
        // Thumbnails are optional; the source timeline identity stays intact.
      }
      _clips.add(savedClip.copyWith(thumbnail: thumbnail));
    }

    _selectedClipIndex = timeline.selectedClipIndex.clamp(0, _clips.length - 1);
    final savedRange = timeline.trimRange;
    _trimRange = savedRange.isValidFor(_clips[_selectedClipIndex].duration)
        ? savedRange
        : TrimRange(
            start: Duration.zero,
            end: _clips[_selectedClipIndex].duration,
          );
    final requestedRange = _trimRange;
    await _activateClip(_selectedClipIndex, position: requestedRange.start);
    if (requestedRange.isValidFor(_clips[_selectedClipIndex].duration)) {
      setState(() => _trimRange = requestedRange);
    }
  }

  Future<_ProbedClip> _probeClip(String path, String? name) async {
    if (path.trim().isEmpty || !await _fileExists(path)) {
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

  Future<bool> _fileExists(String path) =>
      widget.fileExists?.call(path) ?? File(path).exists();

  String _friendlyError(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is FileSystemException) {
      return 'This video could not be found. Choose another recorded video.';
    }
    final description = _controller?.value.errorDescription;
    if (description != null && description.isNotEmpty) {
      return 'This video could not be played. $description';
    }
    return 'This video could not be loaded. Choose another video or try again.';
  }

  Future<void> _pickBackgroundImage() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Choose an AI background image',
        type: FileType.image,
      );
      if (!mounted || file == null) return;

      final sourcePath = file.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        _showMessage('Could not access the selected image.');
        return;
      }

      final source = File(sourcePath);
      if (!await source.exists()) {
        _showMessage('The selected image could not be found.');
        return;
      }

      final extensionIndex = sourcePath.lastIndexOf('.');
      var extension = extensionIndex >= 0
          ? sourcePath.substring(extensionIndex).toLowerCase()
          : '.img';

      if (!['.png', '.jpg', '.jpeg', '.webp', '.gif'].contains(extension)) {
        extension = '.img';
      }

      final appDirectory = await getApplicationSupportDirectory();
      final backgroundDirectory = Directory(
        '${appDirectory.path}/ai_backgrounds',
      );
      await backgroundDirectory.create(recursive: true);

      final destination = File(
        '${backgroundDirectory.path}/background_${DateTime.now().microsecondsSinceEpoch}$extension',
      );
      await source.copy(destination.path);

      if (!mounted) return;

      await _applyClipBackground(
        ClipBackground(
          type: ClipBackgroundType.image,
          imagePath: destination.path,
        ),
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Could not select the background image: $error');
      }
    }
  }

  Future<Color?> _selectBackgroundColor({
    required String title,
    required Color initialColor,
  }) {
    const colors = <Color>[
      Color(0xFF0B1020),
      Color(0xFF172554),
      Color(0xFF1D4ED8),
      Color(0xFF0891B2),
      Color(0xFF047857),
      Color(0xFF65A30D),
      Color(0xFFCA8A04),
      Color(0xFFEA580C),
      Color(0xFFDC2626),
      Color(0xFFBE185D),
      Color(0xFF9333EA),
      Color(0xFF6D28D9),
      Color(0xFF64748B),
      Color(0xFF9CA3AF),
      Color(0xFFE5E7EB),
      Color(0xFFFFFFFF),
    ];

    return showDialog<Color>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final color in colors)
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => Navigator.of(dialogContext).pop(color),
                child: CircleAvatar(
                  radius: 19,
                  backgroundColor: color,
                  child: color == initialColor
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseSolidBackground() async {
    final color = await _selectBackgroundColor(
      title: 'Choose background color',
      initialColor: const Color(0xFF172554),
    );
    if (!mounted || color == null) return;

    await _applyClipBackground(
      ClipBackground(
        type: ClipBackgroundType.solid,
        solidColor: color.toARGB32(),
      ),
    );
  }

  Future<void> _chooseGradientBackground() async {
    final start = await _selectBackgroundColor(
      title: 'Choose gradient start color',
      initialColor: const Color(0xFF2563EB),
    );
    if (!mounted || start == null) return;

    final end = await _selectBackgroundColor(
      title: 'Choose gradient end color',
      initialColor: const Color(0xFF9333EA),
    );
    if (!mounted || end == null) return;

    await _applyClipBackground(
      ClipBackground(
        type: ClipBackgroundType.gradient,
        gradientStartColor: start.toARGB32(),
        gradientEndColor: end.toARGB32(),
      ),
    );
  }

  Future<void> _choosePresetBackground() async {
    const presets = <({String id, String label, List<Color> colors})>[
      (
        id: 'studio',
        label: 'Studio',
        colors: [Color(0xFF111827), Color(0xFF374151)],
      ),
      (
        id: 'sunset',
        label: 'Sunset',
        colors: [Color(0xFF7C2D12), Color(0xFFEC4899)],
      ),
      (
        id: 'ocean',
        label: 'Ocean',
        colors: [Color(0xFF082F49), Color(0xFF0EA5E9)],
      ),
      (
        id: 'forest',
        label: 'Forest',
        colors: [Color(0xFF052E16), Color(0xFF22C55E)],
      ),
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Choose a background preset',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final preset in presets)
              ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors: preset.colors,
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                title: Text(preset.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(preset.id),
              ),
          ],
        ),
      ),
    );

    if (!mounted || selected == null) return;

    await _applyClipBackground(
      ClipBackground(type: ClipBackgroundType.preset, presetId: selected),
    );
  }

  Future<void> _applyClipBackground(ClipBackground background) async {
    if (_clips.isEmpty || _isBusy || _isCropping) return;

    final before = _captureState();
    final updated = List<VideoClip>.of(_clips);

    if (_backgroundApplyToAll) {
      for (var index = 0; index < updated.length; index++) {
        updated[index] = updated[index].copyWith(background: background);
      }
    } else {
      updated[_selectedClipIndex] = updated[_selectedClipIndex].copyWith(
        background: background,
      );
    }

    setState(() {
      _clips
        ..clear()
        ..addAll(updated);
    });

    _recordEdit(before);
    unawaited(_refreshNativePreview());
    await _persistProject();

    if (mounted) {
      _showMessage(
        background.type == ClipBackgroundType.none
            ? 'Background removed.'
            : 'Background settings applied.',
      );
    }
  }

  Widget _buildAiBackgroundStudio() {
    final current = _clips[_selectedClipIndex].background;
    final backgroundLabel = switch (current.type) {
      ClipBackgroundType.none => 'Original background',
      ClipBackgroundType.image => 'Image background',
      ClipBackgroundType.solid => 'Solid color background',
      ClipBackgroundType.gradient => 'Gradient background',
      ClipBackgroundType.preset => 'Preset: ${current.presetId ?? 'Unknown'}',
    };

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: ExpansionTile(
        key: const ValueKey('ai-background-studio'),
        leading: const Icon(Icons.auto_awesome),
        title: const Text('AI Background Studio'),
        subtitle: Text(backgroundLabel),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Choose which clips receive the background:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButton<String>(
            isExpanded: true,
            value: _backgroundApplyToAll ? 'all' : 'selected',
            items: const [
              DropdownMenuItem(value: 'selected', child: Text('Selected Clip')),
              DropdownMenuItem(value: 'all', child: Text('All Clips')),
            ],
            onChanged: _isBusy || _isCropping
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _backgroundApplyToAll = value == 'all';
                    });
                  },
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Background type',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _isBusy || _isCropping ? null : _pickBackgroundImage,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Image'),
              ),
              OutlinedButton.icon(
                onPressed: _isBusy || _isCropping
                    ? null
                    : _chooseSolidBackground,
                icon: const Icon(Icons.palette_outlined),
                label: const Text('Solid Color'),
              ),
              OutlinedButton.icon(
                onPressed: _isBusy || _isCropping
                    ? null
                    : _chooseGradientBackground,
                icon: const Icon(Icons.gradient),
                label: const Text('Gradient'),
              ),
              OutlinedButton.icon(
                onPressed: _isBusy || _isCropping
                    ? null
                    : _choosePresetBackground,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Presets'),
              ),
              OutlinedButton.icon(
                onPressed: _isBusy || _isCropping
                    ? null
                    : () => _applyClipBackground(ClipBackground.none),
                icon: const Icon(Icons.layers_clear),
                label: const Text('Remove'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Background settings are saved automatically. Export to apply them to the final video.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
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
        projectId: widget.project?.id ?? widget.videoPath,
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
    setState(() => _setTimelinePosition(_clipStart(_selectedClipIndex)));
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
        _setTimelinePosition(Duration.zero);
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
      () =>
          _setTimelinePosition(_clipStart(_selectedClipIndex) + localPosition),
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
        'Merge requires both clips to use the same rotation, crop, and background.',
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
    if (mounted && project != null) {
      setState(() => _savedExports = project.exports);
    }
  }

  List<EditorSuggestion> get _visibleSuggestions => widget.suggestions
      .where((suggestion) => !_dismissedSuggestionIds.contains(suggestion.id))
      .toList(growable: false);

  void _dismissSuggestion(EditorSuggestion suggestion) {
    setState(() => _dismissedSuggestionIds.add(suggestion.id));
    widget.onSuggestionDismissed?.call(suggestion);
  }

  // Accepts an editor suggestion and executes its associated action.
  Future<void> _acceptSuggestion(EditorSuggestion suggestion) async {
    final action = suggestion.action;
    var accepted = true;

    if (action is SeekSuggestionAction) {
      if (_isValidTimelinePosition(action.position)) {
        await _seekToTimeline(action.position);
      } else {
        _showMessage('That suggestion points outside the current timeline.');
        accepted = false;
      }
    } else if (action is SplitSuggestionAction) {
      if (_isValidTimelinePosition(action.position)) {
        await _seekToTimeline(action.position);
        if (_clips.isNotEmpty) {
          await _splitSelectedClip();
        }
      } else {
        _showMessage('That split point is outside the current timeline.');
        accepted = false;
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
        accepted = false;
      }
    } else if (action is RemovePauseSuggestionAction) {
      accepted = await _removeSuggestedPause(action);
    } else {
      accepted = false;
    }

    if (!mounted || !accepted) return;

    setState(() => _dismissedSuggestionIds.add(suggestion.id));
    widget.onSuggestionAccepted?.call(suggestion);
  }

  // Removes the detected pause while keeping the video before and after it.
  Future<bool> _removeSuggestedPause(RemovePauseSuggestionAction action) async {
    if (!action.isValid) {
      _showMessage('This pause suggestion is invalid.');
      return false;
    }

    final startMs = action.startMs;
    final endMs = action.endMs;

    // Find the timeline clip that contains the detected source-video pause.
    final clipIndex = _clips.indexWhere((clip) {
      final sourceStart = clip.sourceStart.inMilliseconds;
      final sourceEnd = clip.sourceEnd.inMilliseconds;

      return clip.sourceClipId == action.clipId &&
          sourceStart <= startMs &&
          sourceEnd >= endMs;
    });

    if (clipIndex == -1) {
      _showMessage('The original clip or pause range could not be found.');
      return false;
    }

    final clip = _clips[clipIndex];

    // Convert source-video timestamps to positions inside the timeline clip.
    final localStart = Duration(
      milliseconds: startMs - clip.sourceStart.inMilliseconds,
    );

    // Keep the final 500ms before speech starts.
    const preRollMs = 500;

    final adjustedEndMs = endMs - preRollMs;

    if (adjustedEndMs <= startMs) {
      _showMessage('This pause is too short to preserve the pre-roll.');
      return false;
    }

    final localEnd = Duration(
      milliseconds: adjustedEndMs - clip.sourceStart.inMilliseconds,
    );
    final List<VideoClip> updatedClips;

    try {
      updatedClips = TimelineOperations.removeRange(
        _clips,
        clipIndex,
        localStart,
        localEnd,
      );
    } on ArgumentError {
      _showMessage(
        'Cannot remove this pause. Both remaining video segments '
        'must be at least 0.5 seconds long.',
      );
      return false;
    }

    // Capture the previous timeline for undo support.
    final before = _captureState();

    _isPlaybackActive = false;
    await _controller?.pause();

    if (!mounted) return false;

    // Replace the original clip with the two remaining video segments.
    _clips
      ..clear()
      ..addAll(updatedClips);

    await _activateClip(clipIndex);

    if (!mounted) return false;

    // Record the edit and save the updated project.
    _recordEdit(before);
    await _persistProject();

    if (!mounted) return false;

    _showMessage('Pause removed successfully.');

    return true;
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
      _setTimelinePosition(start + _trimRange.end);
      if (mounted) setState(() {});
      return;
    }

    if (localPosition >= clip.duration && _isPlaybackActive) {
      if (!_isTransitioning) _advanceToNextClip();
      return;
    }

    if (!_isPlaybackActive) {
      _setTimelinePosition(start + localPosition);
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastPlaybackUiUpdate).inMilliseconds < 100) {
      return;
    }

    _lastPlaybackUiUpdate = now;
    _setTimelinePosition(start + localPosition);
  }

  Future<void> _advanceToNextClip() async {
    if (_isTransitioning) return;
    _isTransitioning = true;
    try {
      final nextIndex = _selectedClipIndex + 1;
      if (nextIndex >= _clips.length) {
        _isPlaybackActive = false;
        await _controller?.pause();
        if (mounted) {
          _setTimelinePosition(_totalDuration);
          setState(() {});
        }
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
      _setTimelinePosition(_clipStart(index) + position);
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
      if (sourcePosition > Duration.zero) {
        await controller.seekTo(sourcePosition);
      }
      _controller = controller;
      controller.addListener(_onVideoChanged);
      setState(() => _isLoading = false);
      unawaited(_refreshNativePreview());
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

  Future<void> _refreshNativePreview() async {
    if (_nativePreviewSession != null && mounted) {
      setState(() => _nativePreviewSession = null);
    } else {
      _nativePreviewSession = null;
    }
  }

  Future<void> _seekNativePreview(Duration position) async {
    if (!Platform.isAndroid || _nativePreviewSession == null) return;
    try {
      await _nativeAiPreviewService.seekTo(position.inMilliseconds);
    } catch (error) {
      debugPrint('Native preview seek failed: $error');
    }
  }

  Future<void> _playNativePreview() async {
    if (!Platform.isAndroid || _nativePreviewSession == null) return;
    try {
      await _nativeAiPreviewService.play();
    } catch (error) {
      debugPrint('Native preview play failed: $error');
    }
  }

  Future<void> _pauseNativePreview() async {
    if (!Platform.isAndroid || _nativePreviewSession == null) return;
    try {
      await _nativeAiPreviewService.pause();
    } catch (error) {
      debugPrint('Native preview pause failed: $error');
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
      _setTimelinePosition(_clipStart(targetIndex) + boundedPosition);
      final sourcePosition = _clips[targetIndex].sourceStart + boundedPosition;
      await _controller!.seekTo(sourcePosition);
      await _seekNativePreview(sourcePosition);
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
      _setTimelinePosition(_clipStart(_selectedClipIndex) + range.start);
    } else if (localPosition != null && localPosition > range.end) {
      _controller?.seekTo(clip.sourceStart + range.end);
      _setTimelinePosition(_clipStart(_selectedClipIndex) + range.end);
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
        background: clip.background,
      );
      final index = _selectedClipIndex;
      _clips
        ..clear()
        ..addAll(afterClips);
      setState(() => _setTimelinePosition(_clipStart(index)));
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
          _setTimelinePosition(snapshot.timelinePosition);
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
    _setTimelinePosition(clipStart + localPosition);
    if (mounted) setState(() {});
    await _persistProject();
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
    unawaited(_nativeAiPreviewService.dispose().catchError((_) {}));
    _controllerGeneration++;
    _controller?.removeListener(_onVideoChanged);
    _controller?.dispose();
    _playbackPosition.dispose();
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
    final timelineClips = List<VideoClip>.unmodifiable(_clips);

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
            // Main editor workspace scrolls independently from the fixed tool dock.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: AspectRatio(
                            aspectRatio: _previewAspectRatio(value),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: ColoredBox(
                                color: Colors.black,
                                child: _buildPreview(controller, ready),
                              ),
                            ),
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
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
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
                              onPressed: () =>
                                  _activateClip(_selectedClipIndex),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                        child: Row(
                          children: [
                            ValueListenableBuilder<Duration>(
                              valueListenable: _playbackPosition,
                              builder: (context, position, _) => Text(
                                _formatTime(position),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                            Expanded(
                              child: ValueListenableBuilder<Duration>(
                                valueListenable: _playbackPosition,
                                builder: (context, position, _) => Slider(
                                  key: const ValueKey('video-seek-bar'),
                                  min: 0,
                                  max: totalSeconds,
                                  value: (position.inMilliseconds / 1000)
                                      .clamp(0, totalSeconds)
                                      .toDouble(),
                                  onChanged:
                                      _clips.isNotEmpty &&
                                          !_isCropping &&
                                          !_isBusy
                                      ? (seconds) => _seekToTimeline(
                                          Duration(
                                            milliseconds: (seconds * 1000)
                                                .round(),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            Text(
                              _formatTime(totalDuration),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        key: const ValueKey('video-play-pause'),
                        tooltip: value?.isPlaying ?? false ? 'Pause' : 'Play',
                        onPressed: ready && !_isCropping && !_isBusy
                            ? _togglePlayback
                            : null,
                        iconSize: 30,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          value?.isPlaying ?? false
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                      ),
                    ],
                    if (_clips.isNotEmpty) ...[
                      const Divider(height: 12),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                        child: Row(
                          children: [
                            Text(
                              'Video Timeline',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            Text(
                              '${_clips.length} ${_clips.length == 1 ? 'clip' : 'clips'}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                        child: ValueListenableBuilder<Duration>(
                          valueListenable: _playbackPosition,
                          builder: (context, position, _) => VideoTimeline(
                            clips: timelineClips,
                            selectedClipIndex: _selectedClipIndex,
                            position: position,
                            trimRange: _trimRange,
                            onSeek: _isCropping || _isBusy
                                ? (_) {}
                                : _seekToTimeline,
                            onClipSelected: _isCropping || _isBusy
                                ? (_) {}
                                : _selectClip,
                            onTrimChanged: _isCropping || _isBusy
                                ? (_) {}
                                : _onTrimRangeChanged,
                            onReorder: _isCropping || _isBusy
                                ? (_, _) {}
                                : _reorderClips,
                          ),
                        ),
                      ),
                      // Background studio sits directly below the timeline.
                      _buildAiBackgroundStudio(),
                      if (_savedExports.isNotEmpty)
                        SizedBox(
                          height: 88,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _savedExports.length,
                            itemBuilder: (context, index) {
                              final saved = _savedExports[index];
                              return Card(
                                child: InkWell(
                                  onTap: () => Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) => SavedVideoPlayerScreen(
                                        path: saved.filePath,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Edited video ${index + 1}'),
                                        Text(
                                          '${saved.quality.label} - ${_formatTime(saved.duration)}',
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
            ),
            if (_clips.isNotEmpty) _buildEditorToolDock(),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorToolDock() {
    final tools = <Widget>[
      OutlinedButton.icon(
        key: const ValueKey('merge-selected-clips'),
        onPressed: _clips.length >= 2 && !_isCropping && !_isBusy
            ? _mergeAdjacentClips
            : null,
        icon: const Icon(Icons.merge_type),
        label: Text(_mergeFirstIndex == null ? 'Merge' : 'Select second clip'),
      ),
      OutlinedButton.icon(
        key: const ValueKey('rotate-selected-clip'),
        onPressed: _clips.isNotEmpty && !_isCropping && !_isBusy
            ? _rotateSelectedClip
            : null,
        icon: const Icon(Icons.rotate_right),
        label: Text(
          'Rotate ${(_clips[_selectedClipIndex].rotationDegrees + 90) % 360}°',
        ),
      ),
      if (!_isCropping)
        OutlinedButton.icon(
          key: const ValueKey('crop-selected-clip'),
          onPressed: !_isBusy ? _beginCrop : null,
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
          onPressed: () => setState(() => _isCropping = false),
          child: const Text('Cancel'),
        ),
      ],
      ValueListenableBuilder<Duration>(
        valueListenable: _playbackPosition,
        builder: (context, position, _) => OutlinedButton.icon(
          key: const ValueKey('split-selected-clip'),
          onPressed:
              !_isCropping &&
                  !_isBusy &&
                  TimelineOperations.canSplit(
                    _clips[_selectedClipIndex],
                    position - _clipStart(_selectedClipIndex),
                  )
              ? _splitSelectedClip
              : null,
          icon: const Icon(Icons.call_split),
          label: const Text('Split'),
        ),
      ),
      OutlinedButton.icon(
        key: const ValueKey('delete-selected-clip'),
        onPressed: !_isCropping && !_isBusy ? _deleteSelectedClip : null,
        icon: const Icon(Icons.delete_outline),
        label: const Text('Delete'),
      ),
      FilledButton.icon(
        key: const ValueKey('apply-video-trim'),
        onPressed:
            !_isCropping &&
                !_isBusy &&
                _trimRange.isValidFor(_clips[_selectedClipIndex].duration)
            ? _trimSelectedClip
            : null,
        icon: _isTrimming
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.content_cut),
        label: Text(_isTrimming ? 'Trimming...' : 'Trim'),
      ),
    ];

    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: tools.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => tools[index],
          ),
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
        child: Stack(fit: StackFit.expand, children: [VideoPlayer(controller)]),
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
              if (!_isCropping && widget.captions.isNotEmpty)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 12,
                  child: Center(
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: _playbackPosition,
                      builder: (context, position, _) => CaptionOverlay(
                        captions: widget.captions,
                        positionMs: position.inMilliseconds,
                      ),
                    ),
                  ),
                ),
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
    if (_clips.isEmpty || value == null || value.aspectRatio <= 0) {
      return 16 / 9;
    }
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
