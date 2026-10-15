import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/analysis/analysis_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/capture/capture_screen.dart';
import '../../features/captions/captions_screen.dart';
import '../../features/dev/widget_gallery_screen.dart';
import '../../features/editor/editor_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/profile/profile_screen.dart';
import 'app_shell.dart';

/// Refreshes GoRouter whenever Firebase authentication changes.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final appRouter = GoRouter(
  initialLocation: '/home',

  // Listen for login and logout changes.
  refreshListenable: GoRouterRefreshStream(
    FirebaseAuth.instance.authStateChanges(),
  ),

  // Protect routes according to authentication status.
  redirect: (context, state) {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    final location = state.matchedLocation;

    final isLoginPage = location == '/login';
    final isSignupPage = location == '/signup';
    final isAuthPage = isLoginPage || isSignupPage;

    if (!isLoggedIn && !isAuthPage) {
      return '/login';
    }

    if (isLoggedIn && isAuthPage) {
      return '/home';
    }

    return null;
  },

  routes: [
    // Authentication
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),

    // Editor
    GoRoute(path: '/editor', builder: (context, state) => const EditorScreen()),

    // Analysis
    GoRoute(
      path: '/analysis',
      builder: (context, state) => const AnalysisScreen(),
    ),

    // Captions
    GoRoute(
      path: '/captions',
      builder: (context, state) => const CaptionsScreen(),
    ),

    // Main app navigation
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppShell(navigationShell: navigationShell);
      },
      branches: [
        // Home
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),

        // Record
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/record',
              builder: (context, state) => const CaptureScreen(),
            ),
          ],
        ),

        // History
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/history',
              builder: (context, state) => const HistoryScreen(),
            ),
          ],
        ),

        // Profile
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),

        // Widget gallery
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/gallery',
              builder: (context, state) => const WidgetGalleryScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
