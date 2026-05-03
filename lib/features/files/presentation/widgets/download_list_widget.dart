import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/download_manager.dart';

class DownloadListWidget extends ConsumerWidget {
  final bool showUploads;
  final bool showDownloads;
  final bool compact;

  const DownloadListWidget({
    super.key,
    this.showUploads = true,
    this.showDownloads = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadManagerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final activeDownloads = state.downloads
        .where((d) =>
            d.status == DownloadStatus.downloading ||
            d.status == DownloadStatus.paused ||
            d.status == DownloadStatus.pending)
        .toList();

    final activeUploads = state.uploads
        .where((u) =>
            u.status == DownloadStatus.downloading ||
            u.status == DownloadStatus.pending)
        .toList();

    if (activeDownloads.isEmpty && activeUploads.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, colorScheme.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.sync_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transfers',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        '${activeDownloads.length} downloads, ${activeUploads.length} uploads',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.expand_more_rounded),
                  onPressed: () => _showFullList(context, ref),
                ),
              ],
            ),
          ),
          ...activeDownloads.take(3).map((task) => _DownloadTaskTile(
                task: task,
                compact: compact,
              )),
          ...activeUploads.take(3 - activeDownloads.take(3).length).map(
                (task) => _UploadTaskTile(task: task, compact: compact),
              ),
          if (activeDownloads.length + activeUploads.length > 3)
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton(
                onPressed: () => _showFullList(context, ref),
                child: Text(
                  'View all ${activeDownloads.length + activeUploads.length} transfers',
                ),
              ),
            ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.1);
  }

  void _showFullList(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _FullTransferList(
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class _DownloadTaskTile extends ConsumerWidget {
  final DownloadTask task;
  final bool compact;

  const _DownloadTaskTile({required this.task, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getStatusColor(task.status).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getStatusIcon(task.status),
              color: _getStatusColor(task.status),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.fileName,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: task.progress,
                          minHeight: 4,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(
                            _getStatusColor(task.status),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      task.progressText,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (!compact)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      task.sizeText,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (task.status == DownloadStatus.downloading)
            IconButton(
              icon: const Icon(Icons.pause_rounded, size: 20),
              onPressed: () => ref
                  .read(downloadManagerProvider.notifier)
                  .pauseDownload(task.id),
            )
          else if (task.status == DownloadStatus.paused ||
              task.status == DownloadStatus.failed)
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              onPressed: () => ref
                  .read(downloadManagerProvider.notifier)
                  .resumeDownload(task.id),
            ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 20, color: colorScheme.error),
            onPressed: () => ref
                .read(downloadManagerProvider.notifier)
                .cancelDownload(task.id),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.downloading:
        return Colors.blue;
      case DownloadStatus.paused:
        return Colors.orange;
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.failed:
        return Colors.red;
      case DownloadStatus.cancelled:
        return Colors.grey;
      case DownloadStatus.pending:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.downloading:
        return Icons.download_rounded;
      case DownloadStatus.paused:
        return Icons.pause_rounded;
      case DownloadStatus.completed:
        return Icons.check_circle_rounded;
      case DownloadStatus.failed:
        return Icons.error_rounded;
      case DownloadStatus.cancelled:
        return Icons.cancel_rounded;
      case DownloadStatus.pending:
        return Icons.schedule_rounded;
    }
  }
}

class _UploadTaskTile extends ConsumerWidget {
  final UploadTask task;
  final bool compact;

  const _UploadTaskTile({required this.task, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.upload_rounded,
              color: Colors.green,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.fileName,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: task.progress,
                          minHeight: 4,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor:
                              const AlwaysStoppedAnimation(Colors.green),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      task.progressText,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 20, color: colorScheme.error),
            onPressed: () => ref
                .read(downloadManagerProvider.notifier)
                .removeUpload(task.id),
          ),
        ],
      ),
    );
  }
}

class _FullTransferList extends ConsumerWidget {
  final ScrollController scrollController;

  const _FullTransferList({required this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadManagerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'All Transfers',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              if (state.completedDownloads.isNotEmpty)
                TextButton(
                  onPressed: () => ref
                      .read(downloadManagerProvider.notifier)
                      .clearCompleted(),
                  child: const Text('Clear completed'),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              if (state.downloads.isNotEmpty) ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.download_rounded,
                          size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Downloads (${state.downloads.length})',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                      ),
                    ],
                  ),
                ),
                ...state.downloads.map((task) => _DownloadTaskTile(task: task)),
              ],
              if (state.uploads.isNotEmpty) ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.upload_rounded, size: 18, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        'Uploads (${state.uploads.length})',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                      ),
                    ],
                  ),
                ),
                ...state.uploads.map((task) => _UploadTaskTile(task: task)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class DownloadIndicatorButton extends ConsumerWidget {
  const DownloadIndicatorButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadManagerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final activeCount = state.activeDownloads + state.activeUploads;
    if (activeCount == 0) return const SizedBox.shrink();

    double totalProgress = 0;
    int count = 0;
    for (final d in state.downloads) {
      if (d.status == DownloadStatus.downloading) {
        totalProgress += d.progress;
        count++;
      }
    }
    for (final u in state.uploads) {
      if (u.status == DownloadStatus.downloading) {
        totalProgress += u.progress;
        count++;
      }
    }
    final avgProgress = count > 0 ? totalProgress / count : 0.0;

    return FloatingActionButton.small(
      heroTag: 'download_indicator',
      onPressed: () => _showTransfers(context),
      backgroundColor: colorScheme.primaryContainer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              value: avgProgress,
              strokeWidth: 3,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(colorScheme.primary),
            ),
          ),
          Text(
            '$activeCount',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    ).animate().fadeIn().scale();
  }

  void _showTransfers(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _FullTransferList(
          scrollController: scrollController,
        ),
      ),
    );
  }
}
