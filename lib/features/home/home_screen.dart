import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/project.dart';
import '../../providers/repository_providers.dart';
import '../../shared/widgets/widgets.dart';
import 'widgets/home_hero_card.dart';
import 'widgets/quick_action_tile.dart';

/// Streams the signed-in user's projects once and keeps the subscription.
final homeProjectsProvider = StreamProvider.autoDispose<List<Project>>((ref) {
  return ref.watch(projectRepositoryProvider).watchProjects();
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final projects = ref.watch(homeProjectsProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greeting(),
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ready to practise?',
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Profile',
                  onPressed: () => context.go('/profile'),
                  icon: const Icon(Icons.person_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Main action
            HomeHeroCard(onRecord: () => context.push('/record')),
            const SizedBox(height: 16),

            // Quick actions
            Row(
              children: [
                Expanded(
                  child: QuickActionTile(
                    icon: Icons.video_library_rounded,
                    label: 'Editor',
                    onTap: () => context.push('/video-editor'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuickActionTile(
                    icon: Icons.insights_rounded,
                    label: 'Analysis',
                    onTap: () => context.push('/analysis'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuickActionTile(
                    icon: Icons.closed_caption_rounded,
                    label: 'Captions',
                    onTap: () => context.push('/captions'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Projects
            SectionHeader(
              title: 'My projects',
              actionLabel: 'See all',
              onAction: () => context.go('/history'),
            ),
            const SizedBox(height: 8),

            projects.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: LoadingView(message: 'Loading your projects...'),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: ErrorView(
                  message: 'Could not load projects. Please try again.',
                  onRetry: () => ref.invalidate(homeProjectsProvider),
                ),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: EmptyState(
                      title: 'No projects yet',
                      message:
                          'Record your first video and it will appear here.',
                      icon: Icons.video_library_outlined,
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final project in list) ...[
                      ProjectTile(
                        title: project.title,
                        subtitle: project.clipIds.length == 1
                            ? '1 clip'
                            : '${project.clipIds.length} clips',
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
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),

            // Developer tools: visible only in debug builds
            if (kDebugMode) ...[
              const SizedBox(height: 20),
              ExpansionTile(
                title: const Text('Developer tools'),
                leading: const Icon(Icons.build_rounded),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  ListTile(
                    title: const Text('Widget gallery'),
                    onTap: () => context.push('/gallery'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
