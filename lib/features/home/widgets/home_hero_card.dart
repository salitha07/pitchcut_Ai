import 'package:flutter/material.dart';

class HomeHeroCard extends StatelessWidget {
  const HomeHeroCard({super.key, required this.onRecord});

  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.tertiary, 0.5)!,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.onPrimary.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome_rounded, color: scheme.onPrimary),
          ),
          const SizedBox(height: 16),
          Text(
            'Ready for your next pitch?',
            style: text.titleLarge?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Record a short video and get feedback on pauses, framing and steadiness.',
            style: text.bodyMedium?.copyWith(
              color: scheme.onPrimary.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRecord,
            icon: const Icon(Icons.videocam_rounded),
            label: const Text('Record a video'),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.onPrimary,
              foregroundColor: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
