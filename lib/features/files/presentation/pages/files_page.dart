import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/services/biometric_service.dart';
import '../../../../core/services/device_discovery_service.dart';
import '../../../../core/services/filesystem_monitor_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../storage/presentation/pages/disk_management_page.dart';
import 'hls_video_player.dart';
import 'enhanced_audio_player_page.dart';
import 'image_viewer_page.dart';
import 'network_shares_page.dart';

// ============ Path Encoding Utilities ============

/// Safely encode a path for URL transmission (handles UTF-8/Chinese characters)
String encodePathForUrl(String path) {
  if (path.isEmpty) return path;
  // Split path into segments and encode each segment individually
  final segments = path.split('/');
  final encodedSegments = segments.map((segment) {
    if (segment.isEmpty) return segment;
    return Uri.encodeComponent(segment);
  }).toList();
  return encodedSegments.join('/');
}

/// Safely decode a path from URL (handles UTF-8/Chinese characters)
String decodePathFromUrl(String path) {
  if (path.isEmpty) return path;
  try {
    return Uri.decodeComponent(path);
  } catch (_) {
    // If decoding fails, return original path
    return path;
  }
}

/// Safely decode a file/folder name for display
String safeDisplayName(String name) {
  try {
    return Uri.decodeComponent(name);
  } catch (_) {
    return name;
  }
}

// ============ Providers ============

// View mode preference provider (persisted)
class FilesViewModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    final box = Hive.box('settings');
    return box.get('filesGridView', defaultValue: false);
  }

  void setGridView(bool isGrid) {
    state = isGrid;
    final box = Hive.box('settings');
    box.put('filesGridView', isGrid);
  }

  void toggle() => setGridView(!state);
}

final filesViewModeProvider = NotifierProvider<FilesViewModeNotifier, bool>(
  FilesViewModeNotifier.new,
);

class CurrentPathNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setPath(String path) => state = path;
}

final currentPathProvider = NotifierProvider<CurrentPathNotifier, String>(
  CurrentPathNotifier.new,
);

class FileErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setError(String? error) => state = error;
}

final fileErrorProvider = NotifierProvider<FileErrorNotifier, String?>(
  FileErrorNotifier.new,
);

final directoryListingProvider =
    FutureProvider.family<DirectoryListing?, String>((ref, path) async {
  final device = ref.watch(connectedDeviceProvider);
  if (device == null) {
    ref
        .read(fileErrorProvider.notifier)
        .setError('Not connected to any device');
    return null;
  }

  try {
    final api = ref.read(apiServiceProvider);
    // Pass path directly - the API service handles encoding
    final result = await api.listDirectory(
      path: path.isEmpty ? null : path,
    );
    ref.read(fileErrorProvider.notifier).setError(null);
    return result;
  } catch (e) {
    final safePath = safeDisplayName(path);
    debugPrint('[DirectoryListing] Error loading path "$safePath": $e');

    String errorMessage = e.toString();
    if (errorMessage.contains('FormatException') ||
        errorMessage.contains('encoding') ||
        errorMessage.contains('decode')) {
      errorMessage = 'Path encoding error. Please try refreshing.';
    }
    ref.read(fileErrorProvider.notifier).setError(errorMessage);
    return null;
  }
});

final diskInfoProvider = FutureProvider<List<DiskInfo>>((ref) async {
  final device = ref.watch(connectedDeviceProvider);
  if (device == null) {
    throw Exception('Not connected to any device.');
  }

  final api = ref.read(apiServiceProvider);
  final allDisks = await api.getDiskInfo();

  // 返回所有磁盘（包括未挂载的），但过滤掉无效的磁盘
  return allDisks.where((disk) => disk.totalSpace > 0).toList();
});

// ============ Main Page ============

class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key});

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage>
    with SingleTickerProviderStateMixin {
  String _sortBy = 'name';
  bool _sortAsc = true;
  final Set<String> _selectedFiles = {};
  bool _isUploading = false;
  double _uploadProgress = 0;
  bool _showDisks = true;
  late AnimationController _fabAnimationController;
  final ScrollController _scrollController = ScrollController();
  bool _showFab = true;
  Timer? _autoRefreshTimer;
  StreamSubscription<FileSystemEvent>? _fsEventSubscription;

  List<FileEntry> _clipboardFiles = [];
  bool _isCutOperation = false;

  bool get _isGridView => ref.watch(filesViewModeProvider);

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: M3Durations.medium2,
    );
    _scrollController.addListener(_onScroll);

    // 自动刷新：每3秒刷新一次文件列表和磁盘信息
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        final currentPath = ref.read(currentPathProvider);
        if (_showDisks && currentPath.isEmpty) {
          // 刷新磁盘信息
          ref.invalidate(diskInfoProvider);
        } else {
          // 刷新文件列表
          ref.invalidate(directoryListingProvider(currentPath));
        }
      }
    });

    // 监听文件系统事件
    final monitor = ref.read(fileSystemMonitorProvider);
    _fsEventSubscription = monitor.eventStream.listen((event) {
      debugPrint('[FilesPage] Received FS event: $event');
      if (mounted) {
        final currentPath = ref.read(currentPathProvider);

        // 判断事件是否影响当前视图
        bool shouldRefresh = false;
        bool shouldResetPath = false;

        // 磁盘格式化事件：无论当前在哪个视图都需要刷新
        if (event.type == FileSystemEventType.diskFormatted) {
          shouldRefresh = true;
          // 如果当前在被格式化的磁盘上，需要返回磁盘列表
          if (currentPath.isNotEmpty && event.diskName != null) {
            // 检查当前路径是否在被格式化的磁盘上
            if (currentPath.contains(event.diskName!) ||
                currentPath.contains('/mnt/')) {
              shouldResetPath = true;
            }
          }
        } else if (_showDisks && currentPath.isEmpty) {
          // 在磁盘视图，监听磁盘事件
          if (event.type == FileSystemEventType.diskMounted ||
              event.type == FileSystemEventType.diskUnmounted) {
            shouldRefresh = true;
          }
        } else {
          // 在文件视图，监听文件/目录事件
          if (event.path != null && event.path!.isNotEmpty) {
            // 检查事件路径是否在当前目录下
            final lastSlash = event.path!.lastIndexOf('/');
            if (lastSlash > 0) {
              final eventDir = event.path!.substring(0, lastSlash);
              if (eventDir == currentPath || currentPath.isEmpty) {
                shouldRefresh = true;
              }
            }
          }

          // 也监听重命名、移动等操作
          if (event.oldPath != null && event.oldPath!.isNotEmpty) {
            final lastSlash = event.oldPath!.lastIndexOf('/');
            if (lastSlash > 0) {
              final oldDir = event.oldPath!.substring(0, lastSlash);
              if (oldDir == currentPath || currentPath.isEmpty) {
                shouldRefresh = true;
              }
            }
          }
        }

        if (shouldResetPath) {
          // 格式化后返回磁盘列表视图
          ref.read(currentPathProvider.notifier).setPath('');
          setState(() => _showDisks = true);
          ref.invalidate(diskInfoProvider);
        } else if (shouldRefresh) {
          // 立即刷新
          if (_showDisks && currentPath.isEmpty) {
            ref.invalidate(diskInfoProvider);
          } else {
            ref.invalidate(directoryListingProvider(currentPath));
          }
        }
      }
    });
  }

  void _onScroll() {
    final isScrollingDown = _scrollController.position.userScrollDirection
        .toString()
        .contains('reverse');
    if (isScrollingDown && _showFab) {
      setState(() => _showFab = false);
    } else if (!isScrollingDown && !_showFab) {
      setState(() => _showFab = true);
    }
  }

  void _handleBackNavigation() {
    final currentPath = ref.read(currentPathProvider);

    if (_showDisks) return;

    if (currentPath.isEmpty) {
      setState(() => _showDisks = true);
      return;
    }

    final parts = currentPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      ref.read(currentPathProvider.notifier).setPath('');
      setState(() => _showDisks = true);
    } else if (parts.length == 1) {
      ref.read(currentPathProvider.notifier).setPath('/');
    } else {
      final parentPath = '/${parts.sublist(0, parts.length - 1).join('/')}';
      ref.read(currentPathProvider.notifier).setPath(parentPath);
    }
  }

  bool _canPop() {
    final currentPath = ref.read(currentPathProvider);
    return _showDisks && currentPath.isEmpty;
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _fsEventSubscription?.cancel();
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

    return PopScope(
      canPop: _canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBackNavigation();
      },
      child: GestureDetector(
        // Add swipe-from-edge gesture for back navigation
        onHorizontalDragEnd: (details) {
          // Detect swipe from left edge (back gesture)
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > 500) {
            _handleBackNavigation();
          }
        },
        child: Scaffold(
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              _buildAppBar(showDiskView, currentPath),
              if (!showDiskView)
                SliverToBoxAdapter(child: _buildBreadcrumb(currentPath)),
              if (_isUploading)
                SliverToBoxAdapter(child: _buildUploadProgress()),
              if (showDiskView)
                disks.when(
                  data: (diskList) => _buildDiskGrid(diskList),
                  loading: () => _buildLoadingState(),
                  error: (e, s) => _buildDiskErrorState(e.toString()),
                )
              else
                listing.when(
                  data: (data) {
                    if (data == null) {
                      final device = ref.read(connectedDeviceProvider);
                      if (device == null) {
                        return _buildErrorState('Not connected to any device.');
                      }
                      return _buildErrorState(
                        errorMessage ?? 'Failed to load files.',
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
        ),
      ),
    );
  }

  Widget _buildAppBar(bool showDiskView, String currentPath) {
    final colorScheme = Theme.of(context).colorScheme;

    return SliverAppBar.large(
      title: InkWell(
        onTap: showDiskView
            ? () {
                // 点击 Storage 标题时，导航到存储管理页面
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const DiskManagementPage(),
                  ),
                );
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
              if (showDiskView) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ],
            ],
          ),
        ),
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
            onPressed: () => ref.read(filesViewModeProvider.notifier).toggle(),
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
    final isAtRoot = path == '/' || (path.isNotEmpty && parts.isEmpty);

    // Decode path parts for display (handles Chinese characters)
    final decodedParts = parts.map((p) => safeDisplayName(p)).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          if (path.isNotEmpty && path != '/')
            IconButton(
              icon: Icon(
                Icons.arrow_back_rounded,
                size: 20,
                color: colorScheme.primary,
              ),
              onPressed: () {
                if (parts.length <= 1) {
                  ref.read(currentPathProvider.notifier).setPath('/');
                } else {
                  final parentPath =
                      '/${parts.sublist(0, parts.length - 1).join('/')}';
                  ref.read(currentPathProvider.notifier).setPath(parentPath);
                }
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Go back',
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    _BreadcrumbChip(
                      icon: Icons.folder_rounded,
                      label: '/',
                      isActive: isAtRoot && parts.isEmpty,
                      onTap: isAtRoot && parts.isEmpty
                          ? null
                          : () => ref
                              .read(currentPathProvider.notifier)
                              .setPath('/'),
                    ),
                  ],
                  if (decodedParts.length > 3) ...[
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    PopupMenuButton<int>(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '...',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      onSelected: (index) {
                        final fullPath =
                            '/${parts.sublist(0, index + 1).join('/')}';
                        ref
                            .read(currentPathProvider.notifier)
                            .setPath(fullPath);
                      },
                      itemBuilder: (context) => List.generate(
                        decodedParts.length - 2,
                        (index) => PopupMenuItem(
                          value: index,
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_rounded,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(decodedParts[index]),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ...decodedParts
                        .sublist(decodedParts.length - 2)
                        .asMap()
                        .entries
                        .map((entry) {
                      final actualIndex = decodedParts.length - 2 + entry.key;
                      final part = entry.value;
                      final fullPath =
                          '/${parts.sublist(0, actualIndex + 1).join('/')}';
                      final isLast = actualIndex == decodedParts.length - 1;

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.5,
                            ),
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
                  ] else ...[
                    ...decodedParts.asMap().entries.map((entry) {
                      final index = entry.key;
                      final part = entry.value;
                      final fullPath =
                          '/${parts.sublist(0, index + 1).join('/')}';
                      final isLast = index == decodedParts.length - 1;

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.5,
                            ),
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
                ],
              ),
            ),
          ),
        ],
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
    // Filter out unwanted disks
    final filteredDisks = disks.where((disk) {
      final fs = disk.fileSystem.toUpperCase();
      final mountPoint = disk.mountPoint.toLowerCase();
      final name = disk.name.toLowerCase();

      // Skip VFAT/FAT formats (usually boot partitions)
      if (fs == 'VFAT' || fs == 'FAT32' || fs == 'FAT16' || fs == 'FAT') {
        return false;
      }

      // Skip /boot partition
      if (mountPoint == '/boot' || mountPoint.startsWith('/boot/')) {
        return false;
      }

      // Skip eMMC boot partitions (mmcblk*boot0, mmcblk*boot1, etc.)
      if (name.contains('boot0') || name.contains('boot1')) {
        return false;
      }

      // Skip eMMC RPMB partition
      if (name.contains('rpmb')) {
        return false;
      }

      return true;
    }).toList();

    if (filteredDisks.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyDiskState());
    }

    // Separate mounted and unmounted disks
    final mountedDisks =
        filteredDisks.where((d) => d.mountPoint != 'Not mounted').toList();
    final unmountedDisks =
        filteredDisks.where((d) => d.mountPoint == 'Not mounted').toList();

    // Use filtered disks for display
    final displayDisks = [...mountedDisks, ...unmountedDisks];

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    int totalSpace = 0;
    int usedSpace = 0;
    for (final disk in mountedDisks) {
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
                          '${mountedDisks.length} ${mountedDisks.length == 1 ? 'disk' : 'disks'} mounted',
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
          ),
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
                const Spacer(),
                // Network shares button
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NetworkSharesPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.folder_shared_rounded, size: 18),
                  label: const Text('Network'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
            ),
            itemCount: displayDisks.length,
            itemBuilder: (context, index) {
              final disk = displayDisks[index];
              return _DiskCard(
                disk: disk,
                onTap: () {
                  if (disk.mountPoint != 'Not mounted') {
                    ref
                        .read(currentPathProvider.notifier)
                        .setPath(disk.mountPoint);
                    setState(() => _showDisks = false);
                  } else {
                    // Show mount dialog for unmounted disks
                    _showMountDialog(disk);
                  }
                },
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

    // Optimized animation with staggered effect
    if (_isGridView) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 110,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.82,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => AnimationConfiguration.staggeredGrid(
              position: index,
              duration: M3Durations.medium4,
              columnCount: 3,
              child: ScaleAnimation(
                curve: M3Curves.emphasized,
                child: FadeInAnimation(
                  curve: M3Curves.emphasized,
                  child: RepaintBoundary(
                    child: _FileGridItem(
                      entry: entries[index],
                      isSelected: _selectedFiles.contains(entries[index].path),
                      onTap: () => _handleFileTap(entries[index]),
                      onLongPress: () => _handleLongPress(entries[index]),
                    ),
                  ),
                ),
              ),
            ),
            childCount: entries.length,
          ),
        ),
      );
    } else {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => AnimationConfiguration.staggeredList(
              position: index,
              duration: M3Durations.medium3,
              child: SlideAnimation(
                verticalOffset: 50.0,
                curve: M3Curves.emphasized,
                child: FadeInAnimation(
                  curve: M3Curves.emphasized,
                  child: RepaintBoundary(
                    child: _FileListItem(
                      entry: entries[index],
                      isSelected: _selectedFiles.contains(entries[index].path),
                      onTap: () => _handleFileTap(entries[index]),
                      onLongPress: () => _handleLongPress(entries[index]),
                      onDelete: () => _deleteFile(entries[index]),
                    ),
                  ),
                ),
              ),
            ),
            childCount: entries.length,
          ),
        ),
      );
    }
  }

  Widget _buildLoadingState() {
    final colorScheme = Theme.of(context).colorScheme;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      sliver: _isGridView
          ? SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 110,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _SkeletonGridItem(colorScheme: colorScheme),
                childCount: 12,
              ),
            )
          : SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _SkeletonListItem(colorScheme: colorScheme),
                childCount: 8,
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
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => ref.invalidate(diskInfoProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildDiskErrorState(String message) {
    final colorScheme = Theme.of(context).colorScheme;
    final isNotConnected = message.contains('Not connected');

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
                  color: isNotConnected
                      ? colorScheme.primaryContainer
                      : colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  isNotConnected
                      ? Icons.link_off_rounded
                      : Icons.error_outline_rounded,
                  size: 44,
                  color: isNotConnected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isNotConnected ? 'Not Connected' : 'Failed to load storage',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isNotConnected
                    ? 'Please connect to a RockZero device to browse files'
                    : message,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => ref.invalidate(diskInfoProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
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
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'upload',
          onPressed: _pickAndUploadFiles,
          icon: const Icon(Icons.upload_rounded),
          label: const Text('Upload'),
        ),
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
      // Use the entry's full path directly - it's already correctly formatted
      ref.read(currentPathProvider.notifier).setPath(entry.path);
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

  void _handleLongPress(FileEntry entry) {
    if (entry.isDirectory) {
      _showFolderActions(entry);
    } else {
      _showFileActions(entry);
    }
  }

  void _showFolderActions(FileEntry entry) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final displayName = safeDisplayName(entry.name);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.folder_rounded,
                        size: 32,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Folder',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              ListTile(
                leading: _buildActionIcon(
                  Icons.folder_open_rounded,
                  colorScheme.primaryContainer,
                  colorScheme.onPrimaryContainer,
                ),
                title: const Text('Open'),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(currentPathProvider.notifier).setPath(entry.path);
                },
              ),
              ListTile(
                leading: _buildActionIcon(
                  Icons.copy_rounded,
                  Colors.teal.withValues(alpha: 0.15),
                  Colors.teal,
                ),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(context);
                  _copyFile(entry);
                },
              ),
              ListTile(
                leading: _buildActionIcon(
                  Icons.content_cut_rounded,
                  Colors.indigo.withValues(alpha: 0.15),
                  Colors.indigo,
                ),
                title: const Text('Cut'),
                onTap: () {
                  Navigator.pop(context);
                  _cutFile(entry);
                },
              ),
              if (_clipboardFiles.isNotEmpty)
                ListTile(
                  leading: _buildActionIcon(
                    Icons.paste_rounded,
                    Colors.green.withValues(alpha: 0.15),
                    Colors.green,
                  ),
                  title: Text(
                    'Paste here (${_clipboardFiles.length} item${_clipboardFiles.length > 1 ? 's' : ''})',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _pasteFilesToFolder(entry);
                  },
                ),
              ListTile(
                leading: _buildActionIcon(
                  Icons.edit_rounded,
                  Colors.orange.withValues(alpha: 0.15),
                  Colors.orange,
                ),
                title: const Text('Rename'),
                onTap: () {
                  Navigator.pop(context);
                  _showRenameDialog(entry);
                },
              ),
              ListTile(
                leading: _buildActionIcon(
                  Icons.info_outline_rounded,
                  Colors.purple.withValues(alpha: 0.15),
                  Colors.purple,
                ),
                title: const Text('Details'),
                onTap: () {
                  Navigator.pop(context);
                  _showFileDetails(entry);
                },
              ),
              ListTile(
                leading: _buildActionIcon(
                  Icons.delete_rounded,
                  colorScheme.errorContainer,
                  colorScheme.error,
                ),
                title: Text(
                  'Delete',
                  style: TextStyle(color: colorScheme.error),
                ),
                subtitle: Text(
                  'Requires authentication',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.error.withValues(alpha: 0.7),
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteFile(entry);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, Color bgColor, Color iconColor) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: iconColor),
    );
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                            safeDisplayName(entry.name),
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatFileSize(entry.size),
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
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
                  leading: _buildActionIcon(
                    isImage
                        ? Icons.image_rounded
                        : isVideo
                            ? Icons.play_circle_rounded
                            : Icons.audiotrack_rounded,
                    colorScheme.primaryContainer,
                    colorScheme.onPrimaryContainer,
                  ),
                  title: Text(isImage ? 'View' : 'Play'),
                  onTap: () {
                    Navigator.pop(context);
                    _openMediaPreview(entry);
                  },
                ),
              ListTile(
                leading: _buildActionIcon(
                  Icons.copy_rounded,
                  Colors.teal.withValues(alpha: 0.15),
                  Colors.teal,
                ),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(context);
                  _copyFile(entry);
                },
              ),
              ListTile(
                leading: _buildActionIcon(
                  Icons.content_cut_rounded,
                  Colors.indigo.withValues(alpha: 0.15),
                  Colors.indigo,
                ),
                title: const Text('Cut'),
                onTap: () {
                  Navigator.pop(context);
                  _cutFile(entry);
                },
              ),
              ListTile(
                leading: _buildActionIcon(
                  Icons.download_rounded,
                  Colors.blue.withValues(alpha: 0.15),
                  Colors.blue,
                ),
                title: const Text('Download'),
                onTap: () {
                  Navigator.pop(context);
                  _downloadFile(entry);
                },
              ),
              ListTile(
                leading: _buildActionIcon(
                  Icons.edit_rounded,
                  Colors.orange.withValues(alpha: 0.15),
                  Colors.orange,
                ),
                title: const Text('Rename'),
                onTap: () {
                  Navigator.pop(context);
                  _showRenameDialog(entry);
                },
              ),
              ListTile(
                leading: _buildActionIcon(
                  Icons.info_outline_rounded,
                  Colors.purple.withValues(alpha: 0.15),
                  Colors.purple,
                ),
                title: const Text('Details'),
                onTap: () {
                  Navigator.pop(context);
                  _showFileDetails(entry);
                },
              ),
              ListTile(
                leading: _buildActionIcon(
                  Icons.delete_rounded,
                  colorScheme.errorContainer,
                  colorScheme.error,
                ),
                title: Text(
                  'Delete',
                  style: TextStyle(color: colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteFile(entry);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _copyFile(FileEntry entry) {
    setState(() {
      _clipboardFiles = [entry];
      _isCutOperation = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.copy_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '"${safeDisplayName(entry.name)}" copied to clipboard',
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(label: 'Paste', onPressed: _pasteFiles),
      ),
    );
  }

  void _cutFile(FileEntry entry) {
    setState(() {
      _clipboardFiles = [entry];
      _isCutOperation = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.content_cut_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('"${safeDisplayName(entry.name)}" ready to move'),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(label: 'Paste', onPressed: _pasteFiles),
      ),
    );
  }

  Future<void> _pasteFiles() async {
    if (_clipboardFiles.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Clipboard is empty')));
      return;
    }

    final currentPath = ref.read(currentPathProvider);
    final api = ref.read(apiServiceProvider);
    final colorScheme = Theme.of(context).colorScheme;

    try {
      for (final file in _clipboardFiles) {
        final destPath =
            currentPath.isEmpty ? '/${file.name}' : '$currentPath/${file.name}';

        if (_isCutOperation) {
          await api.moveFiles(source: file.path, destination: destPath);
        } else {
          await api.copyFiles(source: file.path, destination: destPath);
        }
      }

      final wasCut = _isCutOperation;

      if (_isCutOperation) {
        setState(() {
          _clipboardFiles = [];
          _isCutOperation = false;
        });
      }

      ref.invalidate(directoryListingProvider(currentPath));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  wasCut
                      ? 'Files moved successfully'
                      : 'Files copied successfully',
                ),
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
            content: Text('Failed to paste: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _pasteFilesToFolder(FileEntry targetFolder) async {
    if (_clipboardFiles.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Clipboard is empty')));
      return;
    }

    final api = ref.read(apiServiceProvider);
    final colorScheme = Theme.of(context).colorScheme;

    try {
      for (final file in _clipboardFiles) {
        final destPath = '${targetFolder.path}/${file.name}';

        if (_isCutOperation) {
          await api.moveFiles(source: file.path, destination: destPath);
        } else {
          await api.copyFiles(source: file.path, destination: destPath);
        }
      }

      final wasCut = _isCutOperation;

      if (_isCutOperation) {
        setState(() {
          _clipboardFiles = [];
          _isCutOperation = false;
        });
      }

      final currentPath = ref.read(currentPathProvider);
      ref.invalidate(directoryListingProvider(currentPath));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  wasCut
                      ? 'Files moved successfully'
                      : 'Files copied successfully',
                ),
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
            content: Text('Failed to paste: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _pickAndUploadFiles() async {
    // 首先检查当前路径是否有效（必须在一个具体目录中，不能在磁盘列表视图）
    final currentPath = ref.read(currentPathProvider);
    if (currentPath.isEmpty) {
      if (mounted) {
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.warning_rounded, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Please select a disk and navigate to a folder first',
                  ),
                ),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {
                scaffoldMessenger.hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    List<File>? uploadedFiles; // 声明在外层

    try {
      final api = ref.read(apiServiceProvider);

      if (kIsWeb) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Web upload not yet implemented')),
          );
        }
        return; // 提前返回
      }

      uploadedFiles = result.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();

      if (uploadedFiles.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No valid files selected'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      // 检查文件大小
      int totalSize = 0;
      for (final file in uploadedFiles) {
        totalSize += file.lengthSync();
      }

      debugPrint(
          '[Upload] Uploading ${uploadedFiles.length} files, total size: ${_formatBytes(totalSize)}');

      await api.uploadToDirectory(
        currentPath,
        uploadedFiles,
        onProgress: (sent, total) {
          if (mounted) {
            setState(() => _uploadProgress = sent / total);
          }
          debugPrint(
              '[Upload] Progress: ${(sent / total * 100).toStringAsFixed(1)}%');
        },
      );

      debugPrint('[Upload] Upload completed successfully');

      // 发送文件上传完成事件
      final monitor = ref.read(fileSystemMonitorProvider);
      for (final file in uploadedFiles) {
        final fileName = file.path.split(RegExp(r'[/\\]')).last;
        final uploadedPath =
            currentPath.isEmpty ? '/$fileName' : '$currentPath/$fileName';
        monitor.emitUploadCompleted(
          uploadedPath,
          metadata: {
            'filename': fileName,
            'size': file.lengthSync(),
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
    } on DioException catch (e) {
      debugPrint(
          '[Upload] DioException: ${e.type} - ${e.message} - ${e.error}');
      if (mounted) {
        String errorMessage = 'Upload failed';
        if (e.type == DioExceptionType.sendTimeout) {
          errorMessage = 'Upload timeout - file too large or network too slow';
        } else if (e.type == DioExceptionType.connectionTimeout) {
          errorMessage = 'Connection timeout - check your network';
        } else if (e.type == DioExceptionType.connectionError) {
          errorMessage = 'Connection error - check server is running';
        } else if (e.response != null) {
          // Try to extract message from response body first
          final data = e.response?.data;
          if (data is Map && data['message'] != null) {
            errorMessage = 'Upload failed: ${data['message']}';
          } else {
            final statusMsg = e.response?.statusMessage;
            if (statusMsg != null && statusMsg.isNotEmpty) {
              errorMessage = 'Upload failed: $statusMsg';
            } else {
              errorMessage =
                  'Upload failed: Server error (${e.response?.statusCode})';
            }
          }
        } else if (e.error != null) {
          // Extract error from ApiException if wrapped
          errorMessage = 'Upload failed: ${e.error}';
        } else {
          final errMsg = e.message;
          errorMessage = 'Upload failed: ${errMsg ?? 'Network error'}';
        }

        // Clear any existing SnackBars before showing new one
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        scaffoldMessenger.clearSnackBars();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {
                scaffoldMessenger.hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Upload] Error: $e');
      if (mounted) {
        final errorStr = e.toString();
        // Clear any existing SnackBars before showing new one
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        scaffoldMessenger.clearSnackBars();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
                'Upload failed: ${errorStr.isNotEmpty ? errorStr : 'Unknown error'}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {
                scaffoldMessenger.hideCurrentSnackBar();
              },
            ),
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

  void _showMountDialog(DiskInfo disk) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // 检查磁盘是否需要初始化
    final fs = disk.fileSystem.trim().toLowerCase();
    final needsInitialization = fs.isEmpty || fs == 'unknown';

    if (needsInitialization) {
      // 显示未初始化警告
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            Icons.warning_rounded,
            color: colorScheme.error,
            size: 48,
          ),
          title: const Text('磁盘未初始化'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '设备 ${disk.name} 没有分区和文件系统。',
                style:
                    textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: colorScheme.error),
                        const SizedBox(width: 8),
                        Text(
                          '磁盘信息',
                          style: textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('大小: ${_formatBytes(disk.totalSpace)}',
                        style: textTheme.bodySmall),
                    Text('类型: ${disk.diskType}', style: textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '请前往"存储"页面初始化此磁盘，创建分区表和文件系统后才能挂载使用。',
                style: textTheme.bodySmall,
              ),
            ],
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                // 导入存储管理页面
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const DiskManagementPage(),
                  ),
                );
              },
              icon: const Icon(Icons.settings_rounded),
              label: const Text('前往存储管理'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colorScheme.primary, colorScheme.tertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.storage_rounded,
            size: 32,
            color: Colors.white,
          ),
        ),
        title: const Text('Mount Disk'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Do you want to mount "${disk.name}"?',
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Disk Information',
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Size: ${_formatBytes(disk.totalSpace)}',
                      style: textTheme.bodySmall),
                  Text('Type: ${disk.diskType}', style: textTheme.bodySmall),
                  if (disk.fileSystem != 'Unknown')
                    Text('File System: ${disk.fileSystem}',
                        style: textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _mountDisk(disk);
            },
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('Mount'),
          ),
        ],
      ),
    );
  }

  Future<void> _mountDisk(DiskInfo disk) async {
    final colorScheme = Theme.of(context).colorScheme;

    // Store references before async operations
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Mounting ${disk.name}...'),
            ],
          ),
        ),
      ),
    );

    try {
      final api = ref.read(apiServiceProvider);

      // Generate mount point
      final mountPoint = '/mnt/${disk.name}';

      // Call mount API
      await api.mountDisk(
        device: '/dev/${disk.name}',
        mountPoint: mountPoint,
        fileSystem:
            disk.fileSystem != 'Unknown' ? disk.fileSystem.toLowerCase() : null,
      );

      // Wait for the system to update
      await Future.delayed(const Duration(milliseconds: 1500));

      // Close loading dialog
      if (mounted) {
        rootNavigator.pop();
      }

      // Refresh disk list and file list
      ref.invalidate(diskInfoProvider);
      final currentPath = ref.read(currentPathProvider);
      ref.invalidate(directoryListingProvider(currentPath));

      // Show success message
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: colorScheme.onPrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('${disk.name} mounted to $mountPoint'),
                ),
              ],
            ),
            backgroundColor: colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        rootNavigator.pop();
      }

      // Show error message
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: colorScheme.onError),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Failed to mount ${disk.name}: ${e.toString()}'),
                ),
              ],
            ),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _deleteFile(FileEntry entry) async {
    final colorScheme = Theme.of(context).colorScheme;
    final biometricEnabled = ref.read(biometricEnabledProvider);
    final biometricService = ref.read(biometricServiceProvider);

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
              'Are you sure you want to delete "${safeDisplayName(entry.name)}"?',
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

    switch (authMethod) {
      case 'biometric':
        final isAvailable = await biometricService.isAvailable();
        if (isAvailable) {
          authenticated = await biometricService.authenticate(
            reason: 'Authenticate to delete "${safeDisplayName(entry.name)}"',
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
            content: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.white),
                SizedBox(width: 12),
                Text('Authentication failed'),
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
                Text('"${safeDisplayName(entry.name)}" deleted'),
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

  void _showFileDetails(FileEntry entry) {
    final mimeType = entry.mimeType ?? '';
    final isVideo = mimeType.startsWith('video/');
    final isAudio = mimeType.startsWith('audio/');
    final isImage = mimeType.startsWith('image/');
    final isMedia = isVideo || isAudio || isImage;

    showDialog(
      context: context,
      builder: (context) => _FileDetailsDialog(
        entry: entry,
        isMedia: isMedia,
        isVideo: isVideo,
        isAudio: isAudio,
        isImage: isImage,
        getFileIcon: _getFileIcon,
        formatFileSize: _formatFileSize,
        formatTimestamp: _formatTimestamp,
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return _formatDateTime(dateTime);
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays == 0) {
      return 'Today ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  void _openMediaPreview(FileEntry entry) {
    final api = ref.read(apiServiceProvider);
    final mimeType = entry.mimeType ?? '';

    if (mimeType.startsWith('image/')) {
      final imageUrl = api.getImageUrl(entry.path);
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              ImageViewerPage(imageUrl: imageUrl, fileName: entry.name),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: M3Curves.emphasized,
              ),
              child: child,
            );
          },
          transitionDuration: M3Durations.long2,
        ),
      );
    } else if (mimeType.startsWith('audio/')) {
      final streamUrl = api.getMediaStreamUrl(entry.path);
      // Use enhanced audio player with visualizations
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              EnhancedAudioPlayerPage(
            mediaUrl: streamUrl,
            fileName: entry.name,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: M3Curves.emphasized,
              )),
              child: child,
            );
          },
          transitionDuration: M3Durations.long2,
        ),
      );
    } else if (mimeType.startsWith('video/')) {
      final api = ref.read(apiServiceProvider);
      // Use HLS player - Rust backend converts to HLS, supports all formats
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              HlsVideoPlayer(
            filePath: entry.path,
            fileName: entry.name,
            baseUrl: api.baseUrl,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          transitionDuration: M3Durations.medium4,
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Download URL: $downloadUrl')));
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
    final controller = TextEditingController(text: safeDisplayName(entry.name));
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

// ============ Helper Widgets ============

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
      color: isActive
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: isActive
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
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

    final diskIcon = _getDiskIcon();
    final diskTypeLabel = _getDiskTypeLabel();
    final usageColor = _getUsageColor(disk.usagePercentage);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
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
                          backgroundColor: colorScheme.surfaceContainerHighest,
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
              const SizedBox(height: 12),
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
      if (disk.diskType.toLowerCase().contains('usb')) return Icons.usb_rounded;
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
    final displayName = safeDisplayName(entry.name);

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
                displayName,
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
    final displayName = safeDisplayName(entry.name);

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
          displayName,
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

// ============ Skeleton Loading Widgets ============

class _SkeletonGridItem extends StatelessWidget {
  final ColorScheme colorScheme;

  const _SkeletonGridItem({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: 60,
              height: 12,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 40,
              height: 8,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonListItem extends StatelessWidget {
  final ColorScheme colorScheme;

  const _SkeletonListItem({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 14,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 80,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============ Auth Widgets ============

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
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
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
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.deepOrange],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
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

// ============ File Details Dialog ============

class _FileDetailsDialog extends ConsumerStatefulWidget {
  final FileEntry entry;
  final bool isMedia;
  final bool isVideo;
  final bool isAudio;
  final bool isImage;
  final Widget Function(FileEntry, double) getFileIcon;
  final String Function(int) formatFileSize;
  final String Function(int) formatTimestamp;

  const _FileDetailsDialog({
    required this.entry,
    required this.isMedia,
    required this.isVideo,
    required this.isAudio,
    required this.isImage,
    required this.getFileIcon,
    required this.formatFileSize,
    required this.formatTimestamp,
  });

  @override
  ConsumerState<_FileDetailsDialog> createState() => _FileDetailsDialogState();
}

class _FileDetailsDialogState extends ConsumerState<_FileDetailsDialog> {
  Map<String, dynamic>? _mediaInfo;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.isMedia) {
      _loadMediaInfo();
    }
  }

  Future<void> _loadMediaInfo() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.get(
        '/api/v1/media/info/${Uri.encodeComponent(widget.entry.path)}',
      );
      if (mounted) {
        setState(() {
          _mediaInfo = response.data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDuration(double? seconds) {
    if (seconds == null) return '-';
    final duration = Duration(seconds: seconds.round());
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _formatBitrate(int? bitrate) {
    if (bitrate == null) return '-';
    if (bitrate >= 1000000) {
      return '${(bitrate / 1000000).toStringAsFixed(1)} Mbps';
    }
    if (bitrate >= 1000) {
      return '${(bitrate / 1000).toStringAsFixed(0)} Kbps';
    }
    return '$bitrate bps';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: widget.getFileIcon(widget.entry, 64),
      title: Text(
        safeDisplayName(widget.entry.name),
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DetailRow(
              icon: Icons.folder_rounded,
              label: 'Type',
              value: widget.entry.isDirectory
                  ? 'Folder'
                  : (widget.entry.mimeType ?? 'Unknown'),
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.storage_rounded,
              label: 'Size',
              value: widget.entry.isDirectory
                  ? '-'
                  : widget.formatFileSize(widget.entry.size),
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.location_on_rounded,
              label: 'Path',
              value: widget.entry.path,
              isSelectable: true,
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.calendar_today_rounded,
              label: 'Modified',
              value: widget.formatTimestamp(widget.entry.modified),
            ),
            if (widget.entry.permissions.isNotEmpty) ...[
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.security_rounded,
                label: 'Permissions',
                value: widget.entry.permissions,
              ),
            ],
            if (widget.isMedia) ...[
              const SizedBox(height: 20),
              _buildMediaInfoSection(colorScheme),
            ],
          ],
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildMediaInfoSection(ColorScheme colorScheme) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 12),
            Text(
              'Loading media info...',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (_mediaInfo == null) return const SizedBox.shrink();

    final List<Widget> mediaDetails = [];

    if (widget.isVideo) {
      if (_mediaInfo!['width'] != null && _mediaInfo!['height'] != null) {
        mediaDetails.add(
          _DetailRow(
            icon: Icons.aspect_ratio_rounded,
            label: 'Resolution',
            value: '${_mediaInfo!['width']}×${_mediaInfo!['height']}',
          ),
        );
        mediaDetails.add(const SizedBox(height: 12));
      }
      if (_mediaInfo!['duration'] != null) {
        mediaDetails.add(
          _DetailRow(
            icon: Icons.timer_rounded,
            label: 'Duration',
            value: _formatDuration(_mediaInfo!['duration']?.toDouble()),
          ),
        );
        mediaDetails.add(const SizedBox(height: 12));
      }
      if (_mediaInfo!['video_codec'] != null) {
        mediaDetails.add(
          _DetailRow(
            icon: Icons.videocam_rounded,
            label: 'Video Codec',
            value: _mediaInfo!['video_codec'].toString().toUpperCase(),
          ),
        );
        mediaDetails.add(const SizedBox(height: 12));
      }
      if (_mediaInfo!['video_bitrate'] != null) {
        mediaDetails.add(
          _DetailRow(
            icon: Icons.speed_rounded,
            label: 'Video Bitrate',
            value: _formatBitrate(_mediaInfo!['video_bitrate']),
          ),
        );
        mediaDetails.add(const SizedBox(height: 12));
      }
    }

    if (widget.isVideo || widget.isAudio) {
      if (_mediaInfo!['audio_codec'] != null) {
        mediaDetails.add(
          _DetailRow(
            icon: Icons.audiotrack_rounded,
            label: 'Audio Codec',
            value: _mediaInfo!['audio_codec'].toString().toUpperCase(),
          ),
        );
        mediaDetails.add(const SizedBox(height: 12));
      }
      if (_mediaInfo!['audio_bitrate'] != null) {
        mediaDetails.add(
          _DetailRow(
            icon: Icons.graphic_eq_rounded,
            label: 'Audio Bitrate',
            value: _formatBitrate(_mediaInfo!['audio_bitrate']),
          ),
        );
        mediaDetails.add(const SizedBox(height: 12));
      }
    }

    if (mediaDetails.isEmpty) return const SizedBox.shrink();

    // Remove last SizedBox
    if (mediaDetails.isNotEmpty && mediaDetails.last is SizedBox) {
      mediaDetails.removeLast();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(
                widget.isImage
                    ? Icons.photo_camera_rounded
                    : Icons.movie_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.isImage ? 'Image Details' : 'Media Details',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        ...mediaDetails,
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isSelectable;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isSelectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: colorScheme.primary),
          ),
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
                isSelectable
                    ? SelectableText(
                        value,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    : Text(
                        value,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
