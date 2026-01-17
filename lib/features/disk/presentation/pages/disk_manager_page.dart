import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';

final diskListProvider = FutureProvider.autoDispose<List<DiskDetail>>((
  ref,
) async {
  final api = ref.read(apiServiceProvider);
  return await api.listDisks();
});

class DiskManagerPage extends ConsumerStatefulWidget {
  const DiskManagerPage({super.key});

  @override
  ConsumerState<DiskManagerPage> createState() => _DiskManagerPageState();
}

class _DiskManagerPageState extends ConsumerState<DiskManagerPage> {
  @override
  Widget build(BuildContext context) {
    final disksAsync = ref.watch(diskListProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Disk Manager'),
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Supported Filesystems',
                onPressed: () => _showFilesystemInfo(context),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(diskListProvider),
              ),
            ],
          ),
          disksAsync.when(
            data: (disks) {
              if (disks.isEmpty) {
                return SliverFillRemaining(child: _buildEmptyState(context));
              }
              return SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _DiskCard(disk: disks[index])
                        .animate(delay: (50 * index).ms)
                        .fadeIn()
                        .slideY(begin: 0.1),
                    childCount: disks.length,
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              child: _buildErrorState(context, error.toString()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.storage,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No disks found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Connect a storage device to manage it',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: colorScheme.error),
          const SizedBox(height: 16),
          Text(
            'Failed to load disks',
            style: TextStyle(color: colorScheme.error),
          ),
          const SizedBox(height: 8),
          Text(error, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => ref.invalidate(diskListProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _showFilesystemInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supported Filesystems'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FilesystemInfoTile(
                name: 'ext4',
                description: 'Default Linux filesystem',
                maxFileSize: '16 TB',
              ),
              _FilesystemInfoTile(
                name: 'xfs',
                description: 'High-performance filesystem',
                maxFileSize: '8 EB',
              ),
              _FilesystemInfoTile(
                name: 'btrfs',
                description: 'Modern copy-on-write filesystem',
                maxFileSize: '16 EB',
              ),
              _FilesystemInfoTile(
                name: 'FAT32',
                description: 'Universal compatibility',
                maxFileSize: '4 GB',
              ),
              _FilesystemInfoTile(
                name: 'exFAT',
                description: 'Extended FAT for large files',
                maxFileSize: '16 EB',
              ),
              _FilesystemInfoTile(
                name: 'NTFS',
                description: 'Windows native filesystem',
                maxFileSize: '16 EB',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _FilesystemInfoTile extends StatelessWidget {
  final String name;
  final String description;
  final String maxFileSize;

  const _FilesystemInfoTile({
    required this.name,
    required this.description,
    required this.maxFileSize,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description, style: const TextStyle(fontSize: 13)),
                Text(
                  'Max file: $maxFileSize',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiskCard extends ConsumerWidget {
  final DiskDetail disk;

  const _DiskCard({required this.disk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final usageColor = _getUsageColor(disk.usagePercentage);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: disk.isRemovable
                        ? Colors.orange.withValues(alpha: 0.1)
                        : colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    disk.isRemovable ? Icons.usb : Icons.storage,
                    color: disk.isRemovable
                        ? Colors.orange
                        : colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        disk.name,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _StatusChip(
                            label: disk.isMounted ? 'Mounted' : 'Unmounted',
                            color: disk.isMounted ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            disk.fileSystem,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            disk.diskType,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (disk.readOnly) ...[
                            const SizedBox(width: 8),
                            _StatusChip(
                              label: 'Read Only',
                              color: Colors.orange,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) => _handleAction(context, ref, value),
                  itemBuilder: (context) => [
                    if (!disk.isMounted)
                      const PopupMenuItem(
                        value: 'mount',
                        child: Row(
                          children: [
                            Icon(Icons.play_arrow),
                            SizedBox(width: 8),
                            Text('Mount'),
                          ],
                        ),
                      ),
                    if (disk.isMounted)
                      const PopupMenuItem(
                        value: 'unmount',
                        child: Row(
                          children: [
                            Icon(Icons.stop),
                            SizedBox(width: 8),
                            Text('Unmount'),
                          ],
                        ),
                      ),
                    if (disk.isRemovable)
                      const PopupMenuItem(
                        value: 'eject',
                        child: Row(
                          children: [
                            Icon(Icons.eject),
                            SizedBox(width: 8),
                            Text('Eject'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'format',
                      child: Row(
                        children: [
                          Icon(Icons.format_paint),
                          SizedBox(width: 8),
                          Text('Format'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'health',
                      child: Row(
                        children: [
                          Icon(Icons.health_and_safety),
                          SizedBox(width: 8),
                          Text('Check Health'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildStorageUsage(context, usageColor),
            if (disk.mountPoint.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildMountPointInfo(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStorageUsage(BuildContext context, Color usageColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Storage Usage',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${disk.usagePercentage.toStringAsFixed(1)}%',
              style: textTheme.bodyMedium?.copyWith(
                color: usageColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: disk.usagePercentage / 100,
            minHeight: 8,
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(usageColor),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _StorageInfo(
              label: 'Used',
              value: _formatBytes(disk.usedSpace),
              color: usageColor,
            ),
            _StorageInfo(
              label: 'Available',
              value: _formatBytes(disk.availableSpace),
              color: Colors.green,
            ),
            _StorageInfo(
              label: 'Total',
              value: _formatBytes(disk.totalSpace),
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMountPointInfo(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.folder, size: 20, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Mount Point: ${disk.mountPoint}',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleAction(BuildContext context, WidgetRef ref, String action) {
    switch (action) {
      case 'mount':
        _showMountDialog(context, ref);
        break;
      case 'unmount':
        _unmountDisk(context, ref);
        break;
      case 'eject':
        _ejectDisk(context, ref);
        break;
      case 'format':
        _showFormatDialog(context, ref);
        break;
      case 'health':
        _checkHealth(context, ref);
        break;
    }
  }

  void _showMountDialog(BuildContext context, WidgetRef ref) {
    // 检查磁盘是否需要初始化
    final fs = disk.fileSystem.trim().toLowerCase();
    final needsInitialization = fs.isEmpty || fs == 'unknown';

    if (needsInitialization) {
      // 磁盘没有文件系统，需要先初始化
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            Icons.warning_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 48,
          ),
          title: const Text('磁盘未初始化'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '设备 ${disk.name} 没有分区和文件系统。',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .errorContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .error
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '磁盘信息',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('大小: ${_formatBytes(disk.totalSpace)}'),
                    Text('类型: ${disk.diskType}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '请先初始化磁盘以创建分区表和文件系统，然后才能挂载使用。',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showInitializeDialog(context, ref);
              },
              icon: const Icon(Icons.settings_rounded),
              label: const Text('初始化磁盘'),
            ),
          ],
        ),
      );
      return;
    }

    // 磁盘已有文件系统，显示挂载对话框
    final mountPointController = TextEditingController(
      text: '/mnt/${disk.name}',
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mount Disk'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Do you want to mount "${disk.name}"?',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Size: ${_formatBytes(disk.totalSpace)}',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'Type: ${disk.diskType}',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: mountPointController,
              decoration: const InputDecoration(
                labelText: 'Mount Point',
                hintText: '/mnt/disk',
                prefixIcon: Icon(Icons.folder),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _mountDisk(context, ref, mountPointController.text);
            },
            child: const Text('Mount'),
          ),
        ],
      ),
    );
  }

  void _showInitializeDialog(BuildContext context, WidgetRef ref) {
    String selectedFs = 'ext4';
    final labelController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('初始化磁盘'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '警告：此操作将清除磁盘上的所有数据！',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '磁盘: ${disk.name}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  '大小: ${_formatBytes(disk.totalSpace)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedFs,
                  decoration: const InputDecoration(
                    labelText: '文件系统',
                    prefixIcon: Icon(Icons.folder_special),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'ext4', child: Text('ext4 (推荐 Linux)')),
                    DropdownMenuItem(
                        value: 'ext3', child: Text('ext3 (Linux)')),
                    DropdownMenuItem(value: 'xfs', child: Text('XFS (Linux)')),
                    DropdownMenuItem(
                        value: 'btrfs', child: Text('Btrfs (Linux)')),
                    DropdownMenuItem(value: 'fat32', child: Text('FAT32 (通用)')),
                    DropdownMenuItem(value: 'exfat', child: Text('exFAT (通用)')),
                    DropdownMenuItem(
                        value: 'ntfs', child: Text('NTFS (Windows)')),
                  ],
                  onChanged: (value) => setState(() => selectedFs = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: '卷标 (可选)',
                    hintText: 'My Disk',
                    prefixIcon: Icon(Icons.label),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _initializeDisk(
                  context,
                  ref,
                  selectedFs,
                  labelController.text,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('初始化'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initializeDisk(
    BuildContext context,
    WidgetRef ref,
    String fileSystem,
    String label,
  ) async {
    // 显示进度对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在初始化磁盘...'),
            SizedBox(height: 8),
            Text(
              '这可能需要几分钟时间',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );

    try {
      final api = ref.read(apiServiceProvider);
      await api.initializeDisk(
        device: disk.devicePath,
        fileSystem: fileSystem,
        label: label.isNotEmpty ? label : null,
        partitionTable: 'gpt',
      );

      if (!context.mounted) return;
      Navigator.pop(context); // 关闭进度对话框
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('磁盘初始化成功')),
      );
      ref.invalidate(diskListProvider);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // 关闭进度对话框
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('初始化失败: $e')),
      );
    }
  }

  Future<void> _mountDisk(
    BuildContext context,
    WidgetRef ref,
    String mountPoint,
  ) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.mountDisk(
        device: disk.devicePath,
        mountPoint: mountPoint,
        fileSystem: disk.fileSystem,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disk mounted successfully')),
      );
      ref.invalidate(diskListProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to mount: $e')));
    }
  }

  Future<void> _unmountDisk(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unmount Disk'),
        content: Text('Are you sure you want to unmount ${disk.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Unmount'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final api = ref.read(apiServiceProvider);
        await api.unmountDisk(disk.devicePath);

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disk unmounted successfully')),
        );
        ref.invalidate(diskListProvider);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to unmount: $e')));
      }
    }
  }

  Future<void> _ejectDisk(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eject Disk'),
        content: Text(
          'Are you sure you want to safely eject ${disk.name}?\n\n'
          'Make sure all files are closed before ejecting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eject'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final api = ref.read(apiServiceProvider);
        await api.ejectDisk(disk.devicePath);

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disk ejected successfully')),
        );
        ref.invalidate(diskListProvider);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to eject: $e')));
      }
    }
  }

  void _showFormatDialog(BuildContext context, WidgetRef ref) {
    String selectedFs = 'ext4';
    final labelController = TextEditingController();
    bool quickFormat = true;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Format Disk'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'WARNING: This will erase all data on the disk!',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedFs,
                decoration: const InputDecoration(
                  labelText: 'File System',
                  prefixIcon: Icon(Icons.folder_special),
                ),
                items: const [
                  DropdownMenuItem(value: 'ext4', child: Text('ext4 (Linux)')),
                  DropdownMenuItem(value: 'ext3', child: Text('ext3 (Linux)')),
                  DropdownMenuItem(value: 'xfs', child: Text('XFS (Linux)')),
                  DropdownMenuItem(
                    value: 'btrfs',
                    child: Text('Btrfs (Linux)'),
                  ),
                  DropdownMenuItem(
                    value: 'fat32',
                    child: Text('FAT32 (Universal)'),
                  ),
                  DropdownMenuItem(
                    value: 'exfat',
                    child: Text('exFAT (Universal)'),
                  ),
                  DropdownMenuItem(
                    value: 'ntfs',
                    child: Text('NTFS (Windows)'),
                  ),
                ],
                onChanged: (value) => setState(() => selectedFs = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Label (Optional)',
                  hintText: 'My Disk',
                  prefixIcon: Icon(Icons.label),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Quick Format'),
                subtitle: const Text('Faster but less thorough'),
                value: quickFormat,
                onChanged: (value) => setState(() => quickFormat = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _formatDisk(
                  context,
                  ref,
                  selectedFs,
                  labelController.text,
                  quickFormat,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Format'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _formatDisk(
    BuildContext context,
    WidgetRef ref,
    String fileSystem,
    String label,
    bool quick,
  ) async {
    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Formatting disk...'),
            SizedBox(height: 8),
            Text(
              'This may take a while',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );

    try {
      final api = ref.read(apiServiceProvider);
      await api.formatDisk(
        device: disk.devicePath,
        fileSystem: fileSystem,
        label: label.isNotEmpty ? label : null,
      );

      if (!context.mounted) return;
      Navigator.pop(context); // Close progress dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disk formatted successfully')),
      );
      ref.invalidate(diskListProvider);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // Close progress dialog
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to format: $e')));
    }
  }

  Future<void> _checkHealth(BuildContext context, WidgetRef ref) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Checking disk health...'),
          ],
        ),
      ),
    );

    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.checkDiskHealth(disk.devicePath);

      if (!context.mounted) return;
      Navigator.pop(context); // Close loading dialog

      _showHealthResultDialog(context, response);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to check health: $e')));
    }
  }

  void _showHealthResultDialog(
    BuildContext context,
    Map<String, dynamic> response,
  ) {
    final isHealthy = response['healthy'] == true;
    final smartStatus = response['smart_status'] ?? 'UNKNOWN';
    final temperature = response['temperature'];
    final powerOnHours = response['power_on_hours'];

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isHealthy ? Icons.check_circle : Icons.error,
              color: isHealthy ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            const Text('Disk Health'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HealthInfoRow(
                label: 'SMART Status',
                value: smartStatus,
                valueColor: isHealthy ? Colors.green : Colors.red,
              ),
              if (temperature != null)
                _HealthInfoRow(
                  label: 'Temperature',
                  value: '${temperature.toStringAsFixed(0)}°C',
                  valueColor: temperature > 50 ? Colors.orange : Colors.green,
                ),
              if (powerOnHours != null)
                _HealthInfoRow(
                  label: 'Power On Hours',
                  value: '$powerOnHours hours',
                ),
              const Divider(),
              Text(
                isHealthy
                    ? 'Your disk appears to be healthy.'
                    : 'Warning: Issues detected. Consider backing up your data.',
                style: TextStyle(
                  color: isHealthy ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Color _getUsageColor(double usage) {
    if (usage >= 90) return Colors.red;
    if (usage >= 70) return Colors.orange;
    if (usage >= 50) return Colors.yellow.shade700;
    return Colors.green;
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
    } else if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _StorageInfo extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StorageInfo({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _HealthInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _HealthInfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
    );
  }
}
