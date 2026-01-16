import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_service.dart';
import '../../../../core/services/device_discovery_service.dart';

/// Supported file systems for formatting
const List<Map<String, dynamic>> supportedFileSystems = [
  {
    'name': 'ext4',
    'displayName': 'EXT4',
    'description': 'Linux 默认文件系统，稳定可靠',
    'icon': Icons.storage_rounded,
    'recommended': true
  },
  {
    'name': 'xfs',
    'displayName': 'XFS',
    'description': '高性能文件系统，适合大文件',
    'icon': Icons.speed_rounded,
    'recommended': false
  },
  {
    'name': 'btrfs',
    'displayName': 'Btrfs',
    'description': '现代 CoW 文件系统，支持快照',
    'icon': Icons.layers_rounded,
    'recommended': false
  },
  {
    'name': 'f2fs',
    'displayName': 'F2FS',
    'description': '闪存优化文件系统',
    'icon': Icons.flash_on_rounded,
    'recommended': false
  },
  {
    'name': 'exfat',
    'displayName': 'exFAT',
    'description': '跨平台兼容，支持大文件',
    'icon': Icons.devices_rounded,
    'recommended': false
  },
  {
    'name': 'ntfs',
    'displayName': 'NTFS',
    'description': 'Windows 兼容',
    'icon': Icons.window_rounded,
    'recommended': false
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
    throw Exception('未连接到任何设备');
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

  Future<void> _scanDisks() async {
    setState(() => _isScanning = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.post('/api/v1/disk/scan');
      ref.invalidate(allDisksDetailProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('磁盘扫描完成'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e'), backgroundColor: Colors.red),
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
        title: const Text('磁盘管理'),
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
              tooltip: '扫描新磁盘',
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(allDisksDetailProvider),
            tooltip: '刷新',
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
                '正在加载磁盘信息...',
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
            '未发现磁盘',
            style: textTheme.titleMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            '连接外部存储设备或检查系统配置',
            style: textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _scanDisks,
            icon: const Icon(Icons.search_rounded),
            label: const Text('扫描磁盘'),
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
              '加载磁盘信息失败',
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
              label: const Text('重试'),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isMounted = disk.isMounted &&
        disk.mountPoint.isNotEmpty &&
        disk.mountPoint != 'Not mounted';
    final isUnpartitioned =
        disk.fileSystem == 'Unknown' || disk.fileSystem.isEmpty;

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
                          : (isUnpartitioned
                              ? colorScheme.errorContainer
                              : colorScheme.surfaceContainerHighest),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getDiskIcon(),
                      color: isMounted
                          ? colorScheme.onPrimaryContainer
                          : (isUnpartitioned
                              ? colorScheme.onErrorContainer
                              : colorScheme.onSurfaceVariant),
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
                  _buildStatusChip(context, isMounted, isUnpartitioned),
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
                      '${disk.usagePercentage.toStringAsFixed(1)}% 已使用',
                      style: textTheme.bodySmall?.copyWith(
                        color: _getUsageColor(disk.usagePercentage),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ] else if (!isUnpartitioned) ...[
                const SizedBox(height: 12),
                Text('容量: ${_formatBytes(disk.totalSpace)}',
                    style: textTheme.bodyMedium),
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
                          '此磁盘未分区，点击初始化',
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
                      disk.fileSystem != 'Unknown')
                    Chip(
                      label: Text(disk.fileSystem.toUpperCase()),
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
                      avatar: Icon(Icons.usb_rounded,
                          size: 16, color: colorScheme.primary),
                      label: const Text('可移除'),
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

  Widget _buildStatusChip(
      BuildContext context, bool isMounted, bool isUnpartitioned) {
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
          '未分区',
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
          color: colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '未挂载',
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onTertiaryContainer,
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
        '已挂载',
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
    final isUnpartitioned =
        disk.fileSystem == 'Unknown' || disk.fileSystem.isEmpty;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => isUnpartitioned
          ? _InitializeDiskSheet(disk: disk, onComplete: onRefresh)
          : _DiskDetailsSheet(disk: disk, onRefresh: onRefresh),
    );
  }
}

class _InitializeDiskSheet extends ConsumerStatefulWidget {
  final DiskDetail disk;
  final VoidCallback onComplete;

  const _InitializeDiskSheet({required this.disk, required this.onComplete});

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
    setState(() => _isInitializing = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.post('/api/v1/disk/initialize', data: {
        'device': widget.disk.devicePath,
        'file_system': _selectedFs,
        if (_labelController.text.isNotEmpty) 'label': _labelController.text,
        'partition_table': 'gpt',
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('磁盘初始化成功'), backgroundColor: Colors.green),
        );
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('初始化失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
                  Icon(Icons.build_rounded, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '初始化磁盘',
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
                            '警告：此操作将清除磁盘上的所有数据！',
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
                    label: '设备',
                    value: widget.disk.devicePath,
                  ),
                  _InfoRow(
                    icon: Icons.sd_storage_rounded,
                    label: '容量',
                    value: _formatBytes(widget.disk.totalSpace),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '选择文件系统',
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
                                '推荐',
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
                    '磁盘标签 (可选)',
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _labelController,
                    decoration: const InputDecoration(
                      hintText: '输入磁盘标签',
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
                        : const Icon(Icons.build_rounded),
                    label: Text(_isInitializing ? '正在初始化...' : '初始化磁盘'),
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
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final mountPoint = '/mnt/${widget.disk.label ?? widget.disk.name}';
      await api.post('/api/v1/disk/mount', data: {
        'device': widget.disk.devicePath,
        'mount_point': mountPoint,
        'file_system': widget.disk.fileSystem,
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('磁盘挂载成功'), backgroundColor: Colors.green),
        );
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('挂载失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
              content: Text('磁盘卸载成功'), backgroundColor: Colors.green),
        );
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('卸载失败: $e'), backgroundColor: Colors.red),
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
          const SnackBar(content: Text('磁盘已弹出'), backgroundColor: Colors.green),
        );
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('弹出失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showFormatDialog() {
    showDialog(
      context: context,
      builder: (context) => _FormatDiskDialog(
        disk: widget.disk,
        onComplete: () {
          Navigator.pop(context);
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
                    label: '挂载点',
                    value: isMounted ? widget.disk.mountPoint : '未挂载',
                  ),
                  _InfoRow(
                    icon: Icons.description_rounded,
                    label: '文件系统',
                    value: widget.disk.fileSystem,
                  ),
                  _InfoRow(
                    icon: Icons.category_rounded,
                    label: '类型',
                    value: widget.disk.diskType,
                  ),
                  _InfoRow(
                    icon: Icons.storage_rounded,
                    label: '总容量',
                    value: _formatBytes(widget.disk.totalSpace),
                  ),
                  if (isMounted) ...[
                    _InfoRow(
                      icon: Icons.pie_chart_rounded,
                      label: '已使用',
                      value: _formatBytes(widget.disk.usedSpace),
                    ),
                    _InfoRow(
                      icon: Icons.check_circle_rounded,
                      label: '可用',
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
                      label: '型号',
                      value: widget.disk.model!,
                    ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    '操作',
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
                          : const Icon(Icons.play_arrow_rounded),
                      label: const Text('挂载磁盘'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    FilledButton.tonalIcon(
                      onPressed: _isLoading ? null : _unmountDisk,
                      icon: const Icon(Icons.eject_rounded),
                      label: const Text('卸载磁盘'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: _showRenameDialog,
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('重命名'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (widget.disk.isRemovable) ...[
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _ejectDisk,
                      icon: const Icon(Icons.eject_rounded),
                      label: const Text('安全弹出'),
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
                    label:
                        Text('格式化', style: TextStyle(color: colorScheme.error)),
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
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('格式化成功'), backgroundColor: Colors.green),
        );
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('格式化失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFormatting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_rounded, color: colorScheme.error),
          const SizedBox(width: 8),
          const Text('格式化磁盘'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_confirmed) ...[
              Text('确定要格式化 ${widget.disk.label ?? widget.disk.name} 吗？'),
              const SizedBox(height: 8),
              Text(
                '此操作将清除磁盘上的所有数据！',
                style: TextStyle(
                    color: colorScheme.error, fontWeight: FontWeight.bold),
              ),
            ] else ...[
              const Text('选择文件系统:'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedFs,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: supportedFileSystems
                    .map((fs) => DropdownMenuItem(
                          value: fs['name'] as String,
                          child: Text(fs['displayName'] as String),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedFs = v);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: '磁盘标签 (可选)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isFormatting ? null : _formatDisk,
          style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
          child: _isFormatting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(_confirmed ? '确认格式化' : '继续'),
        ),
      ],
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
          const SnackBar(content: Text('重命名成功'), backgroundColor: Colors.green),
        );
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重命名失败: $e'), backgroundColor: Colors.red),
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
      title: const Text('重命名磁盘'),
      content: TextField(
        controller: _labelController,
        decoration: const InputDecoration(
          labelText: '新标签',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isRenaming ? null : _renameDisk,
          child: _isRenaming
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('确认'),
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
