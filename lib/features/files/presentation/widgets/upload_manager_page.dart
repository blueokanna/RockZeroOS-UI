import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/download_manager.dart';

/// 上传管理页面 - 显示所有上传任务
class UploadManagerPage extends ConsumerStatefulWidget {
  const UploadManagerPage({super.key});

  @override
  ConsumerState<UploadManagerPage> createState() => _UploadManagerPageState();
}

class _UploadManagerPageState extends ConsumerState<UploadManagerPage> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    // 每秒更新一次UI以显示实时进度
    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloadManager = ref.watch(downloadManagerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final activeUploads = downloadManager.uploads
        .where((u) =>
            u.status == DownloadStatus.downloading ||
            u.status == DownloadStatus.pending)
        .toList();
    final completedUploads = downloadManager.uploads
        .where((u) => u.status == DownloadStatus.completed)
        .toList();
    final failedUploads = downloadManager.uploads
        .where((u) => u.status == DownloadStatus.failed)
        .toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Upload Manager'),
            actions: [
              if (completedUploads.isNotEmpty || failedUploads.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded),
                  onPressed: () {
                    for (final upload in [
                      ...completedUploads,
                      ...failedUploads
                    ]) {
                      ref
                          .read(downloadManagerProvider.notifier)
                          .removeUpload(upload.id);
                    }
                  },
                  tooltip: 'Clear completed',
                ),
            ],
          ),
          if (activeUploads.isEmpty &&
              completedUploads.isEmpty &&
              failedUploads.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        Icons.cloud_upload_rounded,
                        size: 44,
                        color:
                            colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No uploads',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Upload files from the Files page',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (activeUploads.isNotEmpty) ...[
                    _SectionHeader(
                      title: 'Uploading',
                      count: activeUploads.length,
                      icon: Icons.cloud_upload_rounded,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    ...activeUploads.map((upload) => _UploadTaskCard(
                          upload: upload,
                          onCancel: () {
                            ref
                                .read(downloadManagerProvider.notifier)
                                .removeUpload(upload.id);
                          },
                        )),
                    const SizedBox(height: 24),
                  ],
                  if (completedUploads.isNotEmpty) ...[
                    _SectionHeader(
                      title: 'Completed',
                      count: completedUploads.length,
                      icon: Icons.check_circle_rounded,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 12),
                    ...completedUploads.map((upload) => _UploadTaskCard(
                          upload: upload,
                          onRemove: () {
                            ref
                                .read(downloadManagerProvider.notifier)
                                .removeUpload(upload.id);
                          },
                        )),
                    const SizedBox(height: 24),
                  ],
                  if (failedUploads.isNotEmpty) ...[
                    _SectionHeader(
                      title: 'Failed',
                      count: failedUploads.length,
                      icon: Icons.error_rounded,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    ...failedUploads.map((upload) => _UploadTaskCard(
                          upload: upload,
                          onRetry: () {
                            // TODO: 实现重试上传
                          },
                          onRemove: () {
                            ref
                                .read(downloadManagerProvider.notifier)
                                .removeUpload(upload.id);
                          },
                        )),
                  ],
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _UploadTaskCard extends StatelessWidget {
  final UploadTask upload;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;

  const _UploadTaskCard({
    required this.upload,
    this.onCancel,
    this.onRetry,
    this.onRemove,
  });

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else if (bytesPerSecond >= 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '$bytesPerSecond B/s';
  }

  String _formatRemainingTime(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else if (seconds < 3600) {
      return '${seconds ~/ 60}m ${seconds % 60}s';
    } else {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return '${hours}h ${minutes}m';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final isUploading = upload.status == DownloadStatus.downloading;
    final isCompleted = upload.status == DownloadStatus.completed;
    final isFailed = upload.status == DownloadStatus.failed;

    // 计算上传速度和剩余时间
    final speed = upload.uploadSpeed;
    final remainingBytes = upload.totalBytes - upload.uploadedBytes;
    final remainingSeconds = speed > 0 ? remainingBytes ~/ speed : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFailed
              ? colorScheme.error.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? Colors.green.withValues(alpha: 0.15)
                        : isFailed
                            ? colorScheme.errorContainer
                            : colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isCompleted
                        ? Icons.check_circle_rounded
                        : isFailed
                            ? Icons.error_rounded
                            : Icons.insert_drive_file_rounded,
                    color: isCompleted
                        ? Colors.green
                        : isFailed
                            ? colorScheme.error
                            : colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        upload.fileName,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isCompleted
                            ? 'Completed • ${_formatBytes(upload.totalBytes)}'
                            : isFailed
                                ? 'Failed • ${upload.error ?? "Unknown error"}'
                                : '${_formatBytes(upload.uploadedBytes)} / ${_formatBytes(upload.totalBytes)}',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isUploading && onCancel != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onCancel,
                    tooltip: 'Cancel',
                    iconSize: 20,
                  ),
                if (isFailed && onRetry != null)
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: onRetry,
                    tooltip: 'Retry',
                    iconSize: 20,
                  ),
                if ((isCompleted || isFailed) && onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: onRemove,
                    tooltip: 'Remove',
                    iconSize: 20,
                  ),
              ],
            ),
            if (isUploading) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: upload.progress,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(upload.progress * 100).toStringAsFixed(1)}%',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (speed > 0)
                    Row(
                      children: [
                        Icon(
                          Icons.speed_rounded,
                          size: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatSpeed(speed),
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.schedule_rounded,
                          size: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatRemainingTime(remainingSeconds),
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
