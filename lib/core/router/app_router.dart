import 'package:go_router/go_router.dart';

import '../../features/analysis/analysis_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/capture/capture_screen.dart';
import '../../features/captions/captions_screen.dart';
import '../../features/editor/editor_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/profile/profile_screen.dart';
import 'app_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
    GoRoute(path: '/editor', builder: (c, s) => const EditorScreen()),
    GoRoute(path: '/analysis', builder: (c, s) => const AnalysisScreen()),
    GoRoute(path: '/captions', builder: (c, s) => const CaptionsScreen()),
    StatefulShellRoute.indexedStack(
      builder: (c, s, shell) => AppShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/record', builder: (c, s) => const CaptureScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/history', builder: (c, s) => const HistoryScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
          ],
        ),
      ],
    ),
  ],
);
