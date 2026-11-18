import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/caption_providers.dart';

class CaptionsScreen extends ConsumerWidget {
  const CaptionsScreen({super.key, this.projectId});

  final String? projectId;

  String _formatMs(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = projectId;

    return Scaffold(
      appBar: AppBar(title: const Text('Captions')),
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
                      return const Center(child: Text('No captions yet.'));
                    }
                    return ListView.separated(
                      itemCount: captions.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final c = captions[index];
                        return ListTile(
                          title: Text(c.text),
                          subtitle: Text(
                            '${_formatMs(c.startMs)} - ${_formatMs(c.endMs)}',
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
