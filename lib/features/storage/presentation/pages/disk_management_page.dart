import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_service.dart';
import '../../../../core/services/biometric_service.dart';
import '../../../../core/services/device_discovery_service.dart';
import '../../../../core/services/filesystem_monitor_service.dart';

/// Supported file systems for formatting
const List<Map<String, dynamic>> supportedFileSystems = [
  {
    'name': 'ext4',
    'displayName': 'EXT4',
    'description': 'Linux default filesystem, stable and reliable',
    'icon': Icons.storage_rounded,
    'recommended': true,
    'category': 'linux'
  },
  {
    'name': 'xfs',
    'displayName': 'XFS',
    'description': 'High-performance filesystem, optimized for large files',
    'icon': Icons.speed_rounded,
    'recommended': false,
    'category': 'linux'
  },
  {
    'name': 'btrfs',
    'displayName': 'Btrfs',
    'description': 'Modern CoW filesystem with snapshot support',
    'icon': Icons.layers_rounded,
    'recommended': false,
    'category': 'linux'
  },
  {
    'name': 'f2fs',
    'displayName': 'F2FS',
    'description': 'Flash-optimized filesystem, ideal for SSDs',
    'icon': Icons.flash_on_rounded,
    'recommended': false,
    'category': 'linux'
  },
  {
    'name': 'ntfs',
    'displayName': 'NTFS',
    'description': 'Windows native filesystem, fully compatible',
    'icon': Icons.window_rounded,
    'recommended': true,
    'category': 'windows'
  },
  {
    'name': 'exfat',
    'displayName': 'exFAT',
    'description': 'Cross-platform compatible, Windows/Linux/Mac',
    'icon': Icons.devices_rounded,
    'recommended': true,
    'category': 'cross-platform'
  },
  {
    'name': 'fat32',
    'displayName': 'FAT32',
    'description': 'Maximum compatibility, 4GB file size limit',
    'icon': Icons.sd_card_rounded,
    'recommended': false,
    'category': 'cross-platform'
  },
];

/// Disk detail model
class DiskDetail {
  final String name;
  final String devicePath;
  final String mountPoint;
  final String fileSystem;
  final int totalSpace;
  final int availableSpace;
  final int usedSpace;
  final double usagePercentage;
  final bool isRemovable;
  final String diskType;
  final bool isMounted;
  final bool readOnly;
  final String? label;
  final String? uuid;
  final String? serial;
  final String? model;

  DiskDetail({
    required this.name,
    required this.devicePath,
    required this.mountPoint,
    required this.fileSystem,
    required this.totalSpace,
    required this.availableSpace,
    required this.usedSpace,
    required this.usagePercentage,
    required this.isRemovable,
    required this.diskType,
    required this.isMounted,
    required this.readOnly,
    this.label,
    this.uuid,
    this.serial,
    this.model,
  });

  factory DiskDetail.fromJson(Map<String, dynamic> json) {
    return DiskDetail(
      name: json['name'] ?? '',
      devicePath: json['device_path'] ?? json['name'] ?? '',
      mountPoint: json['mount_point'] ?? '',
      fileSystem: json['file_system'] ?? 'Unknown',
      totalSpace: json['total_space'] ?? 0,
      availableSpace: json['available_space'] ?? 0,
      usedSpace: json['used_space'] ?? 0,
      usagePercentage: (json['usage_percentage'] ?? 0).toDouble(),
      isRemovable: json['is_removable'] ?? false,
      diskType: json['disk_type'] ?? 'Unknown',
      isMounted:
          json['is_mounted'] ?? (json['mount_point']?.isNotEmpty ?? false),
      readOnly: json['read_only'] ?? false,
      label: json['label'],
      uuid: json['uuid'],
      serial: json['serial'],
      model: json['model'],
    );
  }
}

final allDisksDetailProvider = FutureProvider<List<DiskDetail>>((ref) async {
  final device = ref.watch(connectedDeviceProvider);
  if (device == null) {
    throw Exception('Not connected to any device');
  }
  final api = ref.read(apiServiceProvider);
  final response = await api.get('/api/v1/disk/list');
  final List<dynamic> data = response.data;
  return data.map((e) => DiskDetail.fromJson(e)).toList();
});

class DiskManagementPage extends ConsumerStatefulWidget {
  const DiskManagementPage({super.key});

  @override
  ConsumerState<DiskManagementPage> createState() => _DiskManagementPageState();
}

class _DiskManagementPageState extends ConsumerState<DiskManagementPage> {
  bool _isScanning = false;
  Timer? _autoRefreshTimer;
  StreamSubscription<FileSystemEvent>? _fsEventSubscription;

  @override
  void initState() {
    super.initState();

    // Auto refresh: refresh disk status every 5 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        ref.invalidate(allDisksDetailProvider);
      }
    });

    // Listen to filesystem events (disk related)
    final monitor = ref.read(fileSystemMonitorProvider);
    _fsEventSubscription = monitor.listenToDiskEvents().listen((event) {
      debugPrint('[DiskManagement] Received FS event: $event');
      if (mounted) {
        // Immediately refresh disk info
        ref.invalidate(allDisksDetailProvider);

        // Show notification
        String message = '';
        switch (event.type) {
          case FileSystemEventType.diskFormatted:
            message = 'Disk ${event.diskName} formatted';
            break;
          case FileSystemEventType.diskMounted:
            message = 'Disk ${event.diskName} mounted';
            break;
          case FileSystemEventType.diskUnmounted:
            message = 'Disk ${event.diskName} unmounted';
            break;
          default:
            break;
        }

        if (message.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _fsEventSubscription?.cancel();
    super.dispose();
  }

  Future<void> _scanDisks() async {
    setState(() => _isScanning = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.post('/api/v1/disk/scan');
      ref.invalidate(allDisksDetailProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Disk scan completed'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Scan failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final disksAsync = ref.watch(allDisksDetailProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Disk Management'),
        centerTitle: true,
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: _scanDisks,
              tooltip: 'Scan for new disks',
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(allDisksDetailProvider),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: disksAsync.when(
        data: (disks) {
          final filteredDisks = disks.where((disk) {
            final name = disk.name.toLowerCase();
            final mountPoint = disk.mountPoint.toLowerCase();
            final fileSystem = disk.fileSystem.toLowerCase();
            if (name.contains('boot0') ||
                name.contains('boot1') ||
                name.contains('rpmb')) {
              return false;
            }
            if (mountPoint == '/boot' || mountPoint.startsWith('/boot/')) {
              return false;
            }
            if (fileSystem == 'vfat' ||
                fileSystem == 'fat32' ||
                fileSystem == 'fat16') {
              return false;
            }
            if (mountPoint.startsWith('/sys') ||
                mountPoint.startsWith('/proc') ||
                mountPoint.startsWith('/run') ||
                mountPoint.contains('/snap/') ||
                fileSystem == 'squashfs' ||
                fileSystem == 'tmpfs' ||
                fileSystem == 'devtmpfs' ||
                fileSystem == 'overlay') {
              return false;
            }
            return true;
          }).toList();

          if (filteredDisks.isEmpty) {
            return _buildEmptyState(colorScheme, textTheme);
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(allDisksDetailProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredDisks.length,
              itemBuilder: (context, index) => _DiskCard(
                disk: filteredDisks[index],
                onRefresh: () => ref.invalidate(allDisksDetailProvider),
              ),
            ),
          );
        },
        loading: () => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Loading disk information...',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        error: (error, stack) =>
            _buildErrorState(colorScheme, textTheme, error),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.storage_rounded,
              size: 64, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            'No disks found',
            style: textTheme.titleMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect external storage or check system configuration',
            style: textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _scanDisks,
            icon: const Icon(Icons.search_rounded),
            label: const Text('Scan Disks'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
      ColorScheme colorScheme, TextTheme textTheme, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Failed to load disk information',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => ref.invalidate(allDisksDetailProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiskCard extends ConsumerWidget {
  final DiskDetail disk;
  final VoidCallback onRefresh;

  const _DiskCard({required this.disk, required this.onRefresh});

  // Linux native filesystems
  static const Set<String> linuxNativeFileSystems = {
    'ext4',
    'ext3',
    'ext2',
    'xfs',
    'btrfs',
    'f2fs',
    'zfs',
    'reiserfs',
    'jfs',
    'nilfs2',
    'bcachefs',
  };

  // Linux fully compatible cross-platform filesystems (recommended)
  static const Set<String> crossPlatformFileSystems = {
    'ntfs', // Windows native, fully supported on Linux (via ntfs-3g)
    'exfat', // Cross-platform, Windows/Linux/Mac compatible
    'fat32', // Maximum compatibility
    'vfat', // FAT32 Linux name
  };

  // Other compatible filesystems
  static const Set<String> otherCompatibleFileSystems = {
    'fat16',
    'hfsplus', // Mac filesystem
    'udf', // Optical disc filesystem
  };

  // Get filesystem category and recommendation
  Map<String, dynamic> _getFileSystemInfo() {
    final fs = disk.fileSystem.toLowerCase();

    if (linuxNativeFileSystems.contains(fs)) {
      return {
        'category': 'Linux Native',
        'color': Colors.green,
        'icon': Icons.check_circle_rounded,
        'needsFormat': false,
        'description': 'Linux native filesystem, best performance',
      };
    }

    if (fs == 'ntfs') {
      return {
        'category': 'Windows Compatible',
        'color': Colors.blue,
        'icon': Icons.window_rounded,
        'needsFormat': false,
        'description': 'Windows native, fully supported on Linux',
      };
    }

    if (fs == 'exfat') {
      return {
        'category': 'Cross-platform',
        'color': Colors.purple,
        'icon': Icons.devices_rounded,
        'needsFormat': false,
        'description': 'Windows/Linux/Mac compatible',
      };
    }

    if (crossPlatformFileSystems.contains(fs) ||
        otherCompatibleFileSystems.contains(fs)) {
      return {
        'category': 'Compatible',
        'color': Colors.orange,
        'icon': Icons.info_rounded,
        'needsFormat': false,
        'description': 'Compatible filesystem',
      };
    }

    return {
      'category': 'Unsupported',
      'color': Colors.red,
      'icon': Icons.warning_rounded,
      'needsFormat': true,
      'description': 'Needs formatting',
    };
  }

  // Check if non-Linux native filesystem (but compatible)
  bool _isNonLinuxNativeFs() {
    final fs = disk.fileSystem.toLowerCase();
    if (fs.isEmpty || fs == 'unknown') return false;
    return !linuxNativeFileSystems.contains(fs) &&
        (crossPlatformFileSystems.contains(fs) ||
            otherCompatibleFileSystems.contains(fs));
  }

  // Check if completely unsupported filesystem
  bool _isUnsupportedFs() {
    final fs = disk.fileSystem.toLowerCase();
    if (fs.isEmpty || fs == 'unknown') return false;
    return !linuxNativeFileSystems.contains(fs) &&
        !crossPlatformFileSystems.contains(fs) &&
        !otherCompatibleFileSystems.contains(fs);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isMounted = disk.isMounted &&
        disk.mountPoint.isNotEmpty &&
        disk.mountPoint != 'Not mounted';
    final isUnpartitioned =
        disk.fileSystem == 'Unknown' || disk.fileSystem.isEmpty;
    final isNonLinuxNative = _isNonLinuxNativeFs();
    final isUnsupported = _isUnsupportedFs();

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
                          : (isUnpartitioned || isUnsupported
                              ? colorScheme.errorContainer
                              : (isNonLinuxNative
                                  ? colorScheme.tertiaryContainer
                                  : colorScheme.surfaceContainerHighest)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getDiskIcon(),
                      color: isMounted
                          ? colorScheme.onPrimaryContainer
                          : (isUnpartitioned || isUnsupported
                              ? colorScheme.onErrorContainer
                              : (isNonLinuxNative
                                  ? colorScheme.onTertiaryContainer
                                  : colorScheme.onSurfaceVariant)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          disk.label ?? disk.name,
                          style: textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          disk.devicePath,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(context, isMounted, isUnpartitioned,
                      isNonLinuxNative, isUnsupported),
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
                        _getUsageColor(disk.usagePercentage)),
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
              ] else if (!isUnpartitioned) ...[
                const SizedBox(height: 12),
                Text('Capacity: ${_formatBytes(disk.totalSpace)}',
                    style: textTheme.bodyMedium),
                // Show filesystem info
                () {
                  final fsInfo = _getFileSystemInfo();
                  final needsFormat = fsInfo['needsFormat'] as bool;

                  if (needsFormat) {
                    // Unsupported filesystem
                    return Column(
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(fsInfo['icon'] as IconData,
                                  color: fsInfo['color'] as Color, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${disk.fileSystem.toUpperCase()} ${fsInfo['description']}',
                                  style: textTheme.bodySmall?.copyWith(
                                      color: fsInfo['color'] as Color),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  } else if (fsInfo['category'] == 'Windows Compatible' ||
                      fsInfo['category'] == 'Cross-platform') {
                    // Windows/cross-platform filesystem - show as usable
                    return Column(
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (fsInfo['color'] as Color)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: (fsInfo['color'] as Color)
                                  .withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(fsInfo['icon'] as IconData,
                                  color: fsInfo['color'] as Color, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${disk.fileSystem.toUpperCase()} - ${fsInfo['description']}',
                                  style: textTheme.bodySmall?.copyWith(
                                      color: fsInfo['color'] as Color),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                }(),
              ] else ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_rounded,
                          color: colorScheme.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This disk is not partitioned, tap to initialize',
                          style: textTheme.bodySmall
                              ?.copyWith(color: colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (disk.fileSystem.isNotEmpty &&
                      disk.fileSystem != 'Unknown' &&
                      disk.fileSystem != 'unknown')
                    Chip(
                      label: Text(disk.fileSystem.toUpperCase()),
                      labelStyle: textTheme.labelSmall,
                      visualDensity: VisualDensity.compact,
                    )
                  else if (isUnpartitioned)
                    Chip(
                      avatar: Icon(Icons.warning_rounded,
                          size: 14, color: colorScheme.error),
                      label: const Text('Unformatted'),
                      labelStyle: textTheme.labelSmall?.copyWith(
                        color: colorScheme.error,
                      ),
                      visualDensity: VisualDensity.compact,
                      backgroundColor:
                          colorScheme.errorContainer.withValues(alpha: 0.3),
                    ),
                  Chip(
                    label: Text(disk.diskType),
                    labelStyle: textTheme.labelSmall,
                    visualDensity: VisualDensity.compact,
                  ),
                  if (disk.isRemovable)
                    Chip(
                      avatar: Icon(Icons.usb_rounded,
                          size: 16, color: colorScheme.primary),
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

  Widget _buildStatusChip(BuildContext context, bool isMounted,
      bool isUnpartitioned, bool isNonLinuxNative, bool isUnsupported) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (isUnpartitioned) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Unpartitioned',
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onErrorContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (isUnsupported) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Unsupported',
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onErrorContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (!isMounted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isNonLinuxNative
              ? colorScheme.tertiaryContainer
              : colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          isNonLinuxNative ? 'Non-native' : 'Unmounted',
          style: textTheme.labelSmall?.copyWith(
            color: isNonLinuxNative
                ? colorScheme.onTertiaryContainer
                : colorScheme.onTertiaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Mounted',
        style: textTheme.labelSmall?.copyWith(
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  IconData _getDiskIcon() {
    if (disk.isRemovable) {
      return Icons.usb_rounded;
    }
    if (disk.diskType.contains('SSD') || disk.diskType.contains('NVMe')) {
      return Icons.memory_rounded;
    }
    return Icons.storage_rounded;
  }

  Color _getUsageColor(double usage) {
    if (usage >= 90) {
      return Colors.red;
    }
    if (usage >= 70) {
      return Colors.orange;
    }
    if (usage >= 50) {
      return Colors.amber.shade700;
    }
    return Colors.green;
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
    }
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  void _showDiskDetails(BuildContext context, WidgetRef ref) {
    // If disk is mounted, show details page directly
    final isMounted = disk.isMounted &&
        disk.mountPoint.isNotEmpty &&
        disk.mountPoint != 'Not mounted';

    if (isMounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) =>
            _DiskDetailsSheet(disk: disk, onRefresh: onRefresh),
      );
      return;
    }

    // Check disk status
    final isRawDisk = _isRawDisk();
    final isNonLinuxNative = _isNonLinuxNativeFs();
    final isUnsupported = _isUnsupportedFs();

    // If raw disk (no partition, no filesystem), show initialize dialog
    if (isRawDisk) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => _InitializeDiskSheet(
          disk: disk,
          onComplete: onRefresh,
          isReformat: false,
        ),
      );
    } else if (isUnsupported) {
      // Unsupported filesystem, needs formatting
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => _InitializeDiskSheet(
          disk: disk,
          onComplete: onRefresh,
          isReformat: true,
        ),
      );
    } else if (isNonLinuxNative) {
      // Non-Linux native filesystem, can mount or format
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => _NonLinuxFsSheet(
          disk: disk,
          onRefresh: onRefresh,
        ),
      );
    } else {
      // Normal Linux filesystem, unmounted, show details/mount page
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) =>
            _DiskDetailsSheet(disk: disk, onRefresh: onRefresh),
      );
    }
  }

  /// Check if raw disk (no partition, no filesystem)
  bool _isRawDisk() {
    final fs = disk.fileSystem.toLowerCase();
    return fs.isEmpty || fs == 'unknown';
  }
}

class _InitializeDiskSheet extends ConsumerStatefulWidget {
  final DiskDetail disk;
  final VoidCallback onComplete;
  final bool isReformat;

  const _InitializeDiskSheet({
    required this.disk,
    required this.onComplete,
    this.isReformat = false,
  });

  @override
  ConsumerState<_InitializeDiskSheet> createState() =>
      _InitializeDiskSheetState();
}

class _InitializeDiskSheetState extends ConsumerState<_InitializeDiskSheet> {
  String _selectedFs = 'ext4';
  final _labelController = TextEditingController();
  bool _isInitializing = false;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _initializeDisk() async {
    // Biometric authentication first
    final biometricService = ref.read(biometricServiceProvider);
    final authenticated = await biometricService.authenticate(
      reason: 'Authentication required to initialize disk',
    );

    if (!authenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authentication failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isInitializing = true);
    try {
      final api = ref.read(apiServiceProvider);

      if (widget.isReformat) {
        // If reformatting an existing partition
        // First check if it's a whole disk device
        final devicePath = widget.disk.devicePath;
        final isWholeDisk = _isWholeDiskDevice(devicePath);

        if (isWholeDisk) {
          // Whole disk device, use initialize
          await api.post('/api/v1/disk/initialize', data: {
            'device': widget.disk.devicePath,
            'file_system': _selectedFs,
            if (_labelController.text.isNotEmpty)
              'label': _labelController.text,
            'partition_table': 'gpt',
          });
        } else {
          // Partition device, use format
          await api.post('/api/v1/disk/format', data: {
            'device': widget.disk.devicePath,
            'file_system': _selectedFs,
            if (_labelController.text.isNotEmpty)
              'label': _labelController.text,
          });
        }
      } else {
        // New disk initialization
        await api.post('/api/v1/disk/initialize', data: {
          'device': widget.disk.devicePath,
          'file_system': _selectedFs,
          if (_labelController.text.isNotEmpty) 'label': _labelController.text,
          'partition_table': 'gpt',
        });
      }

      if (mounted) {
        // Emit filesystem event
        final monitor = ref.read(fileSystemMonitorProvider);
        monitor.emitDiskFormatted(
          widget.disk.name,
          metadata: {
            'device': widget.disk.devicePath,
            'filesystem': _selectedFs,
            'label': _labelController.text,
          },
        );

        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isReformat
                ? 'Disk formatted, refreshing...'
                : 'Disk initialized, refreshing...'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        // Wait for filesystem info to update before refresh
        await Future.delayed(const Duration(milliseconds: 2000));
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${widget.isReformat ? "Format" : "Initialize"} failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  bool _isWholeDiskDevice(String devicePath) {
    final name = devicePath.split('/').last;
    if (name.startsWith('sd') && name.length == 3) return true;
    if (name.startsWith('vd') && name.length == 3) return true;
    if (name.startsWith('hd') && name.length == 3) return true;
    if (RegExp(r'^nvme\d+n\d+$').hasMatch(name)) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = widget.isReformat ? 'Format Disk' : 'Initialize Disk';
    final warningText = widget.isReformat
        ? 'Warning: This will erase all data on the disk! Current filesystem: ${widget.disk.fileSystem.toUpperCase()}'
        : 'Warning: This will erase all data on the disk!';

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
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
                  Icon(
                      widget.isReformat
                          ? Icons.format_paint_rounded
                          : Icons.build_rounded,
                      color: colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
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
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_rounded, color: colorScheme.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            warningText,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _InfoRow(
                    icon: Icons.storage_rounded,
                    label: 'Device',
                    value: widget.disk.devicePath,
                  ),
                  _InfoRow(
                    icon: Icons.sd_storage_rounded,
                    label: 'Capacity',
                    value: _formatBytes(widget.disk.totalSpace),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Select Filesystem',
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...supportedFileSystems.map((fs) {
                    final fsName = fs['name'] as String;
                    final isSelected = _selectedFs == fsName;
                    return ListTile(
                      leading: Icon(
                        fs['icon'] as IconData,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      title: Row(
                        children: [
                          Text(fs['displayName'] as String),
                          if (fs['recommended'] == true) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Recommended',
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(fs['description'] as String),
                      trailing: isSelected
                          ? Icon(Icons.check_circle, color: colorScheme.primary)
                          : null,
                      selected: isSelected,
                      onTap: () => setState(() => _selectedFs = fsName),
                    );
                  }),
                  const SizedBox(height: 24),
                  Text(
                    'Disk Label (optional)',
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _labelController,
                    decoration: const InputDecoration(
                      hintText: 'Enter disk label',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label_rounded),
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _isInitializing ? null : _initializeDisk,
                    icon: _isInitializing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(widget.isReformat
                            ? Icons.format_paint_rounded
                            : Icons.build_rounded),
                    label: Text(_isInitializing
                        ? (widget.isReformat
                            ? 'Formatting...'
                            : 'Initializing...')
                        : (widget.isReformat
                            ? 'Format Disk'
                            : 'Initialize Disk')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      backgroundColor: colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
    }
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

class _DiskDetailsSheet extends ConsumerStatefulWidget {
  final DiskDetail disk;
  final VoidCallback onRefresh;

  const _DiskDetailsSheet({required this.disk, required this.onRefresh});

  @override
  ConsumerState<_DiskDetailsSheet> createState() => _DiskDetailsSheetState();
}

class _DiskDetailsSheetState extends ConsumerState<_DiskDetailsSheet> {
  bool _isLoading = false;

  Future<void> _mountDisk() async {
    // Check if unpartitioned whole disk device
    final devicePath = widget.disk.devicePath;
    final isWholeDisk = _isWholeDiskDevice(devicePath);
    final hasNoFileSystem = widget.disk.fileSystem.isEmpty ||
        widget.disk.fileSystem == 'Unknown' ||
        widget.disk.fileSystem == 'unknown';

    if (isWholeDisk && hasNoFileSystem) {
      // Show initialize dialog
      if (mounted) {
        Navigator.pop(context); // Close details page first
        // Wait for animation to complete before showing dialog
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          _showInitializeDialog();
        }
      }
      return;
    }

    // Show mount options dialog (don't close details page, show on top)
    if (mounted) {
      _showMountOptionsDialog();
    }
  }

  bool _isWholeDiskDevice(String devicePath) {
    // Check if whole disk device (e.g. /dev/sdb) not partition (e.g. /dev/sdb1)
    final name = devicePath.split('/').last;
    // sda, sdb, nvme0n1 are whole disks; sda1, sdb1, nvme0n1p1 are partitions
    if (name.startsWith('sd') && name.length == 3) return true;
    if (name.startsWith('vd') && name.length == 3) return true;
    if (name.startsWith('hd') && name.length == 3) return true;
    if (RegExp(r'^nvme\d+n\d+$').hasMatch(name)) return true;
    return false;
  }

  void _showInitializeDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _InitializeDiskSheet(
        disk: widget.disk,
        onComplete: widget.onRefresh,
      ),
    );
  }

  void _showMountOptionsDialog() {
    // Use showModalBottomSheet instead of showDialog, better for mobile
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _MountDiskDialog(
          disk: widget.disk,
          onComplete: () {
            Navigator.pop(context); // Close mount dialog
            Navigator.pop(context); // Close details sheet
            widget.onRefresh();
          },
        ),
      ),
    );
  }

  Future<void> _unmountDisk() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.post('/api/v1/disk/unmount',
          data: {'device': widget.disk.devicePath});
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Disk unmounted, refreshing...'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2)),
        );
        // Wait for unmount to complete before refresh
        await Future.delayed(const Duration(milliseconds: 1000));
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Unmount failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _ejectDisk() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.post(
          '/api/v1/disk/eject/${Uri.encodeComponent(widget.disk.devicePath)}');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Disk ejected'), backgroundColor: Colors.green),
        );
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Eject failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showFormatDialog() {
    // Use showModalBottomSheet instead of showDialog
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false, // Prevent accidental close
      builder: (context) => _FormatDiskDialog(
        disk: widget.disk,
        onComplete: () {
          Navigator.pop(context); // Close format dialog
          Navigator.pop(context); // Close details sheet
          widget.onRefresh();
        },
      ),
    );
  }

  void _showRenameDialog() {
    showDialog(
      context: context,
      builder: (context) => _RenameDiskDialog(
        disk: widget.disk,
        onComplete: () {
          Navigator.pop(context);
          widget.onRefresh();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isMounted = widget.disk.isMounted &&
        widget.disk.mountPoint.isNotEmpty &&
        widget.disk.mountPoint != 'Not mounted';

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
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
                      widget.disk.label ?? widget.disk.name,
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
                    value: isMounted ? widget.disk.mountPoint : 'Not mounted',
                  ),
                  _InfoRow(
                    icon: Icons.description_rounded,
                    label: 'Filesystem',
                    value: widget.disk.fileSystem,
                  ),
                  _InfoRow(
                    icon: Icons.category_rounded,
                    label: 'Type',
                    value: widget.disk.diskType,
                  ),
                  _InfoRow(
                    icon: Icons.storage_rounded,
                    label: 'Total Capacity',
                    value: _formatBytes(widget.disk.totalSpace),
                  ),
                  if (isMounted) ...[
                    _InfoRow(
                      icon: Icons.pie_chart_rounded,
                      label: 'Used',
                      value: _formatBytes(widget.disk.usedSpace),
                    ),
                    _InfoRow(
                      icon: Icons.check_circle_rounded,
                      label: 'Available',
                      value: _formatBytes(widget.disk.availableSpace),
                    ),
                  ],
                  if (widget.disk.uuid != null)
                    _InfoRow(
                      icon: Icons.fingerprint_rounded,
                      label: 'UUID',
                      value: widget.disk.uuid!,
                    ),
                  if (widget.disk.model != null)
                    _InfoRow(
                      icon: Icons.info_rounded,
                      label: 'Model',
                      value: widget.disk.model!,
                    ),
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
                      onPressed: _isLoading ? null : _mountDisk,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_needsInitialization()
                              ? Icons.build_rounded
                              : Icons.play_arrow_rounded),
                      label: Text(_needsInitialization()
                          ? 'Initialize Disk'
                          : 'Mount Disk'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        backgroundColor: _needsInitialization()
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                    if (_needsInitialization()) ...[
                      const SizedBox(height: 8),
                      Text(
                        'This disk is not partitioned or formatted, needs initialization',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 12),
                  ] else ...[
                    FilledButton.tonalIcon(
                      onPressed: _isLoading ? null : _unmountDisk,
                      icon: const Icon(Icons.eject_rounded),
                      label: const Text('Unmount Disk'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: _showRenameDialog,
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Rename'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (widget.disk.isRemovable) ...[
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _ejectDisk,
                      icon: const Icon(Icons.eject_rounded),
                      label: const Text('Safely Eject'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: _showFormatDialog,
                    icon: Icon(Icons.format_paint_rounded,
                        color: colorScheme.error),
                    label: Text('Format',
                        style: TextStyle(color: colorScheme.error)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: BorderSide(color: colorScheme.error),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
    }
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  bool _needsInitialization() {
    final devicePath = widget.disk.devicePath;
    final isWholeDisk = _isWholeDiskDevice(devicePath);
    final hasNoFileSystem = widget.disk.fileSystem.isEmpty ||
        widget.disk.fileSystem == 'Unknown' ||
        widget.disk.fileSystem == 'unknown';
    return isWholeDisk && hasNoFileSystem;
  }
}

/// Mount disk dialog - supports filesystem type selection
class _MountDiskDialog extends ConsumerStatefulWidget {
  final DiskDetail disk;
  final VoidCallback onComplete;

  const _MountDiskDialog({required this.disk, required this.onComplete});

  @override
  ConsumerState<_MountDiskDialog> createState() => _MountDiskDialogState();
}

class _MountDiskDialogState extends ConsumerState<_MountDiskDialog> {
  String _selectedFs = 'auto';
  final _mountPointController = TextEditingController();
  bool _isMounting = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill filesystem type
    if (widget.disk.fileSystem.isNotEmpty &&
        widget.disk.fileSystem != 'Unknown' &&
        widget.disk.fileSystem != 'unknown') {
      _selectedFs = widget.disk.fileSystem.toLowerCase();
    }
    // Pre-fill mount point
    _mountPointController.text =
        '/mnt/${widget.disk.label ?? widget.disk.name}';
  }

  @override
  void dispose() {
    _mountPointController.dispose();
    super.dispose();
  }

  Future<void> _mountDisk() async {
    setState(() => _isMounting = true);
    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.post('/api/v1/disk/mount', data: {
        'device': widget.disk.devicePath,
        'mount_point': _mountPointController.text,
        if (_selectedFs != 'auto') 'file_system': _selectedFs,
      });
      if (mounted) {
        Navigator.pop(context);
        final isAlreadyMounted = response.data['already_mounted'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAlreadyMounted
                ? 'Disk already mounted at ${response.data['mount_point']}'
                : 'Disk mounted, refreshing...'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        // Wait for mount to complete before refresh
        await Future.delayed(const Duration(milliseconds: 1000));
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Mount failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isMounting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Filesystem options
    final fsOptions = [
      {
        'name': 'auto',
        'displayName': 'Auto Detect',
        'description': 'Let system auto-detect filesystem'
      },
      ...supportedFileSystems,
    ];

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.primaryContainer,
                          colorScheme.primaryContainer.withValues(alpha: 0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.play_arrow_rounded,
                        color: colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Mount Disk',
                      style: textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Disk info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('Disk Info',
                            style: textTheme.labelMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Device: ${widget.disk.devicePath}',
                        style: textTheme.bodySmall),
                    Text('Capacity: ${_formatBytes(widget.disk.totalSpace)}',
                        style: textTheme.bodySmall),
                    if (widget.disk.fileSystem.isNotEmpty &&
                        widget.disk.fileSystem != 'Unknown')
                      Text(
                          'Detected filesystem: ${widget.disk.fileSystem.toUpperCase()}',
                          style: textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Filesystem selection
              Text('Filesystem Type',
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedFs,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.storage_rounded),
                ),
                items: fsOptions
                    .map((fs) => DropdownMenuItem(
                          value: fs['name'] as String,
                          child: Row(
                            children: [
                              Text(fs['displayName'] as String),
                              if (fs['name'] == 'auto') ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('Recommended',
                                      style: textTheme.labelSmall?.copyWith(
                                        color: colorScheme.onPrimaryContainer,
                                      )),
                                ),
                              ],
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedFs = v);
                },
              ),
              const SizedBox(height: 16),

              // Mount point
              Text('Mount Point',
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _mountPointController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.folder_rounded),
                  hintText: '/mnt/disk_name',
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _isMounting ? null : _mountDisk,
                      icon: _isMounting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(_isMounting ? 'Mounting...' : 'Mount'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
    }
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

class _FormatDiskDialog extends ConsumerStatefulWidget {
  final DiskDetail disk;
  final VoidCallback onComplete;

  const _FormatDiskDialog({required this.disk, required this.onComplete});

  @override
  ConsumerState<_FormatDiskDialog> createState() => _FormatDiskDialogState();
}

class _FormatDiskDialogState extends ConsumerState<_FormatDiskDialog> {
  String _selectedFs = 'ext4';
  final _labelController = TextEditingController();
  bool _isFormatting = false;
  bool _confirmed = false;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _formatDisk() async {
    if (!_confirmed) {
      setState(() => _confirmed = true);
      return;
    }
    setState(() => _isFormatting = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.post('/api/v1/disk/format', data: {
        'device': widget.disk.devicePath,
        'file_system': _selectedFs,
        if (_labelController.text.isNotEmpty) 'label': _labelController.text,
      });

      // Force cleanup all caches after format to ensure accurate storage calculation
      try {
        await api.post('/api/v1/storage-management/force-cleanup');
        debugPrint('[DiskFormat] Cache cleanup completed');
      } catch (e) {
        debugPrint('[DiskFormat] Cache cleanup failed (non-fatal): $e');
      }

      if (mounted) {
        // Emit disk format event to notify all listeners (including FilesPage)
        final monitor = ref.read(fileSystemMonitorProvider);
        monitor.emitDiskFormatted(
          widget.disk.name,
          metadata: {
            'devicePath': widget.disk.devicePath,
            'fileSystem': _selectedFs,
          },
        );

        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Format successful, refreshing...'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        // Wait for filesystem info to update before refresh
        await Future.delayed(const Duration(milliseconds: 2000));
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Format failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFormatting = false);
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
    }
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.warning_rounded,
                        color: colorScheme.onErrorContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Format Disk',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.error,
                      ),
                    ),
                  ),
                  if (!_confirmed)
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              if (!_confirmed) ...[
                // Warning info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.error.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: colorScheme.error, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Dangerous Operation Warning',
                              style: textTheme.titleMedium?.copyWith(
                                color: colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Are you sure you want to format ${widget.disk.label ?? widget.disk.name}?',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '⚠️ This will permanently erase all data on the disk!\n⚠️ This operation cannot be undone!',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Disk Info:',
                                style: textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                )),
                            const SizedBox(height: 4),
                            Text('Device: ${widget.disk.devicePath}',
                                style: textTheme.bodySmall),
                            Text(
                                'Capacity: ${_formatBytes(widget.disk.totalSpace)}',
                                style: textTheme.bodySmall),
                            if (widget.disk.fileSystem.isNotEmpty)
                              Text(
                                  'Current filesystem: ${widget.disk.fileSystem}',
                                  style: textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Format options
                Text('Select Filesystem',
                    style: textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedFs,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.storage_rounded),
                  ),
                  items: supportedFileSystems
                      .map((fs) => DropdownMenuItem(
                            value: fs['name'] as String,
                            child: Row(
                              children: [
                                Icon(fs['icon'] as IconData, size: 20),
                                const SizedBox(width: 8),
                                Text(fs['displayName'] as String),
                                if (fs['recommended'] == true) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('Recommended',
                                        style: textTheme.labelSmall?.copyWith(
                                          color: colorScheme.onPrimaryContainer,
                                        )),
                                  ),
                                ],
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedFs = v);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text('Disk Label (optional)',
                    style: textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _labelController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.label_rounded),
                    hintText: 'e.g. MyDisk',
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  if (_confirmed)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isFormatting
                            ? null
                            : () => setState(() => _confirmed = false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        child: const Text('Back'),
                      ),
                    )
                  else
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _isFormatting ? null : _formatDisk,
                      icon: _isFormatting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(_confirmed
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded),
                      label: Text(_isFormatting
                          ? 'Formatting...'
                          : (_confirmed ? 'Confirm Format' : 'Continue')),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: colorScheme.error,
                      ),
                    ),
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

class _RenameDiskDialog extends ConsumerStatefulWidget {
  final DiskDetail disk;
  final VoidCallback onComplete;

  const _RenameDiskDialog({required this.disk, required this.onComplete});

  @override
  ConsumerState<_RenameDiskDialog> createState() => _RenameDiskDialogState();
}

class _RenameDiskDialogState extends ConsumerState<_RenameDiskDialog> {
  final _labelController = TextEditingController();
  bool _isRenaming = false;

  @override
  void initState() {
    super.initState();
    _labelController.text = widget.disk.label ?? '';
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _renameDisk() async {
    if (_labelController.text.isEmpty) {
      return;
    }
    setState(() => _isRenaming = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.post('/api/v1/disk/rename', data: {
        'device': widget.disk.devicePath,
        'new_label': _labelController.text,
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Rename successful'),
              backgroundColor: Colors.green),
        );
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Rename failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRenaming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename Disk'),
      content: TextField(
        controller: _labelController,
        decoration: const InputDecoration(
          labelText: 'New Label',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isRenaming ? null : _renameDisk,
          child: _isRenaming
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirm'),
        ),
      ],
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
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
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

/// Non-Linux native filesystem handling dialog
class _NonLinuxFsSheet extends ConsumerStatefulWidget {
  final DiskDetail disk;
  final VoidCallback onRefresh;

  const _NonLinuxFsSheet({required this.disk, required this.onRefresh});

  @override
  ConsumerState<_NonLinuxFsSheet> createState() => _NonLinuxFsSheetState();
}

class _NonLinuxFsSheetState extends ConsumerState<_NonLinuxFsSheet> {
  bool _isMounting = false;

  Future<void> _mountAsIs() async {
    setState(() => _isMounting = true);
    try {
      final api = ref.read(apiServiceProvider);
      final mountPoint = '/mnt/${widget.disk.label ?? widget.disk.name}';
      await api.post('/api/v1/disk/mount', data: {
        'device': widget.disk.devicePath,
        'mount_point': mountPoint,
        'file_system': widget.disk.fileSystem.toLowerCase(),
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Disk mounted successfully'),
              backgroundColor: Colors.green),
        );
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Mount failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isMounting = false);
      }
    }
  }

  void _showFormatDialog() {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _InitializeDiskSheet(
        disk: widget.disk,
        onComplete: widget.onRefresh,
        isReformat: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.7,
      expand: false,
      builder: (context, scrollController) => Container(
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
                  Icon(Icons.info_rounded, color: colorScheme.tertiary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Non-Linux Native Filesystem',
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
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.storage_rounded,
                                color: colorScheme.tertiary, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Detected ${widget.disk.fileSystem.toUpperCase()} filesystem',
                              style: textTheme.titleSmall?.copyWith(
                                color: colorScheme.tertiary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This filesystem is not Linux native. You can mount it directly or format to Linux native format (e.g. EXT4, XFS) for better performance and compatibility.',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _InfoRow(
                    icon: Icons.storage_rounded,
                    label: 'Device',
                    value: widget.disk.devicePath,
                  ),
                  _InfoRow(
                    icon: Icons.description_rounded,
                    label: 'Current Filesystem',
                    value: widget.disk.fileSystem.toUpperCase(),
                  ),
                  _InfoRow(
                    icon: Icons.sd_storage_rounded,
                    label: 'Capacity',
                    value: _formatBytes(widget.disk.totalSpace),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isMounting ? null : _mountAsIs,
                    icon: _isMounting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(_isMounting ? 'Mounting...' : 'Mount Directly'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _showFormatDialog,
                    icon: Icon(Icons.format_paint_rounded,
                        color: colorScheme.error),
                    label: Text('Format to Linux Format',
                        style: TextStyle(color: colorScheme.error)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      side: BorderSide(color: colorScheme.error),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
    }
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}
