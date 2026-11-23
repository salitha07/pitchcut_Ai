
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
import '../../features/editor/debug/engine_debug_screen.dart';
import '../../features/editor/video_editor_library_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/splash/splash_screen.dart';
import 'app_shell.dart';

/// Refreshes GoRouter whenever Firebase authentication changes.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen((_) {
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
  // Always start the app from Splash Screen.
  initialLocation: '/splash',

  // Listen for Firebase authentication changes.
  refreshListenable: GoRouterRefreshStream(
    FirebaseAuth.instance.authStateChanges(),
  ),

  // Authentication and navigation logic.
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;

    final location = state.matchedLocation;

    final isSplashPage = location == '/splash';
    final isLoginPage = location == '/login';
    final isSignupPage = location == '/signup';

    final isAuthPage = isLoginPage || isSignupPage;

    // 1. Always allow Splash Screen first.
    if (isSplashPage) {
      return null;
    }

    // 2. If user is not logged in,
    // redirect protected pages to Login.
    if (!isLoggedIn && !isAuthPage) {
      return '/login';
    }

    // 3. If user is already logged in,
    // prevent Login and Signup pages.
    if (isLoggedIn && isAuthPage) {
      return '/home';
    }

    // 4. No redirect needed.
    return null;
  },

  routes: [
    // -------------------------------------
    // SPLASH SCREEN
    // -------------------------------------
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),

    // -------------------------------------
    // DEBUG SCREEN
    // -------------------------------------
    if (kDebugMode)
      GoRoute(
        path: '/engine-debug',
        builder: (context, state) => const EngineDebugScreen(),
      ),

    // -------------------------------------
    // AUTHENTICATION
    // -------------------------------------
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),

    GoRoute(
      path: '/signup',
      builder: (context, state) => const SignupScreen(),
    ),

    // -------------------------------------
    // EDITOR
    // -------------------------------------
    GoRoute(
      path: '/editor',
      builder: (context, state) => const EditorScreen(),
    ),

    GoRoute(
      path: '/video-editor',
      builder: (context, state) =>
          const VideoEditorLibraryScreen(),
    ),

    // -------------------------------------
    // ANALYSIS
    // -------------------------------------
    GoRoute(
      path: '/analysis',
      builder: (context, state) => AnalysisScreen(
        projectId: state.uri.queryParameters['projectId'],
      ),
    ),

    // -------------------------------------
    // CAPTIONS
    // -------------------------------------
    GoRoute(
      path: '/captions',
      builder: (context, state) => CaptionsScreen(
        projectId: state.uri.queryParameters['projectId'],
      ),
    ),

    // -------------------------------------
    // MAIN APP NAVIGATION
    // -------------------------------------
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppShell(
          navigationShell: navigationShell,
        );
      },

      branches: [
        // HOME
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) =>
                  const HomeScreen(),
            ),
          ],
        ),

        // RECORD
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/record',
              builder: (context, state) =>
                  const CaptureScreen(),
            ),
          ],
        ),

        // HISTORY
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/history',
              builder: (context, state) =>
                  const HistoryScreen(),
            ),
          ],
        ),

        // PROFILE
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) =>
                  const ProfileScreen(),
            ),
          ],
        ),

        // WIDGET GALLERY
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/gallery',
              builder: (context, state) =>
                  const WidgetGalleryScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
