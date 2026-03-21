import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/services/wallpaper_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/app_install_dialog.dart' as install_dialog;
import 'app_webview_page.dart';

final storeAppsProvider = FutureProvider.autoDispose<List<AppStoreItem>>((
  ref,
) async {
  final api = ref.read(apiServiceProvider);
  try {
    // Add timeout to prevent infinite loading
    final apps = await api.listStoreApps().timeout(
      const Duration(seconds: 180), // 增加超时到180秒
      onTimeout: () {
        throw TimeoutException('App store request timed out');
      },
    );
    return apps;
  } catch (e) {
    // Log the error and rethrow for the UI to handle
    debugPrint('Store apps fetch error: $e');
    rethrow;
  }
});

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => message;
}

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
  bool _isRefreshing = false;

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

  Future<void> _refresh() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);

    ref.invalidate(storeAppsProvider);
    ref.invalidate(installedAppsProvider);

    // 等待动画完成
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasWallpaper =
        ref.watch(backgroundModeProvider) == BackgroundMode.customWallpaper &&
            (ref.watch(customWallpaperPathProvider)?.isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: hasWallpaper ? Colors.transparent : null,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar.large(
            title: Row(
              children: [
                Icon(Icons.store_rounded, size: 28)
                    .animate(onPlay: (controller) => controller.repeat())
                    .shimmer(
                      duration: 2000.ms,
                      delay: 3000.ms,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.3),
                    ),
                const SizedBox(width: 12),
                const Text('App Store'),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(_isRefreshing
                    ? Icons.hourglass_empty_rounded
                    : Icons.refresh_rounded),
                onPressed: _isRefreshing ? null : _refresh,
              )
                  .animate(target: _isRefreshing ? 1 : 0)
                  .rotate(duration: 1000.ms, curve: Curves.easeInOut),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              tabs: [
                Tab(icon: Icon(Icons.store_rounded), text: 'Store'),
                Tab(icon: Icon(Icons.apps_rounded), text: 'Installed'),
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

        // Sort categories
        final sortedCategories = categories.keys.toList()
          ..sort((a, b) {
            const order = [
              'Media',
              'Cloud Storage',
              'Download',
              'Smart Home',
              'Network',
              'Database',
              'Productivity',
              'Management',
            ];
            final aIndex = order.indexOf(a);
            final bIndex = order.indexOf(b);
            if (aIndex == -1 && bIndex == -1) return a.compareTo(b);
            if (aIndex == -1) return 1;
            if (bIndex == -1) return -1;
            return aIndex.compareTo(bIndex);
          });

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 16),
          itemCount: sortedCategories.length,
          itemBuilder: (context, index) {
            final category = sortedCategories[index];
            final categoryApps = categories[category]!;

            return _CategorySection(
              category: category,
              apps: categoryApps,
              onInstall: (app) => _installApp(context, ref, app),
            )
                .animate(delay: (80 * index).ms)
                .fadeIn(curve: M3Curves.emphasizedDecelerate)
                .slideY(begin: 0.05, curve: M3Curves.emphasized);
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
    // Show advanced install dialog
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => install_dialog.AppInstallDialog(app: app),
    );

    if (result == true && context.mounted) {
      ref.invalidate(installedAppsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Text('${app.displayName} installed successfully'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildEmptyState(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.store_rounded,
              size: 40,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(message, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Unable to connect to App Store',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Please check your internet connection and try again',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => ref.invalidate(storeAppsProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
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
              onOpen: apps[index].status == 'running' &&
                      apps[index].ports.isNotEmpty
                  ? () => _openApp(context, ref, apps[index])
                  : null,
            )
                .animate(delay: (60 * index).ms)
                .fadeIn(curve: M3Curves.emphasizedDecelerate)
                .slideY(begin: 0.05, curve: M3Curves.emphasized);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => _buildErrorState(context, ref),
    );
  }

  Future<void> _openApp(
    BuildContext context,
    WidgetRef ref,
    DockerApp app,
  ) async {
    // Get the base URL from the API client
    final baseUrl = ref.read(baseUrlProvider);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AppWebViewPage(app: app, baseUrl: baseUrl),
      ),
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
        icon: Icon(Icons.delete_rounded, size: 48, color: colorScheme.error),
        title: Text('Uninstall ${app.displayName}?'),
        content: const Text(
          'This will stop and remove the container. Your data volumes will be preserved.',
        ),
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
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.apps_rounded,
              size: 40,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No apps installed',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Browse the store to install apps',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
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
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 24),
          const Text('Failed to load installed apps'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => ref.invalidate(installedAppsProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ============ Widget Components ============

class _CategorySection extends StatelessWidget {
  final String category;
  final List<AppStoreItem> apps;
  final Function(AppStoreItem) onInstall;

  const _CategorySection({
    required this.category,
    required this.apps,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Icon(
                _getCategoryIcon(category),
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                category,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${apps.length}',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 260, // Increased height to show more content
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: apps.length,
            itemBuilder: (context, index) {
              return _StoreAppCard(
                app: apps[index],
                onInstall: () => onInstall(apps[index]),
              )
                  .animate(delay: (40 * index).ms)
                  .fadeIn(curve: M3Curves.emphasizedDecelerate)
                  .slideX(begin: 0.1, curve: M3Curves.emphasized);
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Media':
        return Icons.movie_rounded;
      case 'Cloud Storage':
        return Icons.cloud_rounded;
      case 'Download':
        return Icons.download_rounded;
      case 'Smart Home':
        return Icons.home_rounded;
      case 'Network':
        return Icons.router_rounded;
      case 'Database':
        return Icons.storage_rounded;
      case 'Productivity':
        return Icons.work_rounded;
      case 'Management':
        return Icons.dashboard_rounded;
      default:
        return Icons.apps_rounded;
    }
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
      margin: const EdgeInsets.only(right: 12, bottom: 8),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: onInstall,
        child: Container(
          width: 180,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.surface,
                colorScheme.surfaceContainerLow,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon and category row
              Row(
                children: [
                  _AppIcon(iconUrl: app.icon, size: 52)
                      .animate(
                          onPlay: (controller) =>
                              controller.repeat(reverse: true))
                      .scale(
                        duration: 2000.ms,
                        begin: const Offset(1.0, 1.0),
                        end: const Offset(1.05, 1.05),
                        curve: Curves.easeInOut,
                      ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.displayName,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          app.category,
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Text(
                  app.description,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: onInstall,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('Install'),
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate(
          onPlay: (controller) => controller.repeat(reverse: true),
        )
        .shimmer(
          duration: 3000.ms,
          delay: 2000.ms,
          color: colorScheme.primary.withValues(alpha: 0.05),
        );
  }
}

class _AppIcon extends StatelessWidget {
  final String iconUrl;
  final double size;

  const _AppIcon({required this.iconUrl, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: iconUrl.isNotEmpty
          ? Image.network(
              iconUrl,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => _buildFallbackIcon(context),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: SizedBox(
                    width: size * 0.35,
                    height: size * 0.35,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
            )
          : _buildFallbackIcon(context),
    );
  }

  Widget _buildFallbackIcon(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withValues(alpha: 0.8),
            colorScheme.tertiary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(Icons.apps_rounded, size: size * 0.5, color: Colors.white),
    );
  }
}

class _InstalledAppCard extends StatelessWidget {
  final DockerApp app;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onUninstall;
  final VoidCallback? onOpen;

  const _InstalledAppCard({
    required this.app,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onUninstall,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isRunning = app.status == 'running';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: isRunning && onOpen != null ? onOpen : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _AppIcon(iconUrl: app.icon, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            app.displayName,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isRunning && app.ports.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              ':${app.ports.first.hostPort}',
                              style: textTheme.labelSmall?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _StatusBadge(isRunning: isRunning),
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
                        'Ports: ${app.ports.map((p) => p.hostPort).join(', ')}',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (isRunning && onOpen != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Tap to open',
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  IconButton.filled(
                    onPressed: isRunning ? onStop : onStart,
                    icon: Icon(
                      isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: isRunning
                          ? colorScheme.errorContainer
                          : colorScheme.primaryContainer,
                      foregroundColor: isRunning
                          ? colorScheme.onErrorContainer
                          : colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (value) {
                      switch (value) {
                        case 'open':
                          onOpen?.call();
                          break;
                        case 'restart':
                          onRestart();
                          break;
                        case 'uninstall':
                          onUninstall();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      if (isRunning && onOpen != null)
                        const PopupMenuItem(
                          value: 'open',
                          child: Row(
                            children: [
                              Icon(Icons.open_in_new_rounded),
                              SizedBox(width: 12),
                              Text('Open App'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'restart',
                        child: Row(
                          children: [
                            Icon(Icons.refresh_rounded),
                            SizedBox(width: 12),
                            Text('Restart'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'uninstall',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_rounded,
                              color: colorScheme.error,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Uninstall',
                              style: TextStyle(color: colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isRunning;

  const _StatusBadge({required this.isRunning});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isRunning
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRunning
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isRunning ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
              boxShadow: isRunning
                  ? [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.5),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          )
              .animate(
                onPlay: (controller) => isRunning ? controller.repeat() : null,
              )
              .scale(
                duration: 1000.ms,
                begin: const Offset(1.0, 1.0),
                end: const Offset(1.3, 1.3),
                curve: Curves.easeInOut,
              )
              .then()
              .scale(
                duration: 1000.ms,
                begin: const Offset(1.3, 1.3),
                end: const Offset(1.0, 1.0),
                curve: Curves.easeInOut,
              ),
          const SizedBox(width: 6),
          Text(
            isRunning ? 'Running' : 'Stopped',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isRunning ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
