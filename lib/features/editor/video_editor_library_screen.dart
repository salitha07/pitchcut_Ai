import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'services/editor_project_store.dart';
import 'video_editor_screen.dart';

class VideoEditorLibraryScreen extends StatefulWidget {
  const VideoEditorLibraryScreen({super.key});

  @override
  State<VideoEditorLibraryScreen> createState() =>
      _VideoEditorLibraryScreenState();
}

class _VideoEditorLibraryScreenState extends State<VideoEditorLibraryScreen> {
  final EditorProjectStore _projectStore = EditorProjectStore();
  List<String> _projectIds = const [];
  bool _loading = true;
  bool _pickingVideo = false;

  @override
  void initState() {
    super.initState();
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

  Future<void> _openVideo() async {
    if (_pickingVideo) return;
    setState(() => _pickingVideo = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.video,
      );
      if (!mounted || files.isEmpty) return;
      final file = files.first;
      final path = file.path;
      if (path == null || path.isEmpty) {
        _showMessage('Could not access the selected video.');
        return;
      }
      await _openProject(path, file.name);
    } catch (error) {
      if (mounted) _showMessage('Could not open the video picker: $error');
    } finally {
      if (mounted) setState(() => _pickingVideo = false);
    }
  }

  Future<void> _openSavedProject(String projectId) async {
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
  }

  Future<void> _openProject(String path, String name) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VideoEditorScreen(videoPath: path, videoName: name),
      ),
    );
    if (mounted) await _refreshProjects();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Video Editor')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        FilledButton.icon(
          onPressed: _pickingVideo ? null : _openVideo,
          icon: const Icon(Icons.video_library_outlined),
          label: Text(_pickingVideo ? 'Opening picker…' : 'Open a video'),
        ),
        const SizedBox(height: 24),
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
