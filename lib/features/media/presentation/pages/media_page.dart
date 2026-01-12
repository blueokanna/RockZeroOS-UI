import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/services/device_discovery_service.dart';

// Media providers
final mediaListProvider = FutureProvider.autoDispose<List<MediaResponse>>((
  ref,
) async {
  final api = ref.read(apiServiceProvider);
  return await api.listMedia();
});

final codecInfoProvider = FutureProvider.autoDispose<MediaCodecInfo?>((
  ref,
) async {
  try {
    final api = ref.read(apiServiceProvider);
    return await api.getCodecInfo();
  } catch (_) {
    return null;
  }
});

class MediaPage extends ConsumerStatefulWidget {
  const MediaPage({super.key});

  @override
  ConsumerState<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends ConsumerState<MediaPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _filterType = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaList = ref.watch(mediaListProvider);
    final codecInfo = ref.watch(codecInfoProvider);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar.large(
            title: const Text('Media'),
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () => _showCodecInfo(codecInfo),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(mediaListProvider),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.apps), text: 'All'),
                Tab(icon: Icon(Icons.video_library), text: 'Videos'),
                Tab(icon: Icon(Icons.audiotrack), text: 'Audio'),
                Tab(icon: Icon(Icons.image), text: 'Images'),
              ],
              onTap: (index) {
                setState(() {
                  _filterType = ['all', 'video', 'audio', 'image'][index];
                });
              },
            ),
          ),
        ],
        body: mediaList.when(
          data: (items) {
            final filtered = _filterType == 'all'
                ? items
                : items.where((m) => m.mediaType == _filterType).toList();

            if (filtered.isEmpty) {
              return _buildEmptyState();
            }

            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.75,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                return _MediaCard(
                      media: filtered[index],
                      onTap: () => _playMedia(filtered[index]),
                    )
                    .animate(delay: (50 * index).ms)
                    .fadeIn()
                    .scale(begin: const Offset(0.95, 0.95));
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => _buildErrorState(),
        ),
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
            Icons.movie_creation_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No media files',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Upload videos, audio, or images to get started',
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
            'Failed to load media',
            style: TextStyle(color: colorScheme.error),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => ref.invalidate(mediaListProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _playMedia(MediaResponse media) {
    final device = ref.read(connectedDeviceProvider);
    if (device == null) return;

    final url = '${device.baseUrl}${media.fileUrl}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) =>
            _MediaPlayerSheet(media: media, url: url),
      ),
    );
  }

  void _showCodecInfo(AsyncValue<MediaCodecInfo?> codecInfo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Codec Information'),
        content: codecInfo.when(
          data: (info) {
            if (info == null) {
              return const Text('Failed to load codec info');
            }
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _InfoRow(
                    label: 'FFmpeg',
                    value: info.ffmpegAvailable ? 'Available' : 'Not Available',
                    icon: info.ffmpegAvailable
                        ? Icons.check_circle
                        : Icons.cancel,
                    iconColor: info.ffmpegAvailable ? Colors.green : Colors.red,
                  ),
                  const Divider(),
                  const Text(
                    'Video Codecs:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 4,
                    children: info.supportedVideoCodecs
                        .map((c) => Chip(label: Text(c)))
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Audio Codecs:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 4,
                    children: info.supportedAudioCodecs
                        .map((c) => Chip(label: Text(c)))
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hardware Acceleration:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (info.hardwareAcceleration.isEmpty)
                    const Text('None available')
                  else
                    Wrap(
                      spacing: 4,
                      children: info.hardwareAcceleration
                          .map(
                            (h) => Chip(
                              avatar: const Icon(Icons.speed, size: 16),
                              label: Text(h),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            );
          },
          loading: () => const CircularProgressIndicator(),
          error: (e, s) => const Text('Failed to load codec info'),
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

class _MediaCard extends StatelessWidget {
  final MediaResponse media;
  final VoidCallback onTap;

  const _MediaCard({required this.media, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: _getMediaColor(media.mediaType).withValues(alpha: 0.1),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      _getMediaIcon(media.mediaType),
                      size: 48,
                      color: _getMediaColor(media.mediaType),
                    ),
                    if (media.mediaType == 'video')
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _formatDuration(media.duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.title,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        _getMediaIcon(media.mediaType),
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        media.mediaType.toUpperCase(),
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getMediaIcon(String type) {
    switch (type) {
      case 'video':
        return Icons.video_file;
      case 'audio':
        return Icons.audio_file;
      case 'image':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getMediaColor(String type) {
    switch (type) {
      case 'video':
        return Colors.purple;
      case 'audio':
        return Colors.orange;
      case 'image':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) {
      return '--:--';
    }
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

class _MediaPlayerSheet extends StatelessWidget {
  final MediaResponse media;
  final String url;

  const _MediaPlayerSheet({required this.media, required this.url});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        media.title,
                        style: textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        media.mediaType.toUpperCase(),
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Player placeholder
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      media.mediaType == 'video'
                          ? Icons.play_circle_fill
                          : media.mediaType == 'audio'
                          ? Icons.music_note
                          : Icons.image,
                      size: 64,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Media Player',
                      style: textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hardware accelerated playback',
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Controls
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () {},
                ),
                IconButton(icon: const Icon(Icons.replay_10), onPressed: () {}),
                FloatingActionButton(
                  onPressed: () {},
                  child: const Icon(Icons.play_arrow),
                ),
                IconButton(
                  icon: const Icon(Icons.forward_10),
                  onPressed: () {},
                ),
                IconButton(icon: const Icon(Icons.skip_next), onPressed: () {}),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Text('$label: '),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
