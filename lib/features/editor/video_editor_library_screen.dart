import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/clip.dart';
import '../../models/project.dart';
import '../../providers/repository_providers.dart';
import 'services/editor_project_store.dart';
import 'services/m5_project_library_service.dart';
import 'services/m5_video_import_service.dart';
import 'services/project_clip_adapter.dart';
import 'services/video_trim_service.dart';
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
  final Future<List<PlatformFile>> Function()? videoPicker;

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

  Future<void> _openVideo() async {
    if (_importingVideo) return;
    setState(() => _importingVideo = true);
    var refreshProjectLists = false;
    Project? importedProject;
    try {
      final files =
          await (widget.videoPicker?.call() ??
              FilePicker.pickFiles(type: FileType.video));
      if (!mounted || files.isEmpty) return;
      final file = files.first;
      final path = file.path;
      if (path == null || path.isEmpty) {
        _showMessage(
          'The selected video has no accessible file path. Choose a video stored on this device.',
        );
        return;
      }
      if (!await _fileExists(path)) {
        _showMessage(
          'The selected video cannot be accessed. Choose another video and try again.',
        );
        return;
      }
      if (!mounted) return;

      final title = await _requestImportTitle(file.name);
      if (!mounted || title == null) return;

      refreshProjectLists = true;
      importedProject = await _videoImportService.importVideo(
        video: XFile(path, name: file.name),
        title: title,
      );
      if (!mounted) return;
      final selection = await _projectLibrary.selectProject(importedProject);
      if (!mounted) return;
      if (!selection.canOpen) {
        _showMessage(
          '“${importedProject.title}” was imported, but its clips could not be opened. '
          'The project remains in your library. ${selection.errorMessage ?? ''}',
        );
        return;
      }

      await _refreshProjectLists();
      if (!mounted) return;
      final timeline = selection.timeline!;
      await _openProject(
        importedProject.id,
        importedProject.title,
        project: importedProject,
        projectClips: selection.sourceClips,
        initialTimeline: timeline,
      );
    } catch (error) {
      if (mounted) {
        if (importedProject != null) {
          _showMessage(
            '“${importedProject.title}” was imported, but its clips could not be loaded. '
            'The project remains in your library. $error',
          );
        } else if (error.toString().contains(
          'Unable to complete Firebase project saving',
        )) {
          _showMessage(
            'Firebase did not confirm the import. The video or project may already be saved. '
            'No retry was made; refresh the library before trying again. $error',
          );
        } else {
          _showMessage('Could not import the selected video: $error');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _importingVideo = false);
        if (refreshProjectLists) await _refreshProjectLists();
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
            title: const Text('Save Imported Video'),
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
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: controller.text.trim().isEmpty
                    ? null
                    : () =>
                          Navigator.of(dialogContext)
                              .pop(controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
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
    if (mounted) _reloadSharedProjects();
  }

  Future<bool> _fileExists(String path) =>
      widget.fileExists?.call(path) ?? File(path).exists();

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
      final timeline = selection.timeline!;
      await _openProject(
        project.id,
        project.title,
        project: project,
        projectClips: selection.sourceClips,
        initialTimeline: timeline,
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Could not load project ${project.title}: $error');
      }
    } finally {
      if (mounted) setState(() => _openingProjectId = null);
    }
  }

  Future<void> _openProject(
    String path,
    String name, {
    Project? project,
    List<Clip>? projectClips,
    ProjectEditorTimeline? initialTimeline,
  }) async {
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

  Widget _buildSharedProjects() => FutureBuilder<List<Project>>(
    future: _sharedProjects,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (snapshot.hasError) {
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Could not load M2 projects'),
          subtitle: Text('${snapshot.error}'),
          trailing: IconButton(
            tooltip: 'Retry loading projects',
            onPressed: _reloadSharedProjects,
            icon: const Icon(Icons.refresh),
          ),
        );
      }
      final projects = snapshot.data ?? const <Project>[];
      if (projects.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Projects saved by the app will appear here.'),
        );
      }
      return Column(
        children: [
          for (final project in projects)
            Card(
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(project.title),
                subtitle: Text('${project.clipIds.length} source clip(s)'),
                trailing: _openingProjectId == project.id
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                enabled: _openingProjectId == null,
                onTap: () => _openSharedProject(project),
              ),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Video Editor')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        FilledButton.icon(
          onPressed: _importingVideo ? null : _openVideo,
          icon: const Icon(Icons.video_library_outlined),
          label: Text(_importingVideo ? 'Importing video…' : 'Open a video'),
        ),
        const SizedBox(height: 24),
        Text('M2 Projects', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _buildSharedProjects(),
        const SizedBox(height: 20),
        Text(
          'Saved editor projects',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_projectIds.isEmpty)
          const Text('Projects you edit will appear here.')
        else
          for (final projectId in _projectIds)
            Card(
              child: ListTile(
                leading: const Icon(Icons.video_file_outlined),
                title: Text(projectId.replaceAll('\\', '/').split('/').last),
                subtitle: const Text('Tap to continue editing'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openSavedProject(projectId),
              ),
            ),
      ],
    ),
  );
}
