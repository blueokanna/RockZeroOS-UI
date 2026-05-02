import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/services/wallpaper_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../storage/presentation/pages/disk_management_page.dart';
import '../../../storage/presentation/providers/disk_platform_capabilities_provider.dart';

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

final hardwareInfoAllProvider = StreamProvider.autoDispose<HardwareInfo?>(
  (ref) async* {
    final api = ref.read(apiServiceProvider);
    while (true) {
      try {
        yield await api.getHardwareInfo();
      } catch (_) {
        yield null;
      }
      await Future.delayed(const Duration(seconds: 3));
    }
  },
);

class SystemPage extends ConsumerWidget {
  const SystemPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systemInfo = ref.watch(systemInfoProvider);
    final cpuInfo = ref.watch(cpuInfoProvider);
    final memoryInfo = ref.watch(memoryInfoProvider);
    final diskInfo = ref.watch(diskInfoProvider);
    final usbDevices = ref.watch(usbDevicesProvider);
    final hardwareInfo = ref.watch(hardwareInfoAllProvider);
    final diskCapabilities = ref.watch(diskPlatformCapabilitiesProvider);
    final hasWallpaper =
        ref.watch(backgroundModeProvider) == BackgroundMode.customWallpaper &&
            (ref.watch(customWallpaperPathProvider)?.isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: hasWallpaper ? Colors.transparent : null,
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
                  hardwareInfo: hardwareInfo,
                  diskCapabilities: diskCapabilities,
                ),
                const SizedBox(height: 20),

                // CPU Card with per-core usage — no .animate() since
                // StreamProvider rebuilds every 2s, re-triggering animations.
                _CpuCard(cpuInfo: cpuInfo),
                const SizedBox(height: 20),

                // Memory Card — same: avoid re-animation on stream updates
                _MemoryCard(memoryInfo: memoryInfo),
                const SizedBox(height: 20),

                // Disks Card — FutureProvider, only loads once
                _DisksCard(
                  diskInfo: diskInfo,
                ).animate().fadeIn(
                    delay: 100.ms, curve: M3Curves.emphasizedDecelerate),
                const SizedBox(height: 20),

                // USB Devices Card — FutureProvider, only loads once
                _UsbDevicesCard(
                  usbDevices: usbDevices,
                ).animate().fadeIn(
                    delay: 150.ms, curve: M3Curves.emphasizedDecelerate),
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
  final AsyncValue<HardwareInfo?> hardwareInfo;
  final AsyncValue<DiskPlatformCapabilities> diskCapabilities;

  const _SystemInfoCard({
    required this.systemInfo,
    required this.hardwareInfo,
    required this.diskCapabilities,
  });

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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'System Information',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      systemInfo.when(
                        data: (info) => Text(
                          info?.hostname ?? '',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
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
            hardwareInfo.when(
              data: (info) {
                final active = info?.noDiskPlaybackModeActive ?? false;
                final sessions = info?.noDiskPlaybackSessionCount ?? 0;
                final statusColor =
                    active ? colorScheme.error : colorScheme.primary;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        active
                            ? Icons.warning_amber_rounded
                            : Icons.verified_rounded,
                        size: 18,
                        color: statusColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          active
                              ? 'No-disk playback mode ACTIVE ($sessions session${sessions == 1 ? '' : 's'})'
                              : 'No-disk playback mode inactive',
                          style: textTheme.bodySmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            diskCapabilities.when(
              data: (capabilities) {
                final active = capabilities.readWriteOnlyMode;
                final statusColor =
                    active ? colorScheme.secondary : colorScheme.primary;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        active
                            ? Icons.lock_outline_rounded
                            : Icons.admin_panel_settings_rounded,
                        size: 18,
                        color: statusColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          active
                              ? 'Storage backend is in read-only mode for status + file access only'
                              : 'Storage backend allows full management operations',
                          style: textTheme.bodySmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            systemInfo.when(
              data: (info) {
                if (info == null) {
                  return const Text('Failed to load');
                }
                return Column(
                  children: [
                    // OS & Architecture row
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primaryContainer.withValues(alpha: 0.3),
                            colorScheme.tertiaryContainer
                                .withValues(alpha: 0.3),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _SystemInfoTile(
                              icon: Icons.laptop_chromebook_rounded,
                              label: 'Operating System',
                              value: '${info.osName} ${info.osVersion}',
                              color: colorScheme.primary,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 48,
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.3),
                          ),
                          Expanded(
                            child: _SystemInfoTile(
                              icon: Icons.developer_board_rounded,
                              label: 'Architecture',
                              value: info.architecture,
                              color: colorScheme.tertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Kernel & Uptime row — compact side-by-side layout
                    Row(
                      children: [
                        // Kernel (takes remaining space)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.code_rounded,
                                    size: 18,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Kernel',
                                        style: textTheme.labelSmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        info.kernelVersion,
                                        style: textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'monospace',
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Uptime (compact pill)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: _getUptimeColor(info.uptime)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _getUptimeColor(info.uptime)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: _getUptimeColor(info.uptime)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.schedule_rounded,
                                  size: 18,
                                  color: _getUptimeColor(info.uptime),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Uptime',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    _formatUptime(info.uptime),
                                    style: textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: _getUptimeColor(info.uptime),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Color _getUptimeColor(int seconds) {
    if (seconds >= 30 * 86400) return Colors.green; // 30+ days
    if (seconds >= 7 * 86400) return Colors.blue; // 7+ days
    if (seconds >= 86400) return Colors.orange; // 1+ day
    return Colors.grey; // < 1 day
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

/// Structured tile for system info display
class _SystemInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SystemInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
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
          _buildCoreGrid(context, info.perCoreUsage!, info.coreTypes),
        ],
      ],
    );
  }

  Widget _buildCoreGrid(BuildContext context, List<CpuCoreInfo> cores,
      List<CpuCoreArchInfo>? coreTypes) {
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
            childAspectRatio: 1.0,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: cores.length,
          itemBuilder: (context, index) {
            // Determine architecture for this core based on coreTypes
            String? archName;
            String? coreLabel;
            if (coreTypes != null && coreTypes.isNotEmpty) {
              // Map core index to architecture type
              // Typically big.LITTLE: first N cores are big (A73), rest are little (A53)
              int cumulativeCount = 0;
              var typeIndex = 0;
              for (final coreType in coreTypes) {
                cumulativeCount += coreType.count;
                if (index < cumulativeCount) {
                  archName = coreType.coreName;
                  coreLabel = _classifyCoreLabel(
                    coreType.coreName,
                    typeIndex: typeIndex,
                    totalTypes: coreTypes.length,
                  );
                  break;
                }
                typeIndex += 1;
              }
            }
            return RepaintBoundary(
              child: _CoreUsageCard(
                core: cores[index],
                archName: archName,
                coreLabel: coreLabel,
              ),
            );
          },
        );
      },
    );
  }

  String? _classifyCoreLabel(
    String rawName, {
    required int typeIndex,
    required int totalTypes,
  }) {
    final lower = rawName.toLowerCase();

    if (lower.contains('performance') || lower.contains('p-core')) {
      return 'P-core';
    }
    if (lower.contains('efficiency') || lower.contains('e-core')) {
      return 'E-core';
    }

    final match = RegExp(r'[Aa](\d+)').firstMatch(rawName);
    if (match != null) {
      final family = int.tryParse(match.group(1) ?? '');
      if (family != null) {
        return family >= 70 ? 'Big' : 'Little';
      }
    }

    if (totalTypes == 2) {
      return typeIndex == 0 ? 'P-core' : 'E-core';
    }

    return null;
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
  final String? archName;
  final String? coreLabel;

  const _CoreUsageCard({
    required this.core,
    this.archName,
    this.coreLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final usageColor = _getUsageColor(core.usage);

    final compactArch = _compactCoreName(archName);
    final detailText =
        archName != null && archName != compactArch ? archName : null;

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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Core ${core.coreId}',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (coreLabel != null || compactArch != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    coreLabel ?? compactArch!,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (detailText != null) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 14,
              child: _MarqueeText(
                text: detailText,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ),
          ],
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

  String? _compactCoreName(String? rawName) {
    if (rawName == null || rawName.isEmpty) {
      return null;
    }

    final match = RegExp(r'[Aa](\d+)').firstMatch(rawName);
    if (match != null) {
      return 'A${match.group(1)}';
    }

    final lower = rawName.toLowerCase();
    if (lower.contains('performance') || lower.contains('p-core')) {
      return 'P-core';
    }
    if (lower.contains('efficiency') || lower.contains('e-core')) {
      return 'E-core';
    }
    if (lower.contains('intel')) {
      return 'Intel';
    }
    if (lower.contains('amd')) {
      return 'AMD';
    }
    if (lower.contains('apple')) {
      return 'Apple';
    }

    return rawName.length > 14 ? '${rawName.substring(0, 14)}…' : rawName;
  }
}

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const _MarqueeText({required this.text, this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: double.infinity);

        if (textPainter.width <= constraints.maxWidth) {
          _controller.stop();
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.visible,
            style: widget.style,
          );
        }

        final gap = 24.0;
        final cycleWidth = textPainter.width + gap;
        final seconds = (cycleWidth / 28).clamp(4, 14).toDouble();
        _controller.duration = Duration(milliseconds: (seconds * 1000).round());
        if (!_controller.isAnimating) {
          _controller.repeat();
        }

        Widget textChild() => Text(
              widget.text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: widget.style,
            );

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(-cycleWidth * _controller.value, 0),
                child: child,
              );
            },
            child: Row(
              children: [
                textChild(),
                SizedBox(width: gap),
                textChild(),
              ],
            ),
          ),
        );
      },
    );
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
                  children: [
                    ...disks.map((disk) => _DiskItem(disk: disk)),
                    const SizedBox(height: 16),
                    // Storage Manager button
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const DiskManagementPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings_rounded),
                      label: const Text('Storage Manager'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
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

class _DiskItem extends ConsumerWidget {
  final DiskInfo disk;

  const _DiskItem({required this.disk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final usageColor = _getUsageColor(disk.usagePercentage);

    return InkWell(
      onTap: () {
        // Navigate to storage management page
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const DiskManagementPage(),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
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
