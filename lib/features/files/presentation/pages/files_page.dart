import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/services/biometric_service.dart';
import '../../../../core/theme/app_theme.dart';
import 'media_player_page.dart';
import 'image_viewer_page.dart';

// Current path notifier for Riverpod 3.x
class CurrentPathNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setPath(String path) => state = path;
}

final currentPathProvider = NotifierProvider<CurrentPathNotifier, String>(
  CurrentPathNotifier.new,
);

// Error message notifier for Riverpod 3.x
class FileErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setError(String? error) => state = error;
}

final fileErrorProvider = NotifierProvider<FileErrorNotifier, String?>(
  FileErrorNotifier.new,
);

final directoryListingProvider = FutureProvider.autoDispose
    .family<DirectoryListing?, String>((ref, path) async {
  try {
    final api = ref.read(apiServiceProvider);
    final result = await api.listDirectory(
      path: path.isEmpty ? null : path,
    );
    ref.read(fileErrorProvider.notifier).setError(null);
    return result;
  } catch (e) {
    ref.read(fileErrorProvider.notifier).setError(e.toString());
    return null;
  }
});

// Disk info provider
final diskInfoProvider = FutureProvider.autoDispose<List<DiskInfo>>((
  ref,
) async {
  try {
    final api = ref.read(apiServiceProvider);
    return await api.getDiskInfo();
  } catch (e) {
    return [];
  }
});

class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key});

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage>
    with SingleTickerProviderStateMixin {
  bool _isGridView = true;
  String _sortBy = 'name';
  bool _sortAsc = true;
  final Set<String> _selectedFiles = {};
  bool _isUploading = false;
  double _uploadProgress = 0;
  bool _showDisks = true;
  late AnimationController _fabAnimationController;
  final ScrollController _scrollController = ScrollController();
  bool _showFab = true;

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: M3Durations.medium2,
    );
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // Hide FAB when scrolling down, show when scrolling up
    if (_scrollController.position.userScrollDirection.toString().contains(
          'reverse',
        )) {
      if (_showFab) {
        setState(() => _showFab = false);
      }
    } else {
      if (!_showFab) {
        setState(() => _showFab = true);
      }
    }
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = ref.watch(currentPathProvider);
    final listing = ref.watch(directoryListingProvider(currentPath));
    final disks = ref.watch(diskInfoProvider);
    final errorMessage = ref.watch(fileErrorProvider);

    final showDiskView = _showDisks && currentPath.isEmpty;

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          _buildAppBar(showDiskView, currentPath),
          if (!showDiskView)
            SliverToBoxAdapter(child: _buildBreadcrumb(currentPath)),
          if (_isUploading) SliverToBoxAdapter(child: _buildUploadProgress()),
          if (showDiskView)
            disks.when(
              data: (diskList) => _buildDiskGrid(diskList),
              loading: () => _buildLoadingState(),
              error: (e, s) => _buildErrorState(e.toString()),
            )
          else
            listing.when(
              data: (data) {
                if (data == null) {
                  return _buildErrorState(
                    errorMessage ?? 'Failed to load files',
                  );
                }
                return _buildFileContent(data);
              },
              loading: () => _buildLoadingState(),
              error: (e, s) => _buildErrorState(e.toString()),
            ),
        ],
      ),
      floatingActionButton: showDiskView
          ? null
          : AnimatedSlide(
              duration: M3Durations.medium2,
              offset: _showFab ? Offset.zero : const Offset(0, 2),
              child: AnimatedOpacity(
                duration: M3Durations.medium2,
                opacity: _showFab ? 1.0 : 0.0,
                child: _buildFAB(),
              ),
            ),
    );
  }

  Widget _buildAppBar(bool showDiskView, String currentPath) {
    final colorScheme = Theme.of(context).colorScheme;

    return SliverAppBar.large(
      title: Row(
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
            child: Icon(
              showDiskView ? Icons.storage_rounded : Icons.folder_rounded,
              size: 22,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Text(showDiskView ? 'Storage' : 'Files'),
        ],
      ),
      actions: [
        if (!showDiskView) ...[
          IconButton(
            icon: AnimatedSwitcher(
              duration: M3Durations.short4,
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                key: ValueKey(_isGridView),
              ),
            ),
            onPressed: () => setState(() => _isGridView = !_isGridView),
            tooltip: _isGridView ? 'List view' : 'Grid view',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort',
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (value) {
              if (value == _sortBy) {
                setState(() => _sortAsc = !_sortAsc);
              } else {
                setState(() {
                  _sortBy = value;
                  _sortAsc = true;
                });
              }
            },
            itemBuilder: (context) => [
              _buildSortMenuItem('name', 'Name', Icons.sort_by_alpha_rounded),
              _buildSortMenuItem('size', 'Size', Icons.data_usage_rounded),
              _buildSortMenuItem(
                'modified',
                'Modified',
                Icons.schedule_rounded,
              ),
              _buildSortMenuItem('type', 'Type', Icons.category_rounded),
            ],
          ),
        ],
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () {
            if (showDiskView) {
              ref.invalidate(diskInfoProvider);
            } else {
              ref.invalidate(directoryListingProvider(currentPath));
            }
          },
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  PopupMenuItem<String> _buildSortMenuItem(
    String value,
    String label,
    IconData icon,
  ) {
    final isSelected = _sortBy == value;
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: isSelected ? colorScheme.primary : null, size: 20),
          const SizedBox(width: 12),
          Text(label),
          const Spacer(),
          if (isSelected)
            Icon(
              _sortAsc
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb(String path) {
    final parts = path.isEmpty
        ? <String>[]
        : path.split('/').where((p) => p.isNotEmpty).toList();
    final colorScheme = Theme.of(context).colorScheme;

    // Check if we're at root (/) or a subdirectory
    final isAtRoot = path == '/' || (path.isNotEmpty && parts.isEmpty);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _BreadcrumbChip(
              icon: Icons.storage_rounded,
              label: 'Storage',
              isActive: false,
              onTap: () {
                ref.read(currentPathProvider.notifier).setPath('');
                setState(() => _showDisks = true);
              },
            ),
            if (path.isNotEmpty) ...[
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              _BreadcrumbChip(
                icon: Icons.folder_rounded,
                label: '/',
                isActive: isAtRoot && parts.isEmpty,
                onTap: isAtRoot && parts.isEmpty
                    ? null
                    : () => ref.read(currentPathProvider.notifier).setPath('/'),
              ),
            ],
            ...parts.asMap().entries.map((entry) {
              final index = entry.key;
              final part = entry.value;
              final fullPath = '/${parts.sublist(0, index + 1).join('/')}';
              final isLast = index == parts.length - 1;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  _BreadcrumbChip(
                    label: part,
                    isActive: isLast,
                    onTap: isLast
                        ? null
                        : () => ref
                            .read(currentPathProvider.notifier)
                            .setPath(fullPath),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadProgress() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.primaryContainer.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.cloud_upload_rounded,
                  color: colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Uploading...',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${(_uploadProgress * 100).toInt()}% complete',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _uploadProgress,
              minHeight: 8,
              backgroundColor: colorScheme.onPrimaryContainer.withValues(
                alpha: 0.2,
              ),
              valueColor: AlwaysStoppedAnimation(colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiskGrid(List<DiskInfo> disks) {
    if (disks.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyDiskState());
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Calculate total storage
    int totalSpace = 0;
    int usedSpace = 0;
    for (final disk in disks) {
      totalSpace += disk.totalSpace;
      usedSpace += disk.usedSpace;
    }
    final totalUsagePercent =
        totalSpace > 0 ? (usedSpace / totalSpace) * 100 : 0.0;

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          // Total storage summary card
          Card(
            elevation: 0,
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colorScheme.primary, colorScheme.tertiary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.dns_rounded,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Storage',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${disks.length} ${disks.length == 1 ? 'disk' : 'disks'} connected',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: totalUsagePercent / 100),
                          duration: M3Durations.long2,
                          curve: M3Curves.emphasized,
                          builder: (context, value, child) {
                            return Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: value,
                                    minHeight: 6,
                                    backgroundColor:
                                        colorScheme.surfaceContainerHighest,
                                    valueColor: AlwaysStoppedAnimation(
                                      colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${_formatBytes(usedSpace)} / ${_formatBytes(totalSpace)}',
                                      style: textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      '${(value * 100).toStringAsFixed(1)}% used',
                                      style: textTheme.labelMedium?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
              .animate()
              .fadeIn(curve: M3Curves.emphasizedDecelerate)
              .slideY(begin: -0.05),
          const SizedBox(height: 16),
          // Section header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.storage_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Storage Devices',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          // Disk grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
            ),
            itemCount: disks.length,
            itemBuilder: (context, index) {
              final disk = disks[index];
              return _DiskCard(
                disk: disk,
                onTap: () {
                  ref
                      .read(currentPathProvider.notifier)
                      .setPath(disk.mountPoint);
                  setState(() => _showDisks = false);
                },
              )
                  .animate(delay: (80 * index).ms)
                  .fadeIn(curve: M3Curves.emphasizedDecelerate)
                  .scale(
                    begin: const Offset(0.95, 0.95),
                    curve: M3Curves.emphasized,
                  );
            },
          ),
        ]),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
    } else if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  Widget _buildFileContent(DirectoryListing listing) {
    final entries = _sortEntries(listing.entries);

    if (entries.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyFolderState());
    }

    if (_isGridView) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          12,
          8,
          12,
          100,
        ), // Bottom padding for FAB
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 110,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.82,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _FileGridItem(
              entry: entries[index],
              isSelected: _selectedFiles.contains(entries[index].path),
              onTap: () => _handleFileTap(entries[index]),
              onLongPress: () => _toggleSelection(entries[index].path),
            )
                .animate(delay: (40 * index).ms)
                .fadeIn(curve: M3Curves.emphasizedDecelerate)
                .scale(
                  begin: const Offset(0.95, 0.95),
                  curve: M3Curves.emphasized,
                ),
            childCount: entries.length,
          ),
        ),
      );
    } else {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          12,
          8,
          12,
          100,
        ), // Bottom padding for FAB
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _FileListItem(
              entry: entries[index],
              isSelected: _selectedFiles.contains(entries[index].path),
              onTap: () => _handleFileTap(entries[index]),
              onLongPress: () => _toggleSelection(entries[index].path),
              onDelete: () => _deleteFile(entries[index]),
            )
                .animate(delay: (30 * index).ms)
                .fadeIn(curve: M3Curves.emphasizedDecelerate)
                .slideX(begin: -0.02, curve: M3Curves.emphasized),
            childCount: entries.length,
          ),
        ),
      );
    }
  }

  Widget _buildLoadingState() {
    final colorScheme = Theme.of(context).colorScheme;

    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(child: CircularProgressIndicator()),
            ),
            const SizedBox(height: 20),
            Text(
              'Loading...',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentPath = ref.read(currentPathProvider);

    return SliverFillRemaining(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 44,
                  color: colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Failed to load files',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      ref.read(currentPathProvider.notifier).setPath('');
                      setState(() => _showDisks = true);
                    },
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Go Back'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () {
                      ref.invalidate(directoryListingProvider(currentPath));
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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

  Widget _buildEmptyDiskState() {
    final colorScheme = Theme.of(context).colorScheme;

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
              Icons.storage_rounded,
              size: 44,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No storage devices found',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect a storage device to get started',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFolderState() {
    final colorScheme = Theme.of(context).colorScheme;

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
              Icons.folder_open_rounded,
              size: 44,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'This folder is empty',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload files or create a new folder',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildFAB() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: 'new_folder',
          onPressed: _showCreateFolderDialog,
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
          child: const Icon(Icons.create_new_folder_rounded),
        ).animate().fadeIn(delay: 200.ms).scale(curve: M3Curves.emphasized),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'upload',
          onPressed: _pickAndUploadFiles,
          icon: const Icon(Icons.upload_rounded),
          label: const Text('Upload'),
        ).animate().fadeIn(delay: 100.ms).scale(curve: M3Curves.emphasized),
      ],
    );
  }

  List<FileEntry> _sortEntries(List<FileEntry> entries) {
    final sorted = List<FileEntry>.from(entries);
    sorted.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;

      int cmp;
      switch (_sortBy) {
        case 'size':
          cmp = a.size.compareTo(b.size);
          break;
        case 'modified':
          cmp = a.modified.compareTo(b.modified);
          break;
        case 'type':
          cmp = (a.mimeType ?? '').compareTo(b.mimeType ?? '');
          break;
        default:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _sortAsc ? cmp : -cmp;
    });
    return sorted;
  }

  void _handleFileTap(FileEntry entry) {
    if (_selectedFiles.isNotEmpty) {
      _toggleSelection(entry.path);
    } else if (entry.isDirectory) {
      final currentPath = ref.read(currentPathProvider);
      final newPath =
          currentPath.isEmpty ? entry.name : '$currentPath/${entry.name}';
      ref.read(currentPathProvider.notifier).setPath(newPath);
    } else {
      _showFileActions(entry);
    }
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedFiles.contains(path)) {
        _selectedFiles.remove(path);
      } else {
        _selectedFiles.add(path);
      }
    });
  }

  Future<void> _pickAndUploadFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      final api = ref.read(apiServiceProvider);
      final currentPath = ref.read(currentPathProvider);

      if (kIsWeb) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Web upload not yet implemented')),
          );
        }
      } else {
        final files = result.files
            .where((f) => f.path != null)
            .map((f) => File(f.path!))
            .toList();

        await api.uploadToDirectory(
          currentPath,
          files,
          onProgress: (sent, total) {
            setState(() => _uploadProgress = sent / total);
          },
        );
      }

      ref.invalidate(directoryListingProvider(currentPath));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 12),
                Text('Files uploaded successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _showCreateFolderDialog() {
    final controller = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.create_new_folder_rounded,
            size: 32,
            color: colorScheme.primary,
          ),
        ),
        title: const Text('Create Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Folder name',
            hintText: 'Enter folder name',
            prefixIcon: const Icon(Icons.folder_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                Navigator.pop(context);
                await _createFolder(controller.text);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createFolder(String name) async {
    try {
      final api = ref.read(apiServiceProvider);
      final currentPath = ref.read(currentPathProvider);
      await api.createDirectory(path: currentPath, name: name);
      ref.invalidate(directoryListingProvider(currentPath));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create folder: $e')));
      }
    }
  }

  /// Delete file with biometric/FIDO2 authentication
  Future<void> _deleteFile(FileEntry entry) async {
    final colorScheme = Theme.of(context).colorScheme;
    final biometricEnabled = ref.read(biometricEnabledProvider);
    final biometricService = ref.read(biometricServiceProvider);

    // First show confirmation dialog with authentication options
    final authMethod = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.error,
                colorScheme.error.withValues(alpha: 0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: colorScheme.error.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.delete_forever_rounded,
            size: 32,
            color: Colors.white,
          ),
        ),
        title: const Text('Delete File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${entry.name}"?',
              style: TextStyle(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_rounded,
                    color: colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This action cannot be undone',
                      style: TextStyle(
                        color: colorScheme.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Authentication Required',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            // Authentication options
            if (biometricEnabled) ...[
              _AuthOptionTile(
                icon: Icons.fingerprint_rounded,
                title: 'Biometric',
                subtitle: 'Use fingerprint or face',
                color: colorScheme.primary,
                onTap: () => Navigator.pop(context, 'biometric'),
              ),
              const SizedBox(height: 8),
            ],
            _AuthOptionTile(
              icon: Icons.key_rounded,
              title: 'Passkey / FIDO2',
              subtitle: 'Use security key',
              color: Colors.orange,
              onTap: () => Navigator.pop(context, 'fido2'),
            ),
            const SizedBox(height: 8),
            _AuthOptionTile(
              icon: Icons.password_rounded,
              title: 'Password',
              subtitle: 'Enter your password',
              color: Colors.blue,
              onTap: () => Navigator.pop(context, 'password'),
            ),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (authMethod == null) return;

    bool authenticated = false;

    // Perform authentication based on selected method
    switch (authMethod) {
      case 'biometric':
        final isAvailable = await biometricService.isAvailable();
        if (isAvailable) {
          authenticated = await biometricService.authenticate(
            reason: 'Authenticate to delete "${entry.name}"',
          );
        }
        break;
      case 'fido2':
        authenticated = await _authenticateWithFido2();
        break;
      case 'password':
        authenticated = await _authenticateWithPassword();
        break;
    }

    if (!authenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.white),
                const SizedBox(width: 12),
                const Text('Authentication failed'),
              ],
            ),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      return;
    }

    // Proceed with deletion
    try {
      final api = ref.read(apiServiceProvider);
      await api.deleteFiles([entry.path]);
      final currentPath = ref.read(currentPathProvider);
      ref.invalidate(directoryListingProvider(currentPath));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Text('"${entry.name}" deleted'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<bool> _authenticateWithFido2() async {
    // Show FIDO2 authentication dialog
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _Fido2AuthDialog(),
    );
    return result ?? false;
  }

  Future<bool> _authenticateWithPassword() async {
    final controller = TextEditingController();

    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.lock_rounded, size: 28, color: Colors.blue),
        ),
        title: const Text('Enter Password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.password_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Verify'),
          ),
        ],
      ),
    );

    if (password == null || password.isEmpty) return false;

    // Verify password with server
    try {
      final api = ref.read(apiServiceProvider);
      await api.post(
        '/api/v1/auth/verify-password',
        data: {'password': password},
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  void _showFileActions(FileEntry entry) {
    final mimeType = entry.mimeType ?? '';
    final isImage = mimeType.startsWith('image/');
    final isVideo = mimeType.startsWith('video/');
    final isAudio = mimeType.startsWith('audio/');
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  _getFileIcon(entry, 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatFileSize(entry.size),
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            if (isImage || isVideo || isAudio)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isImage
                        ? Icons.image_rounded
                        : isVideo
                            ? Icons.play_circle_rounded
                            : Icons.audiotrack_rounded,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                title: Text(isImage ? 'View' : 'Play'),
                onTap: () {
                  Navigator.pop(context);
                  _openMediaPreview(entry);
                },
              ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.download_rounded, color: Colors.blue),
              ),
              title: const Text('Download'),
              onTap: () {
                Navigator.pop(context);
                _downloadFile(entry);
              },
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_rounded, color: Colors.orange),
              ),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(entry);
              },
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.delete_rounded, color: colorScheme.error),
              ),
              title: Text('Delete', style: TextStyle(color: colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                _deleteFile(entry);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _openMediaPreview(FileEntry entry) {
    final api = ref.read(apiServiceProvider);
    final mimeType = entry.mimeType ?? '';

    if (mimeType.startsWith('image/')) {
      // Open image viewer
      final imageUrl = api.getImageUrl(entry.path);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ImageViewerPage(imageUrl: imageUrl, fileName: entry.name),
        ),
      );
    } else if (mimeType.startsWith('video/') || mimeType.startsWith('audio/')) {
      // Open media player
      final streamUrl = api.getMediaStreamUrl(entry.path);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MediaPlayerPage(
            mediaUrl: streamUrl,
            fileName: entry.name,
            isVideo: mimeType.startsWith('video/'),
          ),
        ),
      );
    }
  }

  Future<void> _downloadFile(FileEntry entry) async {
    final api = ref.read(apiServiceProvider);
    final downloadUrl = api.getFileManagerDownloadUrl(entry.path);

    try {
      final uri = Uri.parse(downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Download URL: $downloadUrl'),
              action: SnackBarAction(
                label: 'Copy',
                onPressed: () {
                  // Copy to clipboard
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to download: $e')));
      }
    }
  }

  void _showRenameDialog(FileEntry entry) {
    final controller = TextEditingController(text: entry.name);
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.edit_rounded, size: 32, color: colorScheme.primary),
        ),
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'New name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.isNotEmpty && controller.text != entry.name) {
                Navigator.pop(context);
                try {
                  final api = ref.read(apiServiceProvider);
                  await api.renameFile(
                    oldPath: entry.path,
                    newName: controller.text,
                  );
                  final currentPath = ref.read(currentPathProvider);
                  ref.invalidate(directoryListingProvider(currentPath));
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to rename: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Widget _getFileIcon(FileEntry entry, double size) {
    final colorScheme = Theme.of(context).colorScheme;
    final mimeType = entry.mimeType ?? '';

    IconData icon;
    Color bgColor;
    Color iconColor;

    if (entry.isDirectory) {
      icon = Icons.folder_rounded;
      bgColor = colorScheme.primaryContainer;
      iconColor = colorScheme.onPrimaryContainer;
    } else if (mimeType.startsWith('image/')) {
      icon = Icons.image_rounded;
      bgColor = Colors.pink.withValues(alpha: 0.15);
      iconColor = Colors.pink;
    } else if (mimeType.startsWith('video/')) {
      icon = Icons.movie_rounded;
      bgColor = Colors.purple.withValues(alpha: 0.15);
      iconColor = Colors.purple;
    } else if (mimeType.startsWith('audio/')) {
      icon = Icons.audiotrack_rounded;
      bgColor = Colors.orange.withValues(alpha: 0.15);
      iconColor = Colors.orange;
    } else if (mimeType.contains('pdf')) {
      icon = Icons.picture_as_pdf_rounded;
      bgColor = Colors.red.withValues(alpha: 0.15);
      iconColor = Colors.red;
    } else if (mimeType.contains('zip') || mimeType.contains('archive')) {
      icon = Icons.folder_zip_rounded;
      bgColor = Colors.amber.withValues(alpha: 0.15);
      iconColor = Colors.amber.shade700;
    } else {
      icon = Icons.insert_drive_file_rounded;
      bgColor = colorScheme.surfaceContainerHighest;
      iconColor = colorScheme.onSurfaceVariant;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Icon(icon, color: iconColor, size: size * 0.5),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

// ============ Widget Components ============

class _BreadcrumbChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _BreadcrumbChip({
    this.icon,
    required this.label,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isActive ? colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: isActive
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiskCard extends StatelessWidget {
  final DiskInfo disk;
  final VoidCallback onTap;

  const _DiskCard({required this.disk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final usageColor = _getUsageColor(disk.usagePercentage);
    final diskIcon = _getDiskIcon();
    final diskTypeLabel = _getDiskTypeLabel();

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with icon and type badge
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: disk.isRemovable
                            ? [
                                Colors.orange.shade400,
                                Colors.deepOrange.shade400,
                              ]
                            : [colorScheme.primary, colorScheme.tertiary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: (disk.isRemovable
                                  ? Colors.orange
                                  : colorScheme.primary)
                              .withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(diskIcon, size: 24, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          disk.name.isNotEmpty ? disk.name : _getDisplayName(),
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: disk.isRemovable
                                    ? Colors.orange.withValues(alpha: 0.15)
                                    : colorScheme.primaryContainer.withValues(
                                        alpha: 0.5,
                                      ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                diskTypeLabel,
                                style: textTheme.labelSmall?.copyWith(
                                  color: disk.isRemovable
                                      ? Colors.orange.shade700
                                      : colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (disk.fileSystem.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  disk.fileSystem.toUpperCase(),
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Storage bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: disk.usagePercentage / 100),
                    duration: M3Durations.long2,
                    curve: M3Curves.emphasized,
                    builder: (context, value, child) {
                      return Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: value,
                              minHeight: 10,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation(usageColor),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: usageColor,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${_formatBytes(disk.usedSpace)} used',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '${(value * 100).toStringAsFixed(1)}%',
                                style: textTheme.labelLarge?.copyWith(
                                  color: usageColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Footer with storage details
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _StorageMetric(
                        icon: Icons.check_circle_outline_rounded,
                        label: 'Free',
                        value: _formatBytes(disk.availableSpace),
                        color: Colors.green,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 32,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    Expanded(
                      child: _StorageMetric(
                        icon: Icons.storage_rounded,
                        label: 'Total',
                        value: _formatBytes(disk.totalSpace),
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getDiskIcon() {
    if (disk.isRemovable) {
      if (disk.diskType.toLowerCase().contains('usb')) {
        return Icons.usb_rounded;
      }
      return Icons.sd_card_rounded;
    }
    if (disk.diskType.toLowerCase().contains('ssd')) {
      return Icons.memory_rounded;
    }
    return Icons.storage_rounded;
  }

  String _getDiskTypeLabel() {
    if (disk.isRemovable) {
      if (disk.diskType.toLowerCase().contains('usb')) return 'USB';
      return 'Removable';
    }
    if (disk.diskType.toLowerCase().contains('ssd')) return 'SSD';
    if (disk.diskType.toLowerCase().contains('hdd')) return 'HDD';
    return 'Internal';
  }

  String _getDisplayName() {
    if (disk.mountPoint == '/') return 'System';
    if (disk.mountPoint == '/boot') return 'Boot';
    if (disk.mountPoint.startsWith('/mnt/')) {
      return disk.mountPoint.split('/').last;
    }
    if (disk.mountPoint.startsWith('/media/')) {
      return disk.mountPoint.split('/').last;
    }
    return disk.mountPoint.split('/').last;
  }

  Color _getUsageColor(double usage) {
    if (usage >= 90) return Colors.red;
    if (usage >= 70) return Colors.orange;
    if (usage >= 50) return Colors.amber.shade700;
    return Colors.green;
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TB';
    } else if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
}

class _StorageMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StorageMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
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
              style: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FileGridItem extends StatelessWidget {
  final FileEntry entry;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FileGridItem({
    required this.entry,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildIcon(context),
              const SizedBox(height: 10),
              Text(
                entry.name,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: isSelected ? colorScheme.onPrimaryContainer : null,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mimeType = entry.mimeType ?? '';

    IconData icon;
    Color bgColor;
    Color iconColor;

    if (entry.isDirectory) {
      icon = Icons.folder_rounded;
      bgColor = colorScheme.primaryContainer;
      iconColor = colorScheme.onPrimaryContainer;
    } else if (mimeType.startsWith('image/')) {
      icon = Icons.image_rounded;
      bgColor = Colors.pink.withValues(alpha: 0.15);
      iconColor = Colors.pink;
    } else if (mimeType.startsWith('video/')) {
      icon = Icons.movie_rounded;
      bgColor = Colors.purple.withValues(alpha: 0.15);
      iconColor = Colors.purple;
    } else if (mimeType.startsWith('audio/')) {
      icon = Icons.audiotrack_rounded;
      bgColor = Colors.orange.withValues(alpha: 0.15);
      iconColor = Colors.orange;
    } else {
      icon = Icons.insert_drive_file_rounded;
      bgColor = colorScheme.surfaceContainerHighest;
      iconColor = colorScheme.onSurfaceVariant;
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: iconColor, size: 26),
    );
  }
}

class _FileListItem extends StatelessWidget {
  final FileEntry entry;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  const _FileListItem({
    required this.entry,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _buildIcon(context),
        title: Text(
          entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: isSelected ? colorScheme.onPrimaryContainer : null,
          ),
        ),
        subtitle: Text(
          entry.isDirectory ? 'Folder' : _formatFileSize(entry.size),
          style: textTheme.bodySmall?.copyWith(
            color: isSelected
                ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                : colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: entry.isDirectory
            ? Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              )
            : IconButton(
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: onTap,
              ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mimeType = entry.mimeType ?? '';

    IconData icon;
    Color bgColor;
    Color iconColor;

    if (entry.isDirectory) {
      icon = Icons.folder_rounded;
      bgColor = colorScheme.primaryContainer;
      iconColor = colorScheme.onPrimaryContainer;
    } else if (mimeType.startsWith('image/')) {
      icon = Icons.image_rounded;
      bgColor = Colors.pink.withValues(alpha: 0.15);
      iconColor = Colors.pink;
    } else if (mimeType.startsWith('video/')) {
      icon = Icons.movie_rounded;
      bgColor = Colors.purple.withValues(alpha: 0.15);
      iconColor = Colors.purple;
    } else if (mimeType.startsWith('audio/')) {
      icon = Icons.audiotrack_rounded;
      bgColor = Colors.orange.withValues(alpha: 0.15);
      iconColor = Colors.orange;
    } else {
      icon = Icons.insert_drive_file_rounded;
      bgColor = colorScheme.surfaceContainerHighest;
      iconColor = colorScheme.onSurfaceVariant;
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: iconColor, size: 24),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

// ============ Media Preview Pages ============

class _AuthOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AuthOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fido2AuthDialog extends StatefulWidget {
  @override
  State<_Fido2AuthDialog> createState() => _Fido2AuthDialogState();
}

class _Fido2AuthDialogState extends State<_Fido2AuthDialog> {
  bool _isAuthenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startAuthentication();
  }

  Future<void> _startAuthentication() async {
    setState(() {
      _isAuthenticating = true;
      _error = null;
    });

    // Simulate FIDO2 authentication - in real implementation, this would
    // call the platform-specific FIDO2 APIs
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      // For demo purposes, always succeed
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.orange, Colors.deepOrange],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: _isAuthenticating
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            : const Icon(Icons.key_rounded, size: 36, color: Colors.white),
      ),
      title: Text(
        _isAuthenticating ? 'Authenticating...' : 'FIDO2 Authentication',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isAuthenticating) ...[
            Text(
              'Please use your security key or passkey to authenticate',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Touch your security key',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ] else if (_error != null) ...[
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.error),
            ),
          ],
        ],
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        if (_error != null)
          FilledButton(
            onPressed: _startAuthentication,
            child: const Text('Retry'),
          ),
      ],
    );
  }
}
