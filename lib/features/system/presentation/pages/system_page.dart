import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';

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
            title: const Text('System'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
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
                ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05),
                const SizedBox(height: 16),

                // CPU & Memory Row
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 600) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _CpuCard(cpuInfo: cpuInfo)
                                .animate()
                                .fadeIn(delay: 200.ms)
                                .slideX(begin: -0.05),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _MemoryCard(memoryInfo: memoryInfo)
                                .animate()
                                .fadeIn(delay: 300.ms)
                                .slideX(begin: 0.05),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        _CpuCard(
                          cpuInfo: cpuInfo,
                        ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.05),
                        const SizedBox(height: 16),
                        _MemoryCard(
                          memoryInfo: memoryInfo,
                        ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.05),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Disks Card
                _DisksCard(
                  diskInfo: diskInfo,
                ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.05),
                const SizedBox(height: 16),

                // USB Devices Card
                _UsbDevicesCard(
                  usbDevices: usbDevices,
                ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.05),
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
                Icon(Icons.computer, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'System Information',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            systemInfo.when(
              data: (info) {
                if (info == null) {
                  return const Text('Failed to load');
                }
                return Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    _InfoChip(
                      icon: Icons.dns,
                      label: 'Hostname',
                      value: info.hostname,
                    ),
                    _InfoChip(
                      icon: Icons.computer,
                      label: 'OS',
                      value: '${info.osName} ${info.osVersion}',
                    ),
                    _InfoChip(
                      icon: Icons.memory,
                      label: 'Arch',
                      value: info.architecture,
                    ),
                    _InfoChip(
                      icon: Icons.code,
                      label: 'Kernel',
                      value: info.kernelVersion,
                    ),
                    _InfoChip(
                      icon: Icons.schedule,
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
                Icon(Icons.speed, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'CPU',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            cpuInfo.when(
              data: (info) {
                if (info == null) {
                  return const Text('Failed to load');
                }
                final usageColor = _getUsageColor(info.usage);
                return Column(
                  children: [
                    // Usage gauge
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: CircularProgressIndicator(
                            value: info.usage / 100,
                            strokeWidth: 10,
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(usageColor),
                          ),
                        ),
                        Column(
                          children: [
                            Text(
                              '${info.usage.toStringAsFixed(1)}%',
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: usageColor,
                              ),
                            ),
                            Text('Usage', style: textTheme.bodySmall),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      info.brand,
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _MiniStat(label: 'Cores', value: '${info.cores}'),
                        _MiniStat(
                          label: 'Freq',
                          value: '${info.frequency} MHz',
                        ),
                        if (info.temperature != null)
                          _MiniStat(
                            label: 'Temp',
                            value: '${info.temperature!.toStringAsFixed(0)}°C',
                            color: _getTempColor(info.temperature!),
                          ),
                      ],
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => const Text('Error'),
            ),
          ],
        ),
      ),
    );
  }

  Color _getUsageColor(double usage) {
    if (usage >= 90) {
      return Colors.red;
    }
    if (usage >= 70) {
      return Colors.orange;
    }
    if (usage >= 50) {
      return Colors.yellow.shade700;
    }
    return Colors.green;
  }

  Color _getTempColor(double temp) {
    if (temp >= 80) {
      return Colors.red;
    }
    if (temp >= 60) {
      return Colors.orange;
    }
    return Colors.green;
  }
}

class _MemoryCard extends StatelessWidget {
  final AsyncValue<MemoryInfo?> memoryInfo;

  const _MemoryCard({required this.memoryInfo});

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
                Icon(Icons.memory, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Memory',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            memoryInfo.when(
              data: (info) {
                if (info == null) {
                  return const Text('Failed to load');
                }
                final usageColor = _getUsageColor(info.usagePercentage);
                return Column(
                  children: [
                    // Usage gauge
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: CircularProgressIndicator(
                            value: info.usagePercentage / 100,
                            strokeWidth: 10,
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(usageColor),
                          ),
                        ),
                        Column(
                          children: [
                            Text(
                              '${info.usagePercentage.toStringAsFixed(1)}%',
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: usageColor,
                              ),
                            ),
                            Text('Used', style: textTheme.bodySmall),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _MiniStat(
                          label: 'Used',
                          value: _formatBytes(info.used),
                        ),
                        _MiniStat(
                          label: 'Free',
                          value: _formatBytes(info.available),
                        ),
                        _MiniStat(
                          label: 'Total',
                          value: _formatBytes(info.total),
                        ),
                      ],
                    ),
                    if (info.swapTotal > 0) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text('Swap', style: textTheme.bodySmall),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: info.swapUsed / info.swapTotal,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatBytes(info.swapUsed)} / ${_formatBytes(info.swapTotal)}',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => const Text('Error'),
            ),
          ],
        ),
      ),
    );
  }

  Color _getUsageColor(double usage) {
    if (usage >= 90) {
      return Colors.red;
    }
    if (usage >= 70) {
      return Colors.orange;
    }
    if (usage >= 50) {
      return Colors.yellow.shade700;
    }
    return Colors.green;
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
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
                Icon(Icons.storage, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Storage',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            diskInfo.when(
              data: (disks) {
                if (disks.isEmpty) {
                  return const Text('No disks found');
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                disk.isRemovable ? Icons.usb : Icons.storage,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  disk.mountPoint,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '${disk.usagePercentage.toStringAsFixed(1)}%',
                style: textTheme.bodySmall?.copyWith(color: usageColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: disk.usagePercentage / 100,
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(usageColor),
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatBytes(disk.usedSpace)} / ${_formatBytes(disk.totalSpace)} (${disk.fileSystem})',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Color _getUsageColor(double usage) {
    if (usage >= 90) {
      return Colors.red;
    }
    if (usage >= 70) {
      return Colors.orange;
    }
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
                Icon(Icons.usb, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'USB Devices',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            usbDevices.when(
              data: (devices) {
                if (devices.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No USB devices connected',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }
                return Column(
                  children: devices
                      .map(
                        (device) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.usb,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(device.name),
                          subtitle: Text(
                            '${device.vendorId}:${device.productId}',
                          ),
                          trailing: device.mountPoint != null
                              ? Chip(label: Text(device.mountPoint!))
                              : null,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: textTheme.labelSmall),
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

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _MiniStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: textTheme.labelSmall),
      ],
    );
  }
}
