import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';

/// RockZeroOS 应用存储统计 Provider
final appStorageStatsProvider = FutureProvider.autoDispose<AppStorageStats?>((
  ref,
) async {
  try {
    final api = ref.read(apiServiceProvider);
    return await api.getAppStorageStats();
  } catch (e, stackTrace) {
    debugPrint('❌ [AppStorage] Stats error: $e');
    debugPrint('📚 [AppStorage] Stack trace: $stackTrace');
    return null;
  }
});

/// RockZeroOS 应用专用存储统计卡片
///
/// 显示应用实际占用的存储空间，包括：
/// - 视频文件
/// - HLS 缓存
/// - 数据库
/// - 日志
/// - 临时文件
class AppStorageStatsCard extends ConsumerWidget {
  const AppStorageStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(appStorageStatsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.tertiary,
                        colorScheme.primary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.tertiary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.analytics_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'App Storage',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'RockZeroOS usage breakdown',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Refresh button
                IconButton(
                  onPressed: () => ref.invalidate(appStorageStatsProvider),
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: colorScheme.primary,
                  ),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Content
            statsAsync.when(
              data: (stats) {
                if (stats == null) return _buildErrorState(context);
                return _buildContent(context, ref, stats);
              },
              loading: () => _buildLoadingState(context),
              error: (e, s) => _buildErrorState(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, AppStorageStats stats) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        // Total app usage display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primaryContainer.withValues(alpha: 0.6),
                colorScheme.tertiaryContainer.withValues(alpha: 0.4),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total App Usage',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatBytes(stats.totalAppUsage),
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${stats.availableSpaceGb.toStringAsFixed(1)} GB free',
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05),

        const SizedBox(height: 16),

        // Storage breakdown
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              for (int i = 0; i < stats.breakdown.length; i++) ...[
                _StorageBreakdownRow(
                  item: stats.breakdown[i],
                  totalSize: stats.totalAppUsage,
                )
                    .animate()
                    .fadeIn(delay: (150 + i * 50).ms)
                    .slideX(begin: -0.03),
                if (i < stats.breakdown.length - 1)
                  Divider(
                    height: 1,
                    indent: 56,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Auto-cleanup status (替代手动 Clean Cache / Clear Temp 按钮)
        _AutoCleanupStatusBanner(stats: stats),
      ],
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 80,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(
          5,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline_rounded,
              size: 32,
              color: colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Failed to load storage stats',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check server connection',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<void> _showCleanupDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.cleaning_services_rounded),
        title: const Text('Clean HLS Cache'),
        content: const Text(
          'This will remove all cached HLS segments. '
          'Videos will need to be re-transcoded on next playback.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clean'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Cleaning HLS cache...'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 10),
      ),
    );

    try {
      final api = ref.read(apiServiceProvider);
      await api.cleanupHlsCache();
      ref.invalidate(appStorageStatsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ HLS cache cleaned successfully'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clean cache: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // ignore: unused_element
  Future<void> _clearTempFiles(BuildContext context, WidgetRef ref) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Clearing temp files...'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 10),
      ),
    );

    try {
      final api = ref.read(apiServiceProvider);
      await api.cleanupTempFiles();
      ref.invalidate(appStorageStatsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Temporary files cleared'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear temp files: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
    } else if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '$bytes B';
    }
  }
}

/// 存储明细行
class _StorageBreakdownRow extends StatelessWidget {
  final StorageBreakdownItem item;
  final int totalSize;

  const _StorageBreakdownRow({
    required this.item,
    required this.totalSize,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final itemColor = Color(item.color);
    final percentage = totalSize > 0 ? (item.size / totalSize) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: itemColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getIcon(item.icon),
              size: 18,
              color: itemColor,
            ),
          ),
          const SizedBox(width: 12),
          // Name and progress
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.name,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      item.formattedSize,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(itemColor),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'video_library':
        return Icons.video_library_rounded;
      case 'cached':
        return Icons.cached_rounded;
      case 'storage':
        return Icons.storage_rounded;
      case 'description':
        return Icons.description_rounded;
      case 'folder_open':
        return Icons.folder_open_rounded;
      default:
        return Icons.folder_rounded;
    }
  }
}

/// 自动清理状态横幅（替代手动清理按钮）
///
/// 显示 2GB 阈值自动清理的实时状态，包括：
/// - 当前缓存使用量和阈值进度条
/// - 清理状态指示（健康/警告/清理中）
/// - 下次检查倒计时
class _AutoCleanupStatusBanner extends StatelessWidget {
  final AppStorageStats stats;

  const _AutoCleanupStatusBanner({required this.stats});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // 计算缓存使用量（HLS + Temp）
    final cacheUsage = stats.hlsCacheSize + stats.tempStorageSize;
    const threshold = 2 * 1024 * 1024 * 1024; // 2 GB
    final usageRatio = (cacheUsage / threshold).clamp(0.0, 1.0);

    // 状态颜色和图标
    final Color statusColor;
    final IconData statusIcon;
    final String statusText;

    if (usageRatio > 0.95) {
      statusColor = Colors.orange;
      statusIcon = Icons.cleaning_services_rounded;
      statusText = '正在清理';
    } else if (usageRatio > 0.8) {
      statusColor = Colors.amber;
      statusIcon = Icons.warning_amber_rounded;
      statusText = '即将清理';
    } else {
      statusColor = Colors.green;
      statusIcon = Icons.auto_delete_rounded;
      statusText = '自动管理';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            statusColor.withValues(alpha: 0.08),
            statusColor.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(statusIcon, color: statusColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '缓存自动清理',
                      style: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$statusText · 阈值 2GB · 每 30 秒检测',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: usageRatio,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(statusColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatBytes(cacheUsage),
                style: textTheme.bodySmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
              Text(
                '/ 2.0 GB',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
