import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/files/presentation/pages/files_page.dart';
import '../../features/appstore/presentation/pages/wasm_store_page.dart';
import '../../features/system/presentation/pages/system_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/device_discovery/presentation/pages/device_discovery_page.dart';
import '../widgets/shell_scaffold.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/discover',
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final isLoggedIn = authState.isAuthenticated;
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/discover';

      if (!isLoggedIn && !isAuthRoute) {
        return '/login';
      }
      if (isLoggedIn &&
          (state.matchedLocation == '/login' ||
              state.matchedLocation == '/register')) {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/discover',
        name: 'discover',
        pageBuilder: (context, state) =>
            _buildEntranceTransition(state, const DeviceDiscoveryPage()),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder: (context, state) =>
            _buildEntranceTransition(state, const LoginPage()),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        pageBuilder: (context, state) =>
            _buildEntranceTransition(state, const RegisterPage()),
      ),
      ShellRoute(
        builder: (context, state, child) => ShellScaffold(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const DashboardPage()),
          ),
          GoRoute(
            path: '/files',
            name: 'files',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const FilesPage()),
          ),
          GoRoute(
            path: '/appstore',
            name: 'appstore',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const WasmStorePage()),
          ),
          GoRoute(
            path: '/system',
            name: 'system',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const SystemPage()),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const SettingsPage()),
          ),
        ],
      ),
    ],
  );
});

CustomTransitionPage _buildEntranceTransition(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: RepaintBoundary(child: child),
    transitionDuration: M3Durations.short4,
    reverseTransitionDuration: M3Durations.short3,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        return child;
      }

      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: M3Curves.emphasizedDecelerate,
        reverseCurve: M3Curves.emphasizedAccelerate,
      );

      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curvedAnimation),
        child: FadeTransition(opacity: curvedAnimation, child: child),
      );
    },
  );
}

CustomTransitionPage _buildPageTransition(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: RepaintBoundary(child: child),
    transitionDuration: M3Durations.short4,
    reverseTransitionDuration: M3Durations.short3,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        return child;
      }

      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: M3Curves.standardDecelerate,
        reverseCurve: M3Curves.standardAccelerate,
      );

      return FadeTransition(
        opacity: curvedAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}
