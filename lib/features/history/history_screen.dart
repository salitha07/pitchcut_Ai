import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/project.dart';
import 'providers/history_providers.dart';
import 'project_history_screen.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(historyProjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
      ),
      body: projectsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load projects: $error'),
          ),
        ),
        data: (projectList) {
          if (projectList.isEmpty) {
            return const Center(
              child: Text('No project history yet.'),
            );
          }

          final projects = projectList.toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Your Projects',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ...projects.map(
                (project) => _HistoryProjectCard(
                  project: project,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryProjectCard extends ConsumerWidget {
  const _HistoryProjectCard({
    required this.project,
  });

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(
      projectReportsProvider(project.id),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: reportsAsync.when(
        loading: () => ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.history),
          ),
          title: Text(project.title),
          subtitle: const Text('Loading reports...'),
        ),
        error: (error, stack) => ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.history),
          ),
          title: Text(project.title),
          subtitle: const Text('Could not load reports'),
        ),
        data: (reports) => ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.history),
          ),
          title: Text(project.title),
          subtitle: Text(
            reports.isEmpty
                ? 'No performance reports yet'
                : '${reports.length} reports • '
                    'Latest score: ${reports.first.score}/100',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProjectHistoryScreen(
                  project: project,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}