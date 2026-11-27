import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as material;
import 'package:material_ui/material_ui.dart';

import '../../models/caption.dart' as m7;
import '../../models/clip.dart';
import '../../models/project.dart';
import '../../providers/repository_providers.dart';
import 'services/editor_project_store.dart';
import 'services/m5_project_library_service.dart';
import 'services/m5_video_import_service.dart';
import 'services/video_trim_service.dart';
import 'services/project_clip_adapter.dart';

import 'video_editor_screen.dart';

class VideoEditorLibraryScreen extends ConsumerStatefulWidget {
  const VideoEditorLibraryScreen({
    super.key,
    this.projectStore,
    this.trimService,
    this.projectLibrary,
    this.fileExists,
    this.videoImportService,
    this.videoPicker,
  });

  final EditorProjectStore? projectStore;
  final VideoTrimService? trimService;
  final M5ProjectLibraryService? projectLibrary;
  final Future<bool> Function(String path)? fileExists;
  final M5VideoImporter? videoImportService;
  final Future<List<file_picker.PlatformFile>> Function()? videoPicker;

  @override
  ConsumerState<VideoEditorLibraryScreen> createState() =>
      _VideoEditorLibraryScreenState();
}

class _VideoEditorLibraryScreenState
    extends ConsumerState<VideoEditorLibraryScreen> {
  late final EditorProjectStore _projectStore;
  late final M5ProjectLibraryService _projectLibrary;
  late final M5VideoImporter _videoImportService;

  late Future<List<Project>> _sharedProjects;

  List<String> _projectIds = const [];
  bool _loading = true;
  bool _importingVideo = false;
  String? _openingProjectId;

  @override
  void initState() {
    super.initState();

    _projectStore = widget.projectStore ?? EditorProjectStore();

    _projectLibrary =
        widget.projectLibrary ??
        M5ProjectLibraryService(
          projectRepository: ref.read(projectRepositoryProvider),
          projectStore: _projectStore,
        );

    _videoImportService = widget.videoImportService ?? M5VideoImportService();

    _sharedProjects = _projectLibrary.getProjects();
    _refreshProjects();
  }

  Future<void> _refreshProjects() async {
    try {
      final ids = await _projectStore.listProjectIds();

      if (!mounted) return;

      setState(() {
        _projectIds = ids;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() => _loading = false);

      _showMessage('Could not load saved editor projects: $error');
    }
  }

  void _reloadSharedProjects() {
    setState(() {
      _sharedProjects = _projectLibrary.getProjects();
    });
  }

  Future<List<file_picker.PlatformFile>> _pickVideos() async {
    if (widget.videoPicker != null) {
      return widget.videoPicker!.call();
    }

    // file_picker 13.x returns List<PlatformFile> directly.
    // Multiple selection is enabled by default.
    return file_picker.FilePicker.pickFiles(type: file_picker.FileType.video);
  }

  /// Imports multiple videos into one project.
  Future<void> _openVideo() async {
    if (_importingVideo) return;

    setState(() => _importingVideo = true);

    var refreshProjectLists = false;
    Project? importedProject;

    try {
      final files = await _pickVideos();

      if (!mounted || files.isEmpty) return;

      final selectedVideos = <XFile>[];

      for (final file in files) {
        final path = file.path;

        if (path == null || path.trim().isEmpty) {
          _showMessage(
            'One selected video has no accessible file path. '
            'Choose videos stored on this device.',
          );
          return;
        }

        if (!await _fileExists(path)) {
          _showMessage('One selected video cannot be accessed: ${file.name}');
          return;
        }

        selectedVideos.add(XFile(path, name: file.name));
      }

      if (!mounted) return;

      final title = await _requestImportTitle(
        selectedVideos.length == 1
            ? files.first.name
            : '${files.first.name} + ${files.length - 1} videos',
      );

      if (!mounted || title == null) return;

      refreshProjectLists = true;

      importedProject = await _videoImportService.importVideos(
        videos: selectedVideos,
        title: title,
      );

      if (!mounted) return;

      final selection = await _projectLibrary.selectProject(importedProject);

      if (!mounted) return;

      if (!selection.canOpen) {
        _showMessage(
          '“${importedProject.title}” was imported, '
          'but its clips could not be opened. '
          'The project remains in your library. '
          '${selection.errorMessage ?? ''}',
        );
        return;
      }

      await _refreshProjectLists();

      if (!mounted) return;

      await _openProject(
        importedProject.id,
        importedProject.title,
        project: importedProject,
        projectClips: selection.sourceClips,
        initialTimeline: selection.timeline!,
      );
    } catch (error) {
      if (mounted) {
        if (importedProject != null) {
          _showMessage(
            '“${importedProject.title}” was imported, '
            'but its clips could not be loaded. '
            'The project remains in your library. $error',
          );
        } else {
          _showMessage('Could not import the selected videos: $error');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _importingVideo = false);

        if (refreshProjectLists) {
          await _refreshProjectLists();
        }
      }
    }
  }

  Future<String?> _requestImportTitle(String fileName) async {
    final controller = TextEditingController(text: _defaultTitle(fileName));

    String? title;

    try {
      title = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, updateDialog) => AlertDialog(
            title: const Text('Save Video Project'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Project Title',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => updateDialog(() {}),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: controller.text.trim().isEmpty
                    ? null
                    : () {
                        Navigator.of(dialogContext).pop(controller.text.trim());
                      },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }

    return title?.trim();
  }

  String _defaultTitle(String fileName) {
    final baseName = fileName.replaceAll('\\', '/').split('/').last;

    final extensionStart = baseName.lastIndexOf('.');

    final title = extensionStart > 0
        ? baseName.substring(0, extensionStart)
        : baseName;

    return title.trim().isEmpty ? 'Imported Video' : title;
  }

  Future<void> _refreshProjectLists() async {
    await _refreshProjects();

    if (mounted) {
      _reloadSharedProjects();
    }
  }

  Future<bool> _fileExists(String path) {
    return widget.fileExists?.call(path) ?? File(path).exists();
  }

  Future<void> _openSavedProject(String projectId) async {
    try {
      final project = await _projectStore.load(projectId);

      if (!mounted) return;

      if (project == null || project.clips.isEmpty) {
        _showMessage('This project has no editable video.');
        await _refreshProjects();
        return;
      }

      await _openProject(
        projectId,
        projectId.replaceAll('\\', '/').split('/').last,
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Could not read this saved editor project: $error');
      }
    }
  }

  Future<void> _openSharedProject(Project project) async {
    if (_openingProjectId != null) return;

    setState(() => _openingProjectId = project.id);

    try {
      final selection = await _projectLibrary.selectProject(project);

      if (!mounted) return;

      if (!selection.canOpen) {
        _showMessage(selection.errorMessage ?? 'Could not open this project.');
        return;
      }

      await _openProject(
        project.id,
        project.title,
        project: project,
        projectClips: selection.sourceClips,
        initialTimeline: selection.timeline!,
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Could not load project ${project.title}: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _openingProjectId = null);
      }
    }
  }

  Future<void> _openProject(
    String path,
    String name, {
    Project? project,
    List<Clip>? projectClips,
    ProjectEditorTimeline? initialTimeline,
  }) async {
    var captions = const <m7.Caption>[];

    if (project != null) {
      try {
        captions = await ref
            .read(captionRepositoryProvider)
            .getCaptions(project.id);
      } catch (_) {
        // The editor can still open without captions.
      }
    }

    if (!mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VideoEditorScreen(
          videoPath: path,
          videoName: name,
          project: project,
          projectClips: projectClips,
          initialTimeline: initialTimeline,
          projectStore: _projectStore,
          trimService: widget.trimService,
          fileExists: widget.fileExists,
          captions: captions,
        ),
      ),
    );

    if (mounted) {
      await _refreshProjectLists();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _sectionHeading(
    BuildContext context, {
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _emptyProjects(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: scheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildSharedProjects() => FutureBuilder<List<Project>>(
    future: _sharedProjects,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
      }

      if (snapshot.hasError) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Could not load app projects. Please try again.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: 'Retry loading projects',
                onPressed: _reloadSharedProjects,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        );
      }

      final projects = snapshot.data ?? const <Project>[];

      if (projects.isEmpty) {
        return _emptyProjects(
          context,
          icon: Icons.folder_open_rounded,
          title: 'No app projects yet',
          message: 'Projects created in PitchCut will appear here.',
        );
      }

      return Column(
        children: [
          for (final project in projects) ...[
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: material.Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.folder_copy_rounded,
                    color: Colors.blue,
                  ),
                ),
                title: Text(
                  project.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('${project.clipIds.length} source clip(s)'),
                trailing: _openingProjectId == project.id
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right_rounded),
                enabled: _openingProjectId == null,
                onTap: () => _openSharedProject(project),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Video Editor',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh projects',
            onPressed: _refreshProjectLists,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Text(
              'Make every second count.',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a video to start editing or continue where you left off.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 22),

            // Main import action, styled to match the PitchCut home screen.
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF5B45C6), Color(0xFF342477)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF5B45C6).withValues(alpha: 0.20),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.video_library_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Start a new edit',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Import a video and trim, arrange, and improve your clips.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF4935A5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _importingVideo ? null : _openVideo,
                      icon: _importingVideo
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded),
                      label: Text(
                        _importingVideo ? 'Importing videos…' : 'Import Videos',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            _sectionHeading(
              context,
              title: 'Saved editor projects',
              subtitle: 'Your saved editor timelines',
              trailing: IconButton(
                tooltip: 'Refresh saved projects',
                onPressed: _refreshProjects,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_projectIds.isEmpty)
              _emptyProjects(
                context,
                icon: Icons.video_library_outlined,
                title: 'Nothing to continue yet',
                message: 'Videos you start editing will be saved here.',
              )
            else
              for (final projectId in _projectIds) ...[
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: material.Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.video_file_rounded,
                        color: Colors.deepPurple,
                      ),
                    ),
                    title: Text(
                      projectId.replaceAll('\\', '/').split('/').last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('Tap to continue editing'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openSavedProject(projectId),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 26),
            _sectionHeading(
              context,
              title: 'My projects',
              subtitle: 'Projects created in PitchCut',
            ),
            const SizedBox(height: 14),
            _buildSharedProjects(),
          ],
        ),
      ),
    );
  }
}
