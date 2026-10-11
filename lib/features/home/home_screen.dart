import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/placeholder_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
    title: 'Home',
    owner: 'M1',
    children: [
      FilledButton(
        onPressed: () => context.push('/editor'),
        child: const Text('Open Editor'),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () => context.push('/analysis'),
        child: const Text('Open Analysis'),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () => context.push('/captions'),
        child: const Text('Open Captions'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () => context.push('/login'),
        child: const Text('Open Login'),
      ),
    ],
  );
}
