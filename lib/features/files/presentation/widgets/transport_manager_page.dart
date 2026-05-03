import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';

import '../../../../core/services/download_manager.dart';

class TransportManagerPage extends ConsumerStatefulWidget {
  const TransportManagerPage({super.key});

  @override
  ConsumerState<TransportManagerPage> createState() =>
      _TransportManagerPageState();
}

class _TransportManagerPageState extends ConsumerState<TransportManagerPage>
    with SingleTickerProviderStateMixin {
  Timer? _updateTimer;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transportManager = ref.watch(downloadManagerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final totalCompleted = transportManager.completedDownloads.length +
        transportManager.uploads
            .where((u) => u.status == DownloadStatus.completed)
            .length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, colorScheme.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.sync_alt_rounded,
                    size: 24,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Transport'),
              ],
            ),
            actions: [
              if (totalCompleted > 0)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded),
                  onPressed: () => _clearAllCompleted(ref),
                  tooltip: 'Clear completed',
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  labelColor: colorScheme.onPrimaryContainer,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.download_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text('Downloads'),
                          if (transportManager.activeDownloads > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${transportManager.activeDownloads}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.upload_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text('Uploads'),
                          if (transportManager.activeUploads > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${transportManager.activeUploads}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDownloadsTab(transportManager),
                _buildUploadsTab(transportManager),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadsTab(DownloadManagerState state) {
    final colorScheme = Theme.of(context).colorScheme;

    final activeDownloads = state.downloads
        .where((d) =>
            d.status == DownloadStatus.downloading ||
            d.status == DownloadStatus.paused ||
            d.status == DownloadStatus.pending)
        .toList();
    final completedDownloads = state.completedDownloads;
    final failedDownloads = state.downloads
        .where((d) => d.status == DownloadStatus.failed)
        .toList();

    if (activeDownloads.isEmpty &&
        completedDownloads.isEmpty &&
        failedDownloads.isEmpty) {
      return _buildEmptyState(
        icon: Icons.download_rounded,
        title: 'No downloads',
        subtitle: 'Downloaded files will appear here',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (activeDownloads.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.downloading_rounded,
            title: 'Active',
            count: activeDownloads.length,
            color: Colors.blue,
          ),
          const SizedBox(height: 8),
          ...activeDownloads.map((download) => _TransportCard(
                fileName: download.fileName,
                status: download.status,
                progress: download.progress,
                progressText: download.progressText,
                sizeText: download.sizeText,
                isUpload: false,
                onPause: () => ref
                    .read(downloadManagerProvider.notifier)
                    .pauseDownload(download.id),
                onResume: () => ref
                    .read(downloadManagerProvider.notifier)
                    .resumeDownload(download.id),
                onCancel: () => ref
                    .read(downloadManagerProvider.notifier)
                    .cancelDownload(download.id),
              )),
          const SizedBox(height: 24),
        ],
        if (completedDownloads.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.check_circle_rounded,
            title: 'Completed',
            count: completedDownloads.length,
            color: Colors.green,
          ),
          const SizedBox(height: 8),
          ...completedDownloads.map((download) => _TransportCard(
                fileName: download.fileName,
                status: download.status,
                progress: download.progress,
                progressText: download.progressText,
                sizeText: download.sizeText,
                isUpload: false,
                onOpen: () => _openFile(download.savePath),
                onCancel: () => ref
                    .read(downloadManagerProvider.notifier)
                    .cancelDownload(download.id),
              )),
          const SizedBox(height: 24),
        ],
        if (failedDownloads.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.error_rounded,
            title: 'Failed',
            count: failedDownloads.length,
            color: colorScheme.error,
          ),
          const SizedBox(height: 8),
          ...failedDownloads.map((download) => _TransportCard(
                fileName: download.fileName,
                status: download.status,
                progress: download.progress,
                progressText: download.progressText,
                sizeText: download.sizeText,
                isUpload: false,
                onRetry: () => ref
                    .read(downloadManagerProvider.notifier)
                    .resumeDownload(download.id),
                onCancel: () => ref
                    .read(downloadManagerProvider.notifier)
                    .cancelDownload(download.id),
              )),
        ],
      ],
    );
  }

  Widget _buildUploadsTab(DownloadManagerState state) {
    final colorScheme = Theme.of(context).colorScheme;

    final activeUploads = state.uploads
        .where((u) =>
            u.status == DownloadStatus.downloading ||
            u.status == DownloadStatus.pending)
        .toList();
    final completedUploads = state.uploads
        .where((u) => u.status == DownloadStatus.completed)
        .toList();
    final failedUploads =
        state.uploads.where((u) => u.status == DownloadStatus.failed).toList();

    if (activeUploads.isEmpty &&
        completedUploads.isEmpty &&
        failedUploads.isEmpty) {
      return _buildEmptyState(
        icon: Icons.upload_rounded,
        title: 'No uploads',
        subtitle: 'Uploaded files will appear here',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (activeUploads.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.upload_rounded,
            title: 'Active',
            count: activeUploads.length,
            color: Colors.green,
          ),
          const SizedBox(height: 8),
          ...activeUploads.map((upload) => _TransportCard(
                fileName: upload.fileName,
                status: upload.status,
                progress: upload.progress,
                progressText: upload.progressText,
                sizeText: _formatBytes(upload.totalBytes),
                isUpload: true,
                onCancel: () => ref
                    .read(downloadManagerProvider.notifier)
                    .removeUpload(upload.id),
              )),
          const SizedBox(height: 24),
        ],
        if (completedUploads.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.check_circle_rounded,
            title: 'Completed',
            count: completedUploads.length,
            color: Colors.green,
          ),
          const SizedBox(height: 8),
          ...completedUploads.map((upload) => _TransportCard(
                fileName: upload.fileName,
                status: upload.status,
                progress: upload.progress,
                progressText: upload.progressText,
                sizeText: _formatBytes(upload.totalBytes),
                isUpload: true,
                onCancel: () => ref
                    .read(downloadManagerProvider.notifier)
                    .removeUpload(upload.id),
              )),
          const SizedBox(height: 24),
        ],
        if (failedUploads.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.error_rounded,
            title: 'Failed',
            count: failedUploads.length,
            color: colorScheme.error,
          ),
          const SizedBox(height: 8),
          ...failedUploads.map((upload) => _TransportCard(
                fileName: upload.fileName,
                status: upload.status,
                progress: upload.progress,
                progressText: upload.progressText,
                sizeText: _formatBytes(upload.totalBytes),
                isUpload: true,
                onCancel: () => ref
                    .read(downloadManagerProvider.notifier)
                    .removeUpload(upload.id),
              )),
        ],
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
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
              icon,
              size: 44,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  void _clearAllCompleted(WidgetRef ref) {
    final notifier = ref.read(downloadManagerProvider.notifier);
    notifier.clearCompleted();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _openFile(String path) async {
    try {
      await OpenFile.open(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open file: $e')),
        );
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Text(
          '$title ($count)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
      ],
    );
  }
}

class _TransportCard extends StatelessWidget {
  final String fileName;
  final DownloadStatus status;
  final double progress;
  final String progressText;
  final String sizeText;
  final bool isUpload;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onOpen;

  const _TransportCard({
    required this.fileName,
    required this.status,
    required this.progress,
    required this.progressText,
    required this.sizeText,
    required this.isUpload,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onRetry,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
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
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _getStatusColor(status, isUpload)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getFileIcon(fileName),
                    color: _getStatusColor(status, isUpload),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isUpload
                                ? Icons.upload_rounded
                                : Icons.download_rounded,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              fileName,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sizeText,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status, isUpload)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getStatusIcon(status),
                        size: 14,
                        color: _getStatusColor(status, isUpload),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getStatusText(status),
                        style: textTheme.labelSmall?.copyWith(
                          color: _getStatusColor(status, isUpload),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (status == DownloadStatus.downloading ||
                status == DownloadStatus.paused ||
                status == DownloadStatus.pending) ...[
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                        _getStatusColor(status, isUpload),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    progressText,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (status == DownloadStatus.completed && onOpen != null)
                  FilledButton.tonalIcon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open'),
                  ),
                if (status == DownloadStatus.downloading && onPause != null)
                  FilledButton.tonalIcon(
                    onPressed: onPause,
                    icon: const Icon(Icons.pause_rounded, size: 18),
                    label: const Text('Pause'),
                  ),
                if ((status == DownloadStatus.paused ||
                        status == DownloadStatus.failed) &&
                    (onResume != null || onRetry != null))
                  FilledButton.tonalIcon(
                    onPressed: onResume ?? onRetry,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(
                        status == DownloadStatus.failed ? 'Retry' : 'Resume'),
                  ),
                if (onCancel != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onCancel,
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: colorScheme.error),
                    label: Text(
                      status == DownloadStatus.completed ? 'Remove' : 'Cancel',
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(DownloadStatus status, bool isUpload) {
    if (isUpload && status == DownloadStatus.downloading) {
      return Colors.green;
    }
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
        return Icons.sync_rounded;
      case DownloadStatus.paused:
        return Icons.pause_circle_rounded;
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

  String _getStatusText(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.downloading:
        return 'Active';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.completed:
        return 'Done';
      case DownloadStatus.failed:
        return 'Failed';
      case DownloadStatus.cancelled:
        return 'Cancelled';
      case DownloadStatus.pending:
        return 'Pending';
    }
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
        return Icons.image_rounded;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
        return Icons.video_file_rounded;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.audio_file_rounded;
      case 'txt':
        return Icons.text_snippet_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }
}
