import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/audio_player_service.dart';
import '../services/device_discovery_service.dart';
import '../services/wallpaper_service.dart';
import '../theme/app_theme.dart';
import 'mini_audio_player.dart';

class BottomNavVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void show() => state = true;
  void hide() => state = false;
  void toggle() => state = !state;
}

final bottomNavVisibleProvider =
    NotifierProvider<BottomNavVisibleNotifier, bool>(
  BottomNavVisibleNotifier.new,
);

class ShellScaffold extends ConsumerStatefulWidget {
  final Widget child;

  const ShellScaffold({super.key, required this.child});

  @override
  ConsumerState<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends ConsumerState<ShellScaffold> {
  int _selectedIndex = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: 'Files',
    ),
    NavigationDestination(
      icon: Icon(Icons.apps_outlined),
      selectedIcon: Icon(Icons.apps),
      label: 'Apps',
    ),
    NavigationDestination(
      icon: Icon(Icons.memory_outlined),
      selectedIcon: Icon(Icons.memory),
      label: 'System',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  static const _routes = [
    '/dashboard',
    '/files',
    '/appstore',
    '/system',
    '/settings',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSelectedIndex();
  }

  void _updateSelectedIndex() {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _routes.indexWhere((route) => location.startsWith(route));
    if (index != -1 && index != _selectedIndex) {
      setState(() => _selectedIndex = index);
    }
  }

  void _onDestinationSelected(int index) {
    if (index != _selectedIndex) {
      setState(() => _selectedIndex = index);
      context.go(_routes[index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 1200;
    final isMediumScreen = screenWidth >= 600 && screenWidth < 1200;
    final connectedDevice = ref.watch(connectedDeviceProvider);
    final bottomNavVisible = ref.watch(bottomNavVisibleProvider);
    final backgroundMode = ref.watch(backgroundModeProvider);
    final wallpaperPath = ref.watch(customWallpaperPathProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final hasWallpaper = backgroundMode == BackgroundMode.customWallpaper &&
        wallpaperPath != null &&
        wallpaperPath.isNotEmpty;

    Widget content = Row(
      children: [
        // Navigation Rail for medium/wide screens
        if ((isMediumScreen || isWideScreen) && bottomNavVisible)
          AnimatedSlide(
            duration: M3Durations.medium2,
            curve: M3Curves.emphasized,
            offset: bottomNavVisible ? Offset.zero : const Offset(-1, 0),
            child: _buildNavigationRail(
              isWideScreen,
              connectedDevice,
              hasWallpaper,
              colorScheme,
            ),
          ),

        // Vertical divider
        if ((isMediumScreen || isWideScreen) && bottomNavVisible)
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: colorScheme.outlineVariant
                .withValues(alpha: hasWallpaper ? 0.3 : 1.0),
          ),

        // Main content
        Expanded(child: widget.child),
      ],
    );

    Widget? bottomNav;
    if (!isMediumScreen && !isWideScreen) {
      final audioState = ref.watch(audioPlayerServiceProvider);
      final hasMiniPlayer = audioState.hasAudio;

      bottomNav = AnimatedSlide(
        duration: M3Durations.medium2,
        curve: M3Curves.emphasized,
        offset: bottomNavVisible ? Offset.zero : const Offset(0, 1),
        child: AnimatedOpacity(
          duration: M3Durations.medium2,
          curve: M3Curves.emphasized,
          opacity: bottomNavVisible ? 1.0 : 0.0,
          child: bottomNavVisible
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasMiniPlayer) const MiniAudioPlayer(),
                    _buildBottomNav(hasWallpaper, colorScheme),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      );
    }

    // If wallpaper is set, wrap with glass effect
    if (hasWallpaper) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Wallpaper image
          Image.file(
            File(wallpaperPath),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: colorScheme.surface);
            },
          ),
          // Glass overlay with blur
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                color: colorScheme.surface.withValues(alpha: 0.7),
              ),
            ),
          ),
          // Scaffold
          Scaffold(
            backgroundColor: Colors.transparent,
            body: content,
            bottomNavigationBar: bottomNav,
          ),
        ],
      );
    }

    return Scaffold(
      body: content,
      bottomNavigationBar: bottomNav,
    );
  }

  Widget _buildNavigationRail(
    bool extended,
    DiscoveredDevice? device,
    bool hasWallpaper,
    ColorScheme colorScheme,
  ) {
    return Container(
      decoration: hasWallpaper
          ? BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.5),
            )
          : null,
      child: NavigationRail(
        extended: extended,
        backgroundColor: hasWallpaper ? Colors.transparent : null,
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
        leading: _buildNavLeading(extended, device),
        destinations: _destinations
            .map(
              (d) => NavigationRailDestination(
                icon: d.icon,
                selectedIcon: d.selectedIcon,
                label: Text(d.label),
              ),
            )
            .toList(),
      ).animate().fadeIn(duration: 200.ms).slideX(begin: -0.1, end: 0),
    );
  }

  Widget _buildBottomNav(bool hasWallpaper, ColorScheme colorScheme) {
    if (hasWallpaper) {
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.6),
              border: Border(
                top: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onDestinationSelected,
              destinations: _destinations,
            ),
          ),
        ),
      ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.1, end: 0);
    }

    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onDestinationSelected,
      destinations: _destinations,
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildNavLeading(bool extended, DiscoveredDevice? device) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            width: extended ? 200 : 56,
            height: 56,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: extended
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_done,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'RockZero',
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                : Icon(Icons.cloud_done, color: colorScheme.onPrimaryContainer),
          ),
          if (device != null && extended) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    device.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
