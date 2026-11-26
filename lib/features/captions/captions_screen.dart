import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/caption.dart';
import '../../models/project.dart';
import '../../providers/repository_providers.dart';
import '../editor/services/editor_project_store.dart';
import '../editor/services/m5_project_library_service.dart';
import 'providers/caption_providers.dart';
import 'services/auto_caption_service.dart';
import 'ui/caption_edit_dialog.dart';

class CaptionsScreen extends ConsumerStatefulWidget {
  const CaptionsScreen({super.key, this.projectId});

  final String? projectId;

  @override
  ConsumerState<CaptionsScreen> createState() => _CaptionsScreenState();
}

class _CaptionsScreenState extends ConsumerState<CaptionsScreen> {
  bool _isGenerating = false;
  int _progress = 0;
  String _status = '';

  String _formatMs(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _addOrEdit(
    BuildContext context,
    WidgetRef ref,
    String id, {
    Caption? existing,
  }) async {
    final result = await showCaptionEditDialog(context, existing: existing);
    if (result == null) return;

    try {
      await ref.read(captionRepositoryProvider).saveCaption(id, result);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  Future<void> _generateAutoCaptions() async {
    final id = widget.projectId;
    if (id == null || _isGenerating) return;

    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Automatic captions are currently supported on Android only.'),
        ),
      );
      return;
    }

    final captionRepository = ref.read(captionRepositoryProvider);

    setState(() {
      _isGenerating = true;
      _progress = 0;
      _status = 'Checking existing captions...';
    });

    try {
      final existingCaptions = await captionRepository.getCaptions(id);

      if (existingCaptions.isNotEmpty) {
        if (!mounted) return;

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Replace existing captions?'),
            content: Text(
              'This project already has ${existingCaptions.length} caption(s). '
              'Generate new captions and replace the existing ones?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;
      }

      setState(() {
        _status = 'Loading project timeline...';
      });

      final projectRepository = ref.read(projectRepositoryProvider);
      final projects = await projectRepository.getProjects();

      Project? project;
      for (final candidate in projects) {
        if (candidate.id == id) {
          project = candidate;
          break;
        }
      }

      if (project == null) {
        throw StateError('The selected project could not be found.');
      }

      final libraryService = M5ProjectLibraryService(
        projectRepository: projectRepository,
        projectStore: EditorProjectStore(),
      );

      final selection = await libraryService.selectProject(project);

      if (!selection.canOpen || selection.timeline == null) {
        throw StateError(
          selection.errorMessage ?? 'Could not load the edited timeline.',
        );
      }

      final generatedCaptions = await AutoCaptionService().generateCaptions(
        sourceClips: selection.sourceClips,
        timelineClips: selection.timeline!.clips,
        onStatus: (message) {
          if (mounted) {
            setState(() => _status = message);
          }
        },
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
      );

      if (generatedCaptions.isEmpty) {
        throw StateError('No captions were generated.');
      }

      if (!mounted) return;

      setState(() {
        _status = 'Saving ${generatedCaptions.length} captions...';
      });

      // Save the new captions first. Existing captions are only deleted
      // after the new captions have been saved successfully.
      await captionRepository.saveCaptions(id, generatedCaptions);

      for (final oldCaption in existingCaptions) {
        await captionRepository.deleteCaption(id, oldCaption.id);
      }

      if (!mounted) return;

      setState(() {
        _progress = 100;
        _status = 'Captions generated successfully.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Generated ${generatedCaptions.length} captions successfully.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auto-caption generation failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.projectId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Captions'),
        actions: [
          if (id != null)
            IconButton(
              tooltip: 'Generate auto-captions',
              onPressed: _isGenerating ? null : _generateAutoCaptions,
              icon: const Icon(Icons.auto_awesome),
            ),
        ],
      ),
      floatingActionButton: id == null
          ? null
          : FloatingActionButton(
              onPressed: _isGenerating
                  ? null
                  : () => _addOrEdit(context, ref, id),
              child: const Icon(Icons.add),
            ),
      body: id == null
          ? const Center(child: Text('No project selected.'))
          : Column(
              children: [
                if (_isGenerating)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_status),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _progress / 100,
                        ),
                        const SizedBox(height: 4),
                        Text('$_progress%'),
                      ],
                    ),
                  ),
                Expanded(
                  child: ref.watch(captionsProvider(id)).when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) =>
                        Center(child: Text('Error: $error')),
                    data: (captions) {
                      if (captions.isEmpty) {
                        return const Center(
                          child: Text(
                            'No captions yet. Tap + to add one or '
                            'use the auto-captions button.',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: captions.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final caption = captions[index];

                          return Dismissible(
                            key: ValueKey(caption.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Theme.of(context).colorScheme.error,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                            onDismissed: (_) => ref
                                .read(captionRepositoryProvider)
                                .deleteCaption(id, caption.id),
                            child: ListTile(
                              title: Text(caption.text),
                              subtitle: Text(
                                '${_formatMs(caption.startMs)} - '
                                '${_formatMs(caption.endMs)}',
                              ),
                              onTap: () => _addOrEdit(
                                context,
                                ref,
                                id,
                                existing: caption,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}



