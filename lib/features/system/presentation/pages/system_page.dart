import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/theme/app_theme.dart';

// System info providers with auto-refresh
final systemInfoProvider = FutureProvider.autoDispose<SystemInfo?>((ref) async {
  try {
    final api = ref.read(apiServiceProvider);
    return await api.getSystemInfo();
  } catch (_) {
    return null;
  }
});

final cpuInfoProvider = StreamProvider.autoDispose<CpuInfo?>((ref) async* {
  final api = ref.read(apiServiceProvider);
  while (true) {
    try {
      yield await api.getCpuInfo();
    } catch (_) {
      yield null;
    }
    await Future.delayed(const Duration(seconds: 2));
  }
});

final memoryInfoProvider = StreamProvider.autoDispose<MemoryInfo?>((
  ref,
) async* {
  final api = ref.read(apiServiceProvider);
  while (true) {
    try {
      yield await api.getMemoryInfo();
    } catch (_) {
      yield null;
    }
    await Future.delayed(const Duration(seconds: 2));
  }
});

final diskInfoProvider = FutureProvider.autoDispose<List<DiskInfo>>((
  ref,
) async {
  final api = ref.read(apiServiceProvider);
  return await api.getDiskInfo();
});

final usbDevicesProvider = FutureProvider.autoDispose<List<UsbDevice>>((
  ref,
) async {
  final api = ref.read(apiServiceProvider);
  return await api.getUsbDevices();
});

class SystemPage extends ConsumerWidget {
  const SystemPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systemInfo = ref.watch(systemInfoProvider);
    final cpuInfo = ref.watch(cpuInfoProvider);
    final memoryInfo = ref.watch(memoryInfoProvider);
    final diskInfo = ref.watch(diskInfoProvider);
    final usbDevices = ref.watch(usbDevicesProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Row(
              children: [
                Icon(Icons.memory_rounded, size: 28),
                const SizedBox(width: 12),
                const Text('System'),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () {
                  ref.invalidate(systemInfoProvider);
                  ref.invalidate(diskInfoProvider);
                  ref.invalidate(usbDevicesProvider);
                },
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // System Info Card
                _SystemInfoCard(
                  systemInfo: systemInfo,
                ).animate().fadeIn(
                    delay: 100.ms, curve: M3Curves.emphasizedDecelerate),
                const SizedBox(height: 20),

                // CPU Card with per-core usage
                _CpuCard(cpuInfo: cpuInfo).animate().fadeIn(
                    delay: 150.ms, curve: M3Curves.emphasizedDecelerate),
                const SizedBox(height: 20),

                // Memory Card
                _MemoryCard(memoryInfo: memoryInfo).animate().fadeIn(
                    delay: 200.ms, curve: M3Curves.emphasizedDecelerate),
                const SizedBox(height: 20),

                // Disks Card
                _DisksCard(
                  diskInfo: diskInfo,
                ).animate().fadeIn(
                    delay: 250.ms, curve: M3Curves.emphasizedDecelerate),
                const SizedBox(height: 20),

                // USB Devices Card
                _UsbDevicesCard(
                  usbDevices: usbDevices,
                ).animate().fadeIn(
                    delay: 300.ms, curve: M3Curves.emphasizedDecelerate),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemInfoCard extends StatelessWidget {
  final AsyncValue<SystemInfo?> systemInfo;

  const _SystemInfoCard({required this.systemInfo});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, colorScheme.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      const Icon(Icons.computer_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text(
                  'System Information',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            systemInfo.when(
              data: (info) {
                if (info == null) {
                  return const Text('Failed to load');
                }
                return Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    _InfoChip(
                      icon: Icons.dns_rounded,
                      label: 'Hostname',
                      value: info.hostname,
                    ),
                    _InfoChip(
                      icon: Icons.computer_rounded,
                      label: 'OS',
                      value: '${info.osName} ${info.osVersion}',
                    ),
                    _InfoChip(
                      icon: Icons.memory_rounded,
                      label: 'Arch',
                      value: info.architecture,
                    ),
                    _InfoChip(
                      icon: Icons.code_rounded,
                      label: 'Kernel',
                      value: info.kernelVersion,
                    ),
                    _InfoChip(
                      icon: Icons.schedule_rounded,
                      label: 'Uptime',
                      value: _formatUptime(info.uptime),
                    ),
                  ],
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, s) => const Text('Error loading system info'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatUptime(int seconds) {
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (days > 0) {
      return '${days}d ${hours}h ${minutes}m';
    }
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

class _CpuCard extends StatelessWidget {
  final AsyncValue<CpuInfo?> cpuInfo;

  const _CpuCard({required this.cpuInfo});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue, Colors.cyan],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.speed_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CPU',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      cpuInfo.when(
                        data: (info) => Text(
                          info?.brand ?? 'Unknown',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            cpuInfo.when(
              data: (info) {
                if (info == null) {
                  return const Text('Failed to load');
                }
                return _buildCpuContent(context, info);
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, s) => const Text('Error'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCpuContent(BuildContext context, CpuInfo info) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final usageColor = _getUsageColor(info.usage);

    return Column(
      children: [
        // Overall stats row
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatItem(
                label: 'Total Usage',
                value: '${info.usage.toStringAsFixed(1)}%',
                color: usageColor,
                icon: Icons.speed_rounded,
              ),
              Container(
                width: 1,
                height: 40,
                color: colorScheme.outlineVariant,
              ),
              _StatItem(
                label: 'Frequency',
                value: '${info.frequency} MHz',
                color: colorScheme.primary,
                icon: Icons.bolt_rounded,
              ),
              if (info.temperature != null) ...[
                Container(
                  width: 1,
                  height: 40,
                  color: colorScheme.outlineVariant,
                ),
                _StatItem(
                  label: 'Temperature',
                  value: '${info.temperature!.toStringAsFixed(0)}°C',
                  color: _getTempColor(info.temperature!),
                  icon: Icons.thermostat_rounded,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Per-core usage section
        if (info.perCoreUsage != null && info.perCoreUsage!.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.grid_view_rounded,
                  size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Per-Core Usage',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${info.cores} cores',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCoreGrid(context, info.perCoreUsage!),
        ],
      ],
    );
  }

  Widget _buildCoreGrid(BuildContext context, List<CpuCoreInfo> cores) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate columns based on width
        final crossAxisCount = constraints.maxWidth > 600
            ? 4
            : (constraints.maxWidth > 400 ? 3 : 2);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 1.2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: cores.length,
          itemBuilder: (context, index) {
            return _CoreUsageCard(core: cores[index]);
          },
        );
      },
    );
  }

  Color _getUsageColor(double usage) {
    if (usage >= 90) return Colors.red;
    if (usage >= 70) return Colors.orange;
    if (usage >= 50) return Colors.amber.shade700;
    return Colors.green;
  }

  Color _getTempColor(double temp) {
    if (temp >= 80) return Colors.red;
    if (temp >= 60) return Colors.orange;
    return Colors.green;
  }
}

class _CoreUsageCard extends StatelessWidget {
  final CpuCoreInfo core;

  const _CoreUsageCard({required this.core});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final usageColor = _getUsageColor(core.usage);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: usageColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: usageColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Core ${core.coreId}',
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: core.usage),
            duration: M3Durations.medium4,
            curve: M3Curves.emphasized,
            builder: (context, value, child) {
              return Text(
                '${value.toStringAsFixed(1)}%',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: usageColor,
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: core.usage / 100),
            duration: M3Durations.medium4,
            curve: M3Curves.emphasized,
            builder: (context, value, child) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(usageColor),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Color _getUsageColor(double usage) {
    if (usage >= 90) return Colors.red;
    if (usage >= 70) return Colors.orange;
    if (usage >= 50) return Colors.amber.shade700;
    return Colors.green;
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MemoryCard extends StatelessWidget {
  final AsyncValue<MemoryInfo?> memoryInfo;

  const _MemoryCard({required this.memoryInfo});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple, Colors.pink],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.memory_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text(
                  'Memory',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            memoryInfo.when(
              data: (info) {
                if (info == null) {
                  return const Text('Failed to load');
                }
                return _buildMemoryContent(context, info);
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, s) => const Text('Error'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryContent(BuildContext context, MemoryInfo info) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final usageColor = _getUsageColor(info.usagePercentage);

    return Column(
      children: [
        // Main memory bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'RAM Usage',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: info.usagePercentage),
                    duration: M3Durations.medium4,
                    curve: M3Curves.emphasized,
                    builder: (context, value, child) {
                      return Text(
                        '${value.toStringAsFixed(1)}%',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: usageColor,
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: info.usagePercentage / 100),
                duration: M3Durations.medium4,
                curve: M3Curves.emphasized,
                builder: (context, value, child) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 12,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(usageColor),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _MemoryStat(
                    label: 'Used',
                    value: _formatBytes(info.used),
                    color: usageColor,
                  ),
                  _MemoryStat(
                    label: 'Available',
                    value: _formatBytes(info.available),
                    color: Colors.green,
                  ),
                  _MemoryStat(
                    label: 'Total',
                    value: _formatBytes(info.total),
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),

        // Swap section
        if (info.swapTotal > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Swap',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${_formatBytes(info.swapUsed)} / ${_formatBytes(info.swapTotal)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: info.swapUsed / info.swapTotal,
                    minHeight: 6,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(colorScheme.tertiary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
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
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}

class _MemoryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MemoryStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Text(
          value,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DisksCard extends StatelessWidget {
  final AsyncValue<List<DiskInfo>> diskInfo;

  const _DisksCard({required this.diskInfo});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.teal, Colors.green],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.storage_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text(
                  'Storage',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            diskInfo.when(
              data: (disks) {
                if (disks.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No disks found',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }
                return Column(
                  children: disks.map((disk) => _DiskItem(disk: disk)).toList(),
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, s) => const Text('Error loading disks'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiskItem extends StatelessWidget {
  final DiskInfo disk;

  const _DiskItem({required this.disk});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final usageColor = _getUsageColor(disk.usagePercentage);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                disk.isRemovable ? Icons.usb_rounded : Icons.storage_rounded,
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  disk.mountPoint,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: usageColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${disk.usagePercentage.toStringAsFixed(1)}%',
                  style: textTheme.labelMedium?.copyWith(
                    color: usageColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: disk.usagePercentage / 100,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(usageColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_formatBytes(disk.usedSpace)} / ${_formatBytes(disk.totalSpace)}',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                disk.fileSystem,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getUsageColor(double usage) {
    if (usage >= 90) return Colors.red;
    if (usage >= 70) return Colors.orange;
    return Colors.green;
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TB';
    }
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}

class _UsbDevicesCard extends StatelessWidget {
  final AsyncValue<List<UsbDevice>> usbDevices;

  const _UsbDevicesCard({required this.usbDevices});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange, Colors.deepOrange],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.usb_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text(
                  'USB Devices',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            usbDevices.when(
              data: (devices) {
                if (devices.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.usb_off_rounded,
                            size: 48,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No USB devices connected',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: devices
                      .map(
                        (device) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            tileColor: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.usb_rounded,
                                color: colorScheme.onPrimaryContainer,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              device.name,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${device.vendorId}:${device.productId}',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            trailing: device.mountPoint != null
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: colorScheme.tertiaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      device.mountPoint!,
                                      style: textTheme.labelSmall?.copyWith(
                                        color: colorScheme.onTertiaryContainer,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, s) => const Text('Error loading USB devices'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
