import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/files/presentation/pages/files_page.dart';
import '../../features/appstore/presentation/pages/appstore_page.dart';
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
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const DeviceDiscoveryPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),

      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LoginPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
        ),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const RegisterPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
        ),
      ),

      // Main App Shell
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
                _buildPageTransition(state, const AppStorePage()),
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

CustomTransitionPage _buildPageTransition(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}
