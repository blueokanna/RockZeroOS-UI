import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';

final storeAppsProvider = FutureProvider.autoDispose<List<AppStoreItem>>((
  ref,
) async {
  final api = ref.read(apiServiceProvider);
  return await api.listStoreApps();
});

final installedAppsProvider = FutureProvider.autoDispose<List<DockerApp>>((
  ref,
) async {
  final api = ref.read(apiServiceProvider);
  return await api.listInstalledApps();
});

class AppStorePage extends ConsumerStatefulWidget {
  const AppStorePage({super.key});
  @override
  ConsumerState<AppStorePage> createState() => _AppStorePageState();
}

class _AppStorePageState extends ConsumerState<AppStorePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar.large(
            title: const Text('App Store'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  ref.invalidate(storeAppsProvider);
                  ref.invalidate(installedAppsProvider);
                },
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.store), text: 'Store'),
                Tab(icon: Icon(Icons.apps), text: 'Installed'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [_StoreTab(), _InstalledTab()],
        ),
      ),
    );
  }
}

class _StoreTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeApps = ref.watch(storeAppsProvider);
    return storeApps.when(
      data: (apps) {
        if (apps.isEmpty) return _buildEmptyState(context, 'No apps available');
        final categories = <String, List<AppStoreItem>>{};
        for (final app in apps) {
          categories.putIfAbsent(app.category, () => []).add(app);
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories.keys.elementAt(index);
            final categoryApps = categories[category]!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    category,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: categoryApps.length,
                    itemBuilder: (context, appIndex) {
                      return _StoreAppCard(
                            app: categoryApps[appIndex],
                            onInstall: () => _installApp(
                              context,
                              ref,
                              categoryApps[appIndex],
                            ),
                          )
                          .animate(delay: (50 * appIndex).ms)
                          .fadeIn()
                          .slideX(begin: 0.1);
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => _buildErrorState(context, ref),
    );
  }

  Future<void> _installApp(
    BuildContext context,
    WidgetRef ref,
    AppStoreItem app,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Install ${app.displayName}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(app.description),
            const SizedBox(height: 16),
            Text('Image: ${app.dockerImage}:${app.recommendedTag}'),
            if (app.defaultPorts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Ports: ${app.defaultPorts.map((p) => "${p.hostPort}:${p.containerPort}").join(", ")}',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (loadingContext) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Installing app...'),
              ],
            ),
          ),
        );
        final api = ref.read(apiServiceProvider);
        await api.installApp(
          name: app.name,
          dockerImage: app.dockerImage,
          dockerTag: app.recommendedTag,
          ports: app.defaultPorts,
          volumes: app.defaultVolumes,
          environment: [],
        );
        if (context.mounted) {
          Navigator.pop(context);
          ref.invalidate(installedAppsProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${app.displayName} installed successfully'),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to install: $e')));
        }
      }
    }
  }

  Widget _buildEmptyState(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.store,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: colorScheme.error),
          const SizedBox(height: 16),
          const Text('Failed to load apps'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => ref.invalidate(storeAppsProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _InstalledTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installedApps = ref.watch(installedAppsProvider);
    return installedApps.when(
      data: (apps) {
        if (apps.isEmpty) return _buildEmptyState(context);
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: apps.length,
          itemBuilder: (context, index) {
            return _InstalledAppCard(
              app: apps[index],
              onStart: () => _startApp(context, ref, apps[index]),
              onStop: () => _stopApp(context, ref, apps[index]),
              onRestart: () => _restartApp(context, ref, apps[index]),
              onUninstall: () => _uninstallApp(context, ref, apps[index]),
            ).animate(delay: (50 * index).ms).fadeIn().slideY(begin: 0.05);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => _buildErrorState(context, ref),
    );
  }

  Future<void> _startApp(
    BuildContext context,
    WidgetRef ref,
    DockerApp app,
  ) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.startApp(app.id);
      ref.invalidate(installedAppsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${app.displayName} started')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start: $e')));
      }
    }
  }

  Future<void> _stopApp(
    BuildContext context,
    WidgetRef ref,
    DockerApp app,
  ) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.stopApp(app.id);
      ref.invalidate(installedAppsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${app.displayName} stopped')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to stop: $e')));
      }
    }
  }

  Future<void> _restartApp(
    BuildContext context,
    WidgetRef ref,
    DockerApp app,
  ) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.restartApp(app.id);
      ref.invalidate(installedAppsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${app.displayName} restarted')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to restart: $e')));
      }
    }
  }

  Future<void> _uninstallApp(
    BuildContext context,
    WidgetRef ref,
    DockerApp app,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Uninstall ${app.displayName}?'),
        content: const Text('This will stop and remove the container.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        final api = ref.read(apiServiceProvider);
        await api.uninstallApp(app.id);
        ref.invalidate(installedAppsProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${app.displayName} uninstalled')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to uninstall: $e')));
        }
      }
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.apps,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text('No apps installed'),
          const SizedBox(height: 8),
          const Text('Browse the store to install apps'),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: colorScheme.error),
          const SizedBox(height: 16),
          const Text('Failed to load installed apps'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => ref.invalidate(installedAppsProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _StoreAppCard extends StatelessWidget {
  final AppStoreItem app;
  final VoidCallback onInstall;
  const _StoreAppCard({required this.app, required this.onInstall});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(right: 12),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: app.icon.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        app.icon,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Icon(
                          Icons.apps,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    )
                  : Icon(Icons.apps, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            Text(
              app.displayName,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                app.description,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: onInstall,
                child: const Text('Install'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstalledAppCard extends StatelessWidget {
  final DockerApp app;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onUninstall;
  const _InstalledAppCard({
    required this.app,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isRunning = app.status == 'running';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: app.icon.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        app.icon,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Icon(
                          Icons.apps,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    )
                  : Icon(Icons.apps, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.displayName,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isRunning ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        app.status.toUpperCase(),
                        style: textTheme.bodySmall?.copyWith(
                          color: isRunning
                              ? Colors.green
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          '${app.dockerImage}:${app.dockerTag}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (app.ports.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Ports: ${app.ports.map((p) => "${p.hostPort}").join(", ")}',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'start':
                    onStart();
                    break;
                  case 'stop':
                    onStop();
                    break;
                  case 'restart':
                    onRestart();
                    break;
                  case 'uninstall':
                    onUninstall();
                    break;
                }
              },
              itemBuilder: (popupContext) {
                final popupColorScheme = Theme.of(popupContext).colorScheme;
                return [
                  if (!isRunning)
                    const PopupMenuItem(
                      value: 'start',
                      child: Row(
                        children: [
                          Icon(Icons.play_arrow),
                          SizedBox(width: 8),
                          Text('Start'),
                        ],
                      ),
                    ),
                  if (isRunning)
                    const PopupMenuItem(
                      value: 'stop',
                      child: Row(
                        children: [
                          Icon(Icons.stop),
                          SizedBox(width: 8),
                          Text('Stop'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'restart',
                    child: Row(
                      children: [
                        Icon(Icons.refresh),
                        SizedBox(width: 8),
                        Text('Restart'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'uninstall',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: popupColorScheme.error),
                        const SizedBox(width: 8),
                        Text(
                          'Uninstall',
                          style: TextStyle(color: popupColorScheme.error),
                        ),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}
