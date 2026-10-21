import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/project.dart';
import '../../providers/repository_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsStream = ref.watch(projectRepositoryProvider).watchProjects();

    return Scaffold(
      appBar: AppBar(
        title: const Text('PitchCut AI'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () => context.go('/profile'),
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Welcome back! 👋',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Manage your video projects in one place.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: () => context.push('/record'),
              icon: const Icon(Icons.videocam_outlined),
              label: const Text('Record a Video'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/gallery'),
              icon: const Icon(Icons.widgets_outlined),
              label: const Text('Widget Gallery'),
            ),

            const SizedBox(height: 28),
            Text('My Projects', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),

            StreamBuilder<List<Project>>(
              stream: projectsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Could not load projects. Please try again.'),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final projects = snapshot.data ?? [];

                if (projects.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(Icons.video_library_outlined, size: 44),
                          SizedBox(height: 12),
                          Text(
                            'No projects yet',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Your saved projects will appear here.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: projects.map((project) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.movie_outlined),
                        ),
                        title: Text(project.title),
                        subtitle: Text('${project.clipIds.length} clips'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Project details screen is not connected yet.',
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => context.push('/analysis'),
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Open Analysis'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.push('/captions'),
              icon: const Icon(Icons.subtitles_outlined),
              label: const Text('Open Captions'),
            ),
          ],
        ),
      ),
    );
  }
}
