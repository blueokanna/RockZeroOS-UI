import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/services/device_discovery_service.dart';

final allDisksProvider = FutureProvider<List<DiskInfo>>((ref) async {
  final device = ref.watch(connectedDeviceProvider);
  if (device == null) {
    throw Exception('Not connected to any device.');
  }

  final api = ref.read(apiServiceProvider);
  return await api.getDiskInfo();
});

class DiskManagementPage extends ConsumerWidget {
  const DiskManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final disksAsync = ref.watch(allDisksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Disk Management'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(allDisksProvider),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: disksAsync.when(
        data: (disks) {
          if (disks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.storage_rounded,
                      size: 64, color: colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text('No disks found',
                      style: textTheme.titleMedium
                          ?.copyWith(color: colorScheme.onSurfaceVariant)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: disks.length,
            itemBuilder: (context, index) {
              final disk = disks[index];
              return _DiskCard(disk: disk);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text('Error: $error', style: TextStyle(color: colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => ref.invalidate(allDisksProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiskCard extends ConsumerWidget {
  final DiskInfo disk;

  const _DiskCard({required this.disk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isMounted = disk.mountPoint != 'Not mounted';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showDiskDetails(context, ref),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isMounted
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getDiskIcon(),
                      color: isMounted
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          disk.name,
                          style: textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isMounted ? disk.mountPoint : 'Not mounted',
                          style: textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (!isMounted)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Unmounted',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              if (isMounted) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: disk.usagePercentage / 100,
                    minHeight: 8,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(
                      _getUsageColor(disk.usagePercentage),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_formatBytes(disk.usedSpace)} / ${_formatBytes(disk.totalSpace)}',
                      style: textTheme.bodySmall,
                    ),
                    Text(
                      '${disk.usagePercentage.toStringAsFixed(1)}% used',
                      style: textTheme.bodySmall?.copyWith(
                        color: _getUsageColor(disk.usagePercentage),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  'Size: ${_formatBytes(disk.totalSpace)}',
                  style: textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  Chip(
                    label: Text(disk.fileSystem),
                    labelStyle: textTheme.labelSmall,
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    label: Text(disk.diskType),
                    labelStyle: textTheme.labelSmall,
                    visualDensity: VisualDensity.compact,
                  ),
                  if (disk.isRemovable)
                    Chip(
                      label: const Text('Removable'),
                      labelStyle: textTheme.labelSmall,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getDiskIcon() {
    if (disk.isRemovable) return Icons.usb_rounded;
    if (disk.diskType.contains('SSD') || disk.diskType.contains('NVMe')) {
      return Icons.storage_rounded;
    }
    return Icons.storage_rounded;
  }

  Color _getUsageColor(double usage) {
    if (usage >= 90) return Colors.red;
    if (usage >= 70) return Colors.orange;
    if (usage >= 50) return Colors.amber.shade700;
    return Colors.green;
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  void _showDiskDetails(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _DiskDetailsSheet(disk: disk),
    );
  }
}

class _DiskDetailsSheet extends ConsumerWidget {
  final DiskInfo disk;

  const _DiskDetailsSheet({required this.disk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isMounted = disk.mountPoint != 'Not mounted';

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        disk.name,
                        style: textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    _InfoRow(
                      icon: Icons.folder_rounded,
                      label: 'Mount Point',
                      value: disk.mountPoint,
                    ),
                    _InfoRow(
                      icon: Icons.description_rounded,
                      label: 'File System',
                      value: disk.fileSystem,
                    ),
                    _InfoRow(
                      icon: Icons.category_rounded,
                      label: 'Type',
                      value: disk.diskType,
                    ),
                    _InfoRow(
                      icon: Icons.storage_rounded,
                      label: 'Total Size',
                      value: _formatBytes(disk.totalSpace),
                    ),
                    if (isMounted) ...[
                      _InfoRow(
                        icon: Icons.pie_chart_rounded,
                        label: 'Used',
                        value: _formatBytes(disk.usedSpace),
                      ),
                      _InfoRow(
                        icon: Icons.check_circle_rounded,
                        label: 'Available',
                        value: _formatBytes(disk.availableSpace),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      'Actions',
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    if (!isMounted) ...[
                      FilledButton.icon(
                        onPressed: () => _mountDisk(context, ref),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Mount Disk'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => _formatDisk(context, ref),
                        icon: const Icon(Icons.format_paint_rounded),
                        label: const Text('Format Disk'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                    ] else ...[
                      FilledButton.tonalIcon(
                        onPressed: () => _unmountDisk(context, ref),
                        icon: const Icon(Icons.eject_rounded),
                        label: const Text('Unmount Disk'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _mountDisk(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mount functionality coming soon')),
    );
  }

  Future<void> _unmountDisk(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unmount requires FIDO2 authentication')),
    );
  }

  Future<void> _formatDisk(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Format requires FIDO2 authentication')),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.labelSmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
