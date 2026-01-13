import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/theme/app_theme.dart';

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
    final result = await api.listDirectory(path: path.isEmpty ? null : path);
    ref.read(fileErrorProvider.notifier).setError(null);
    return result;
  } catch (e) {
    ref.read(fileErrorProvider.notifier).setError(e.toString());
    return null;
  }
});

// Disk info provider
final diskInfoProvider =
    FutureProvider.autoDispose<List<DiskInfo>>((ref) async {
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

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: M3Durations.medium2,
    );
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
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
                      errorMessage ?? 'Failed to load files');
                }
                return _buildFileContent(data);
              },
              loading: () => _buildLoadingState(),
              error: (e, s) => _buildErrorState(e.toString()),
            ),
        ],
      ),
      floatingActionButton: showDiskView ? null : _buildFAB(),
    );
  }

  Widget _buildAppBar(bool showDiskView, String currentPath) {
    return SliverAppBar.large(
      title: Row(
        children: [
          Icon(
            showDiskView ? Icons.storage_rounded : Icons.folder_rounded,
            size: 28,
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
                  'modified', 'Modified', Icons.schedule_rounded),
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
      String value, String label, IconData icon) {
    final isSelected = _sortBy == value;
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: isSelected ? colorScheme.primary : null),
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
    final parts = path.isEmpty ? <String>[] : path.split('/');
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            ...parts.asMap().entries.map((entry) {
              final index = entry.key;
              final part = entry.value;
              final fullPath = parts.sublist(0, index + 1).join('/');
              final isLast = index == parts.length - 1;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.cloud_upload_rounded,
                  color: colorScheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Uploading... ${(_uploadProgress * 100).toInt()}%',
                  style: TextStyle(color: colorScheme.onPrimaryContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _uploadProgress,
              minHeight: 8,
              backgroundColor:
                  colorScheme.onPrimaryContainer.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiskGrid(List<DiskInfo> disks) {
    if (disks.isEmpty) {
      return SliverFillRemaining(
        child: _buildEmptyDiskState(),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 400,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final disk = disks[index];
            return _DiskCard(
              disk: disk,
              onTap: () {
                ref.read(currentPathProvider.notifier).setPath(disk.mountPoint);
                setState(() => _showDisks = false);
              },
            )
                .animate(delay: (80 * index).ms)
                .fadeIn(curve: M3Curves.emphasizedDecelerate)
                .scale(
                    begin: const Offset(0.92, 0.92),
                    curve: M3Curves.emphasized);
          },
          childCount: disks.length,
        ),
      ),
    );
  }

  Widget _buildFileContent(DirectoryListing listing) {
    final entries = _sortEntries(listing.entries);

    if (entries.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyFolderState());
    }

    if (_isGridView) {
      return SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
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
                    curve: M3Curves.emphasized),
            childCount: entries.length,
          ),
        ),
      );
    } else {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
    return const SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
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
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 40,
                  color: colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Failed to load files',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
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
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () {
                      ref.invalidate(directoryListingProvider(currentPath));
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
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
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.storage_rounded,
              size: 40,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No storage devices found',
            style: Theme.of(context).textTheme.titleMedium,
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
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.folder_open_rounded,
              size: 40,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'This folder is empty',
            style: Theme.of(context).textTheme.titleMedium,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: 'new_folder',
          onPressed: _showCreateFolderDialog,
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
          const SnackBar(content: Text('Files uploaded successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
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
        icon: Icon(Icons.create_new_folder_rounded,
            size: 48, color: colorScheme.primary),
        title: const Text('Create Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder name',
            hintText: 'Enter folder name',
            prefixIcon: Icon(Icons.folder_rounded),
          ),
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create folder: $e')),
        );
      }
    }
  }

  Future<void> _deleteFile(FileEntry entry) async {
    final colorScheme = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.delete_rounded, size: 48, color: colorScheme.error),
        title: const Text('Delete'),
        content: Text('Are you sure you want to delete "${entry.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final api = ref.read(apiServiceProvider);
        await api.deleteFiles([entry.path]);
        final currentPath = ref.read(currentPathProvider);
        ref.invalidate(directoryListingProvider(currentPath));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  void _showFileActions(FileEntry entry) {
    final mimeType = entry.mimeType ?? '';
    final isImage = mimeType.startsWith('image/');
    final isVideo = mimeType.startsWith('video/');
    final isAudio = mimeType.startsWith('audio/');
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  _getFileIcon(entry, 48),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
            const Divider(height: 1),
            if (isImage || isVideo || isAudio)
              ListTile(
                leading: Icon(
                  isImage
                      ? Icons.image_rounded
                      : isVideo
                          ? Icons.play_circle_rounded
                          : Icons.audiotrack_rounded,
                ),
                title: Text(isImage ? 'View' : 'Play'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Implement media preview
                },
              ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Download'),
              onTap: () {
                Navigator.pop(context);
                _downloadFile(entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(entry);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_rounded, color: colorScheme.error),
              title: Text('Delete', style: TextStyle(color: colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                _deleteFile(entry);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _downloadFile(FileEntry entry) {
    final api = ref.read(apiServiceProvider);
    final downloadUrl = api.getFileManagerDownloadUrl(entry.path);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Download: ${entry.name}'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () {
            debugPrint('Download URL: $downloadUrl');
          },
        ),
      ),
    );
  }

  void _showRenameDialog(FileEntry entry) {
    final controller = TextEditingController(text: entry.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
        ),
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
                      oldPath: entry.path, newName: controller.text);
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
      color: isActive ? colorScheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 18,
                    color: isActive
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.primary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.primary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Circular progress indicator
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: disk.usagePercentage / 100,
                      strokeWidth: 8,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(usageColor),
                      strokeCap: StrokeCap.round,
                    ),
                    Text(
                      '${disk.usagePercentage.toStringAsFixed(0)}%',
                      style: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: usageColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Icon(
                          disk.isRemovable
                              ? Icons.usb_rounded
                              : Icons.storage_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            disk.name.isNotEmpty ? disk.name : disk.mountPoint,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      disk.mountPoint,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_formatBytes(disk.availableSpace)} free of ${_formatBytes(disk.totalSpace)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
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
      color: isSelected ? colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildIcon(context),
              const SizedBox(height: 8),
              Text(
                entry.name,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: iconColor, size: 28),
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
      color: isSelected ? colorScheme.primaryContainer : null,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        leading: _buildIcon(context),
        title: Text(
          entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          entry.isDirectory ? 'Folder' : _formatFileSize(entry.size),
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: entry.isDirectory
            ? Icon(Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant)
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
