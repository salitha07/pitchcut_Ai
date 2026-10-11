import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/placeholder_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
    title: 'Login',
    owner: 'M2',
    children: [
      FilledButton(
        onPressed: () => context.go('/home'),
        child: const Text('Go to Home (temporary)'),
      ),
    ],
  );
}
