import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/device_discovery_service.dart';

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
      icon: Icon(Icons.play_circle_outline),
      selectedIcon: Icon(Icons.play_circle),
      label: 'Media',
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
    '/media',
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

    return Scaffold(
      body: Row(
        children: [
          // Navigation Rail for medium/wide screens
          if (isMediumScreen || isWideScreen)
            NavigationRail(
              extended: isWideScreen,
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onDestinationSelected,
              leading: _buildNavLeading(isWideScreen, connectedDevice),
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

          // Vertical divider
          if (isMediumScreen || isWideScreen)
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),

          // Main content
          Expanded(child: widget.child),
        ],
      ),

      // Bottom Navigation for narrow screens
      bottomNavigationBar: (!isMediumScreen && !isWideScreen)
          ? NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onDestinationSelected,
              destinations: _destinations,
            ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.1, end: 0)
          : null,
    );
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
                    decoration: BoxDecoration(
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
