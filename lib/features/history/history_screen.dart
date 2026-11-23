import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/project.dart';
import 'project_history_screen.dart';
import 'providers/history_providers.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  String _date(String iso) => iso.length >= 10 ? iso.substring(0, 10) : iso;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: projects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No projects yet.'));
          }

          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _ProjectRow(project: list[index], date: _date),
          );
        },
      ),
    );
  }
}

class _ProjectRow extends ConsumerWidget {
  const _ProjectRow({required this.project, required this.date});

  final Project project;
  final String Function(String) date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(reportsProvider(project.id));

    final trailing = reports.when(
      loading: () => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => const Text('-'),
      data: (list) => list.isEmpty
          ? const Text('No score')
          : Text(
              '${list.first.score}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
    );

    return ListTile(
      title: Text(project.title),
      subtitle: Text('Updated ${date(project.updatedAt)}'),
      trailing: trailing,
      leading: const Icon(Icons.folder_outlined),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProjectHistoryScreen(project: project),
          ),
        );
      },
    );
  }
}
