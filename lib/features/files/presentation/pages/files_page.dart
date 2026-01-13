import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';

// Current path notifier for Riverpod 3.x
class CurrentPathNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setPath(String path) => state = path;
}

final currentPathProvider = NotifierProvider<CurrentPathNotifier, String>(
  CurrentPathNotifier.new,
);

final directoryListingProvider = FutureProvider.autoDispose
    .family<DirectoryListing?, String>((ref, path) async {
  try {
    final api = ref.read(apiServiceProvider);
    return await api.listDirectory(path: path.isEmpty ? null : path);
  } catch (_) {
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
  } catch (_) {
    return [];
  }
});

class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key});

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  bool _isGridView = true;
  String _sortBy = 'name';
  bool _sortAsc = true;
  final Set<String> _selectedFiles = {};
  bool _isUploading = false;
  double _uploadProgress = 0;
  bool _showDisks = true; // Start with disk view

  @override
  Widget build(BuildContext context) {
    final currentPath = ref.watch(currentPathProvider);
    final listing = ref.watch(directoryListingProvider(currentPath));
    final disks = ref.watch(diskInfoProvider);

    // Show disk view when at root (empty path)
    final showDiskView = _showDisks && currentPath.isEmpty;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: Text(showDiskView ? 'Storage' : 'Files'),
            actions: [
              if (!showDiskView) ...[
                IconButton(
                  icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.sort),
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
                    const PopupMenuItem(value: 'name', child: Text('Name')),
                    const PopupMenuItem(value: 'size', child: Text('Size')),
                    const PopupMenuItem(
                      value: 'modified',
                      child: Text('Modified'),
                    ),
                    const PopupMenuItem(value: 'type', child: Text('Type')),
                  ],
                ),
              ],
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  if (showDiskView) {
                    ref.invalidate(diskInfoProvider);
                  } else {
                    ref.invalidate(directoryListingProvider(currentPath));
                  }
                },
              ),
            ],
          ),
          if (!showDiskView)
            SliverToBoxAdapter(child: _buildBreadcrumb(currentPath)),
          if (_isUploading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    LinearProgressIndicator(value: _uploadProgress),
                    const SizedBox(height: 8),
                    Text('Uploading... ${(_uploadProgress * 100).toInt()}%'),
                  ],
                ),
              ),
            ),
          // Show disk view or file list based on current state
          if (showDiskView)
            disks.when(
              data: (diskList) => _buildDiskList(diskList),
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, s) => SliverFillRemaining(child: _buildErrorState()),
            )
          else
            listing.when(
              data: (data) {
                if (data == null) {
                  return SliverFillRemaining(child: _buildErrorState());
                }
                return _buildFileList(data);
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, s) => SliverFillRemaining(child: _buildErrorState()),
            ),
        ],
      ),
      floatingActionButton: showDiskView
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'new_folder',
                  onPressed: () => _showCreateFolderDialog(),
                  child: const Icon(Icons.create_new_folder),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'upload',
                  onPressed: _pickAndUploadFiles,
                  icon: const Icon(Icons.upload),
                  label: const Text('Upload'),
                ),
              ],
            ),
    );
  }

  Widget _buildBreadcrumb(String path) {
    final parts = path.isEmpty ? <String>[] : path.split('/');
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              onTap: () {
                ref.read(currentPathProvider.notifier).setPath('');
                setState(() => _showDisks = true);
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.storage, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Storage',
                      style: TextStyle(color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
            ...parts.asMap().entries.map((entry) {
              final index = entry.key;
              final part = entry.value;
              final fullPath = parts.sublist(0, index + 1).join('/');
              final isLast = index == parts.length - 1;

              return Row(
                children: [
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  InkWell(
                    onTap: isLast
                        ? null
                        : () => ref
                            .read(currentPathProvider.notifier)
                            .setPath(fullPath),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        part,
                        style: TextStyle(
                          color: isLast
                              ? colorScheme.onSurface
                              : colorScheme.primary,
                          fontWeight:
                              isLast ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDiskList(List<DiskInfo> disks) {
    if (disks.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.storage,
                size: 64,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No storage devices found',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    // Windows-style grid layout for disks
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.2,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final disk = disks[index];
          return _WindowsDiskCard(
            disk: disk,
            onTap: () {
              ref.read(currentPathProvider.notifier).setPath(disk.mountPoint);
              setState(() => _showDisks = false);
            },
          )
              .animate(delay: (50 * index).ms)
              .fadeIn()
              .scale(begin: const Offset(0.95, 0.95));
        }, childCount: disks.length),
      ),
    );
  }

  Widget _buildFileList(DirectoryListing listing) {
    final entries = _sortEntries(listing.entries);

    if (entries.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyState());
    }

    if (_isGridView) {
      return SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
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
                .animate(delay: (50 * index).ms)
                .fadeIn()
                .scale(begin: const Offset(0.95, 0.95)),
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
            ).animate(delay: (30 * index).ms).fadeIn().slideX(begin: -0.02),
            childCount: entries.length,
          ),
        ),
      );
    }
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
        // Web platform handling
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _showCreateFolderDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder name',
            hintText: 'Enter folder name',
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create folder: $e')));
      }
    }
  }

  Future<void> _deleteFile(FileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Are you sure you want to delete "${entry.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
  }

  void _showFileActions(FileEntry entry) {
    final mimeType = entry.mimeType ?? '';
    final isImage = mimeType.startsWith('image/');
    final isVideo = mimeType.startsWith('video/');
    final isAudio = mimeType.startsWith('audio/');
    final isText = _isTextFile(entry.name, mimeType);
    final isMedia = isImage || isVideo || isAudio;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Preview option for text files
            if (isText)
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('View Content'),
                onTap: () {
                  Navigator.pop(context);
                  _openTextPreview(entry);
                },
              ),
            // Preview option for media files
            if (isMedia)
              ListTile(
                leading: Icon(
                  isImage
                      ? Icons.image
                      : (isVideo ? Icons.play_circle : Icons.audiotrack),
                ),
                title: Text(
                  isImage
                      ? 'View Image'
                      : (isVideo ? 'Play Video' : 'Play Audio'),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openMediaPreview(entry);
                },
              ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Download'),
              onTap: () {
                Navigator.pop(context);
                _downloadFile(entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(entry);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteFile(entry);
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _isTextFile(String filename, String mimeType) {
    final textExtensions = [
      'txt',
      'md',
      'json',
      'xml',
      'yaml',
      'yml',
      'toml',
      'ini',
      'cfg',
      'conf',
      'log',
      'csv',
      'html',
      'htm',
      'css',
      'js',
      'ts',
      'jsx',
      'tsx',
      'vue',
      'py',
      'rs',
      'go',
      'java',
      'c',
      'cpp',
      'h',
      'hpp',
      'sh',
      'bash',
      'zsh',
      'sql',
      'dockerfile',
      'makefile',
      'gitignore',
      'env',
      'properties',
    ];
    final ext = filename.split('.').last.toLowerCase();
    return textExtensions.contains(ext) || mimeType.startsWith('text/');
  }

  void _openTextPreview(FileEntry entry) async {
    final api = ref.read(apiServiceProvider);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final preview = await api.previewTextFile(entry.path);
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      showDialog(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(entry.name),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                if (preview.truncated)
                  Chip(
                    label: const Text('Truncated'),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.errorContainer,
                  ),
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: () {
                    Navigator.pop(context);
                    _downloadFile(entry);
                  },
                ),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                preview.content,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to preview file: $e')));
    }
  }

  void _openMediaPreview(FileEntry entry) {
    final api = ref.read(apiServiceProvider);
    final mimeType = entry.mimeType ?? '';

    if (mimeType.startsWith('image/')) {
      _openImageViewer(entry, api);
    } else if (mimeType.startsWith('video/') || mimeType.startsWith('audio/')) {
      _openMediaPlayer(entry, api, mimeType);
    }
  }

  void _openImageViewer(FileEntry entry, ApiService api) {
    final imageUrl = api.getImageUrl(entry.path);

    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black.withValues(alpha: 0.7),
            foregroundColor: Colors.white,
            title: Text(entry.name),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: () {
                  Navigator.pop(context);
                  _downloadFile(entry);
                },
              ),
            ],
          ),
          body: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                headers: _getAuthHeaders(api),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                      color: Colors.white,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _downloadFile(entry);
                          },
                          icon: const Icon(Icons.download),
                          label: const Text('Download instead'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openMediaPlayer(FileEntry entry, ApiService api, String mimeType) {
    final streamUrl = api.getMediaStreamUrl(entry.path);
    final isVideo = mimeType.startsWith('video/');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _MediaPlayerPage(
          entry: entry,
          streamUrl: streamUrl,
          isVideo: isVideo,
          onDownload: () => _downloadFile(entry),
        ),
      ),
    );
  }

  Map<String, String> _getAuthHeaders(ApiService api) {
    // Headers will be added by the API client interceptor
    return {};
  }

  void _downloadFile(FileEntry entry) {
    final api = ref.read(apiServiceProvider);
    final downloadUrl = api.getFileManagerDownloadUrl(entry.path);
    // For now, just show the URL - in production, use url_launcher or download manager
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Download: ${entry.name}'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () {
            // Open URL in browser or download manager
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

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
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

  Widget _buildErrorState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: colorScheme.error),
          const SizedBox(height: 16),
          Text(
            'Failed to load files',
            style: TextStyle(color: colorScheme.error),
          ),
        ],
      ),
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

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                entry.isDirectory ? Icons.folder : _getFileIcon(entry.mimeType),
                size: 48,
                color: entry.isDirectory
                    ? Colors.amber
                    : _getFileColor(entry.mimeType),
              ),
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
              if (!entry.isDirectory) ...[
                const SizedBox(height: 4),
                Text(
                  _formatBytes(entry.size),
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _getFileIcon(String? mimeType) {
    if (mimeType == null) return Icons.insert_drive_file;
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.startsWith('audio/')) return Icons.audio_file;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('zip') || mimeType.contains('rar')) {
      return Icons.folder_zip;
    }
    return Icons.insert_drive_file;
  }

  Color _getFileColor(String? mimeType) {
    if (mimeType == null) return Colors.grey;
    if (mimeType.startsWith('image/')) return Colors.blue;
    if (mimeType.startsWith('video/')) return Colors.purple;
    if (mimeType.startsWith('audio/')) return Colors.orange;
    if (mimeType.contains('pdf')) return Colors.red;
    return Colors.grey;
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
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

    return ListTile(
      selected: isSelected,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
      onTap: onTap,
      onLongPress: onLongPress,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: entry.isDirectory
              ? Colors.amber.withValues(alpha: 0.1)
              : _getFileColor(entry.mimeType).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          entry.isDirectory ? Icons.folder : _getFileIcon(entry.mimeType),
          color:
              entry.isDirectory ? Colors.amber : _getFileColor(entry.mimeType),
        ),
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        entry.isDirectory
            ? 'Folder'
            : '${_formatBytes(entry.size)} • ${_formatDate(entry.modified)}',
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: entry.isDirectory
          ? const Icon(Icons.chevron_right)
          : IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
    );
  }

  IconData _getFileIcon(String? mimeType) {
    if (mimeType == null) return Icons.insert_drive_file;
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.startsWith('audio/')) return Icons.audio_file;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    return Icons.insert_drive_file;
  }

  Color _getFileColor(String? mimeType) {
    if (mimeType == null) return Colors.grey;
    if (mimeType.startsWith('image/')) return Colors.blue;
    if (mimeType.startsWith('video/')) return Colors.purple;
    if (mimeType.startsWith('audio/')) return Colors.orange;
    if (mimeType.contains('pdf')) return Colors.red;
    return Colors.grey;
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('MMM d, yyyy').format(date);
  }
}

// Windows-style Disk card widget
class _WindowsDiskCard extends StatelessWidget {
  final DiskInfo disk;
  final VoidCallback onTap;

  const _WindowsDiskCard({required this.disk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final usedPercent = disk.usagePercentage;
    final isAlmostFull = usedPercent > 90;
    final isWarning = usedPercent > 75;

    // Progress bar color like Windows
    final progressColor = isAlmostFull
        ? Colors.red
        : isWarning
            ? Colors.orange
            : Colors.blue;

    return Card(
      elevation: isDark ? 0 : 1,
      color: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Disk icon (Windows style)
              _buildDiskIcon(context),
              const SizedBox(width: 12),
              // Disk info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Disk name with mount point
                    Text(
                      _getDiskDisplayName(disk),
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Progress bar (Windows style)
                    Container(
                      height: 16,
                      decoration: BoxDecoration(
                        color: isDark
                            ? colorScheme.surfaceContainerHighest
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Stack(
                          children: [
                            FractionallySizedBox(
                              widthFactor: usedPercent / 100,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: progressColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Storage info text (Windows style: "XXX GB 可用, 共 XXX GB")
                    Text(
                      '${_formatBytes(disk.availableSpace)} free of ${_formatBytes(disk.totalSpace)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
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

  Widget _buildDiskIcon(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    IconData icon;
    Color iconColor;

    if (disk.mountPoint == '/' ||
        disk.mountPoint.toLowerCase().contains('system')) {
      // System drive - Windows logo style
      icon = Icons.window;
      iconColor = Colors.blue;
    } else if (disk.mountPoint == '/boot') {
      icon = Icons.settings;
      iconColor = Colors.purple;
    } else if (disk.isRemovable) {
      icon = Icons.usb;
      iconColor = Colors.green;
    } else {
      // Regular HDD
      icon = Icons.storage;
      iconColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 32, color: iconColor),
    );
  }

  String _getDiskDisplayName(DiskInfo disk) {
    String name;
    String mountPoint = disk.mountPoint;

    if (mountPoint == '/') {
      name = 'System';
    } else if (mountPoint == '/boot') {
      name = 'Boot';
    } else if (disk.name.isNotEmpty && disk.name != 'Unknown') {
      name = disk.name;
    } else if (mountPoint.startsWith('/mnt/')) {
      name = mountPoint.split('/').last;
    } else if (mountPoint.startsWith('/media/')) {
      name = mountPoint.split('/').last;
    } else {
      name = 'Local Disk';
    }

    // Format like Windows: "Name (X:)" -> "Name (mount_point)"
    return '$name ($mountPoint)';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }
}

// Disk card widget for storage view (legacy, kept for reference)
// ignore: unused_element
class _DiskCard extends StatelessWidget {
  final DiskInfo disk;
  final VoidCallback onTap;

  const _DiskCard({required this.disk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Determine disk icon and color based on type
    final (IconData icon, Color color) = _getDiskIconAndColor(disk);

    final usedPercent = disk.usagePercentage;
    final isAlmostFull = usedPercent > 90;
    final isWarning = usedPercent > 75;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
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
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getDiskDisplayName(disk),
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          disk.mountPoint,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Storage usage bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: usedPercent / 100,
                  minHeight: 8,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isAlmostFull
                        ? colorScheme.error
                        : isWarning
                            ? Colors.orange
                            : colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_formatBytes(disk.usedSpace)} used',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${_formatBytes(disk.availableSpace)} free',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    _formatBytes(disk.totalSpace),
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Disk info chips
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _InfoChip(
                    label: disk.fileSystem,
                    icon: Icons.description_outlined,
                  ),
                  _InfoChip(label: disk.diskType, icon: Icons.memory),
                  if (disk.isRemovable)
                    _InfoChip(
                      label: 'Removable',
                      icon: Icons.usb,
                      color: Colors.orange,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color) _getDiskIconAndColor(DiskInfo disk) {
    if (disk.mountPoint == '/') {
      return (Icons.computer, Colors.blue);
    } else if (disk.mountPoint == '/boot') {
      return (Icons.settings_applications, Colors.purple);
    } else if (disk.isRemovable) {
      return (Icons.usb, Colors.orange);
    } else if (disk.diskType.toLowerCase().contains('ssd')) {
      return (Icons.flash_on, Colors.green);
    } else {
      return (Icons.storage, Colors.teal);
    }
  }

  String _getDiskDisplayName(DiskInfo disk) {
    if (disk.mountPoint == '/') {
      return 'System';
    } else if (disk.mountPoint == '/boot') {
      return 'Boot';
    } else if (disk.name.isNotEmpty && disk.name != 'Unknown') {
      return disk.name;
    } else if (disk.mountPoint.startsWith('/mnt/')) {
      return disk.mountPoint.split('/').last;
    } else if (disk.mountPoint.startsWith('/media/')) {
      return disk.mountPoint.split('/').last;
    }
    return disk.mountPoint;
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;

  const _InfoChip({required this.label, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chipColor = color ?? colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: chipColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ============ Media Player Page ============

class _MediaPlayerPage extends StatefulWidget {
  final FileEntry entry;
  final String streamUrl;
  final bool isVideo;
  final VoidCallback onDownload;

  const _MediaPlayerPage({
    required this.entry,
    required this.streamUrl,
    required this.isVideo,
    required this.onDownload,
  });

  @override
  State<_MediaPlayerPage> createState() => _MediaPlayerPageState();
}

class _MediaPlayerPageState extends State<_MediaPlayerPage> {
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _hasError = false;
  double _currentPosition = 0;
  double _duration = 0;
  double _volume = 1.0;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    // In a real implementation, you would initialize video_player or audioplayers here
    // For now, we'll show a placeholder that indicates the stream URL
    try {
      setState(() {
        _isLoading = false;
        _duration = 100; // Placeholder duration
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: widget.isVideo ? Colors.black : colorScheme.surface,
      appBar: AppBar(
        backgroundColor:
            widget.isVideo ? Colors.black.withValues(alpha: 0.7) : null,
        foregroundColor: widget.isVideo ? Colors.white : null,
        title: Text(
          widget.entry.name,
          style: TextStyle(
            color: widget.isVideo ? Colors.white : null,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              Navigator.pop(context);
              widget.onDownload();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Video/Audio display area
          Expanded(
            child: _buildMediaDisplay(),
          ),
          // Controls
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildMediaDisplay() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: widget.isVideo ? Colors.white54 : Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load media',
              style: TextStyle(
                color: widget.isVideo ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                widget.onDownload();
              },
              icon: const Icon(Icons.download),
              label: const Text('Download instead'),
            ),
          ],
        ),
      );
    }

    if (widget.isVideo) {
      // Video placeholder - in production, use video_player package
      return GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Container(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  size: 80,
                  color: Colors.white70,
                ),
                const SizedBox(height: 16),
                Text(
                  widget.entry.name,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Stream URL: ${widget.streamUrl}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Video playback requires video_player package',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Audio player UI
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.music_note,
                size: 100,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              widget.entry.name,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Audio file',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildControls() {
    final colorScheme = Theme.of(context).colorScheme;
    final isVideo = widget.isVideo;
    final controlColor = isVideo ? Colors.white : colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(16),
      color: isVideo ? Colors.black.withValues(alpha: 0.8) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
          Row(
            children: [
              Text(
                _formatDuration(_currentPosition),
                style: TextStyle(color: controlColor, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: _currentPosition,
                  max: _duration > 0 ? _duration : 1,
                  onChanged: (value) {
                    setState(() => _currentPosition = value);
                  },
                  activeColor: isVideo ? Colors.white : colorScheme.primary,
                  inactiveColor: isVideo
                      ? Colors.white24
                      : colorScheme.surfaceContainerHighest,
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: TextStyle(color: controlColor, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Playback controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.replay_10, color: controlColor),
                onPressed: () {
                  setState(() {
                    _currentPosition =
                        (_currentPosition - 10).clamp(0, _duration);
                  });
                },
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: Icon(
                  _isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: controlColor,
                  size: 56,
                ),
                onPressed: () {
                  setState(() => _isPlaying = !_isPlaying);
                },
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: Icon(Icons.forward_10, color: controlColor),
                onPressed: () {
                  setState(() {
                    _currentPosition =
                        (_currentPosition + 10).clamp(0, _duration);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Volume control
          Row(
            children: [
              Icon(
                _volume == 0 ? Icons.volume_off : Icons.volume_up,
                color: controlColor,
                size: 20,
              ),
              Expanded(
                child: Slider(
                  value: _volume,
                  onChanged: (value) {
                    setState(() => _volume = value);
                  },
                  activeColor: isVideo ? Colors.white : colorScheme.primary,
                  inactiveColor: isVideo
                      ? Colors.white24
                      : colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    final minutes = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
