import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/caption.dart';
import '../../providers/repository_providers.dart';
import 'providers/caption_providers.dart';
import 'ui/caption_edit_dialog.dart';

class CaptionsScreen extends ConsumerWidget {
  const CaptionsScreen({super.key, this.projectId});

  final String? projectId;

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = projectId;

    return Scaffold(
      appBar: AppBar(title: const Text('Captions')),
      floatingActionButton: id == null
          ? null
          : FloatingActionButton(
              onPressed: () => _addOrEdit(context, ref, id),
              child: const Icon(Icons.add),
            ),
      body: id == null
          ? const Center(child: Text('No project selected.'))
          : ref
                .watch(captionsProvider(id))
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(child: Text('Error: $error')),
                  data: (captions) {
                    if (captions.isEmpty) {
                      return const Center(
                        child: Text('No captions yet. Tap + to add one.'),
                      );
                    }
                    return ListView.separated(
                      itemCount: captions.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final c = captions[index];
                        return Dismissible(
                          key: ValueKey(c.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Theme.of(context).colorScheme.error,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) => ref
                              .read(captionRepositoryProvider)
                              .deleteCaption(id, c.id),
                          child: ListTile(
                            title: Text(c.text),
                            subtitle: Text(
                              '${_formatMs(c.startMs)} - ${_formatMs(c.endMs)}',
                            ),
                            onTap: () =>
                                _addOrEdit(context, ref, id, existing: c),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}