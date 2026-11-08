import 'package:flutter/material.dart';

import '../../shared/widgets/widgets.dart';

class WidgetGalleryScreen extends StatelessWidget {
  const WidgetGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Widget gallery')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Section('AppButton'),
        AppButton(label: 'Primary', icon: Icons.videocam, onPressed: () {}),
        const SizedBox(height: 8),
        AppButton(label: 'Secondary', isSecondary: true, onPressed: () {}),
        const SizedBox(height: 8),
        AppButton(label: 'Loading', isLoading: true, onPressed: () {}),
        const SizedBox(height: 8),
        const AppButton(label: 'Disabled', onPressed: null),

        const _Section('AppCard'),
        AppCard(
          title: 'My pitch video',
          subtitle: 'Score: 82 - 12 Oct 2026',
          leading: const Icon(Icons.movie),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {},
        ),

        const _Section('LoadingView'),
        const SizedBox(
          height: 140,
          child: LoadingView(message: 'Analysing video...'),
        ),

        const _Section('ErrorView'),
        SizedBox(
          height: 200,
          child: ErrorView(message: 'Could not load projects', onRetry: () {}),
        ),

        const _Section('EmptyState'),
        const SizedBox(
          height: 200,
          child: EmptyState(
            title: 'No projects yet',
            message: 'Record your first video to get started',
            icon: Icons.videocam_off_outlined,
          ),
        ),

        const _Section('ConfirmDialog'),
        AppButton(
          label: 'Show dialog',
          isSecondary: true,
          onPressed: () async {
            final ok = await ConfirmDialog.show(
              context,
              title: 'Delete project?',
              message: 'This cannot be undone.',
              confirmLabel: 'Delete',
            );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ok ? 'Confirmed' : 'Cancelled')),
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
}
