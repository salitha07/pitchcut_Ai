import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/project.dart';
import '../../providers/repository_providers.dart';
import '../../shared/widgets/widgets.dart';
import 'widgets/feature_carousel.dart';
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

  /// Slides for the feature slideshow at the top of the home screen.
  ///
  /// Put the matching pictures in assets/images/features/. Until a picture
  /// exists, its slide shows a gradient with the icon instead.
  List<FeatureSlide> _featureSlides(BuildContext context) {
    return [
      FeatureSlide(
        title: 'Record or import',
        description:
            'Film your presentation in the app or bring in a video you '
            'already have.',
        icon: Icons.videocam_rounded,
        imageAsset: 'assets/images/features/record.jpg',
        onTap: () => context.push('/record'),
      ),
      FeatureSlide(
        title: 'Edit your video',
        description:
            'Trim, cut, merge, crop and rotate clips on a simple timeline.',
        icon: Icons.content_cut_rounded,
        imageAsset: 'assets/images/features/edit.jpg',
        onTap: () => context.push('/video-editor'),
      ),
      FeatureSlide(
        title: 'Find long pauses',
        description:
            'See where you paused for too long and cut those parts out.',
        icon: Icons.graphic_eq_rounded,
        imageAsset: 'assets/images/features/pauses.jpg',
        onTap: () => context.push('/analysis'),
      ),
      FeatureSlide(
        title: 'Check your framing',
        description:
            'See how well your face sits in the frame and how steady your '
            'camera was.',
        icon: Icons.center_focus_strong_rounded,
        imageAsset: 'assets/images/features/framing.jpg',
        onTap: () => context.push('/analysis'),
      ),
      FeatureSlide(
        title: 'Add captions',
        description:
            'Generate captions automatically, then fix the words and timing.',
        icon: Icons.closed_caption_rounded,
        imageAsset: 'assets/images/features/captions.jpg',
        onTap: () => context.push('/captions'),
      ),
      FeatureSlide(
        title: 'Track your score',
        description: 'See your presentation score and watch it improve.',
        icon: Icons.trending_up_rounded,
        imageAsset: 'assets/images/features/progress.jpg',
        onTap: () => context.go('/history'),
      ),
    ];
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

            // Feature slideshow
            FeatureCarousel(slides: _featureSlides(context)),
            const SizedBox(height: 20),

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
          ],
        ),
      ),
    );
  }
}
