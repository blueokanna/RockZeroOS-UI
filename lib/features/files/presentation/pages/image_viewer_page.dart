import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../../../core/theme/app_theme.dart';

/// Image viewer with zoom, pan, and download support
class ImageViewerPage extends ConsumerStatefulWidget {
  final String imageUrl;
  final String fileName;
  final List<String>? gallery;
  final int initialIndex;

  const ImageViewerPage({
    super.key,
    required this.imageUrl,
    required this.fileName,
    this.gallery,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends ConsumerState<ImageViewerPage> {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _showControls = true;
  bool _isDownloading = false;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    // Hide system UI for immersive experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pageController.dispose();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  Future<void> _downloadImage() async {
    if (_isDownloading) return;

    // Request storage permission
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission required')),
          );
        }
        return;
      }
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      // Get download directory
      Directory? downloadDir;
      if (Platform.isAndroid) {
        downloadDir = Directory(
          '/storage/emulated/0/Download/RockZeroDownload',
        );
      } else if (Platform.isIOS) {
        downloadDir = await getApplicationDocumentsDirectory();
        downloadDir = Directory('${downloadDir.path}/RockZeroDownload');
      } else {
        downloadDir = await getDownloadsDirectory();
        if (downloadDir != null) {
          downloadDir = Directory('${downloadDir.path}/RockZeroDownload');
        }
      }

      if (downloadDir == null) {
        throw Exception('Could not find download directory');
      }

      // Create directory if not exists
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final currentUrl = widget.gallery != null
          ? widget.gallery![_currentIndex]
          : widget.imageUrl;
      final currentFileName = widget.gallery != null
          ? Uri.parse(currentUrl).pathSegments.last
          : widget.fileName;

      final filePath = '${downloadDir.path}/$currentFileName';
      final file = File(filePath);

      // Download file
      final request = http.Request('GET', Uri.parse(currentUrl));
      final response = await http.Client().send(request);
      final contentLength = response.contentLength ?? 0;

      final sink = file.openWrite();
      int received = 0;

      await response.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          setState(() {
            _downloadProgress = received / contentLength;
          });
        }
      });

      await sink.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Saved to ${downloadDir.path}')),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasGallery = widget.gallery != null && widget.gallery!.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Image viewer
            if (hasGallery)
              PhotoViewGallery.builder(
                pageController: _pageController,
                itemCount: widget.gallery!.length,
                builder: (context, index) {
                  return PhotoViewGalleryPageOptions(
                    imageProvider: NetworkImage(widget.gallery![index]),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 4,
                    heroAttributes: PhotoViewHeroAttributes(
                      tag: 'image_$index',
                    ),
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image_rounded,
                              size: 64,
                              color: Colors.white54,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Failed to load image',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
                },
                loadingBuilder: (context, event) {
                  return Center(
                    child: CircularProgressIndicator(
                      value: event?.expectedTotalBytes != null
                          ? event!.cumulativeBytesLoaded /
                              event.expectedTotalBytes!
                          : null,
                      color: colorScheme.primary,
                    ),
                  );
                },
                backgroundDecoration: const BoxDecoration(color: Colors.black),
              )
            else
              PhotoView(
                imageProvider: NetworkImage(widget.imageUrl),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
                heroAttributes: const PhotoViewHeroAttributes(tag: 'image'),
                loadingBuilder: (context, event) {
                  return Center(
                    child: CircularProgressIndicator(
                      value: event?.expectedTotalBytes != null
                          ? event!.cumulativeBytesLoaded /
                              event.expectedTotalBytes!
                          : null,
                      color: colorScheme.primary,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.broken_image_rounded,
                          size: 64,
                          color: Colors.white54,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                  );
                },
                backgroundDecoration: const BoxDecoration(color: Colors.black),
              ),

            // Controls overlay
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: M3Durations.medium2,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black54,
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black54,
                    ],
                    stops: const [0.0, 0.15, 0.85, 1.0],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      // Top bar
                      _buildTopBar(colorScheme, hasGallery),
                      const Spacer(),
                      // Bottom indicator
                      if (hasGallery) _buildPageIndicator(colorScheme),
                    ],
                  ),
                ),
              ),
            ),

            // Download progress
            if (_isDownloading)
              Positioned(
                top: MediaQuery.of(context).padding.top + 60,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.download_rounded,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Downloading...',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          Text(
                            '${(_downloadProgress * 100).toInt()}%',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _downloadProgress,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(ColorScheme colorScheme, bool hasGallery) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.fileName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasGallery)
                  Text(
                    '${_currentIndex + 1} / ${widget.gallery!.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: _isDownloading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                : const Icon(Icons.download_rounded, color: Colors.white),
            onPressed: _isDownloading ? null : _downloadImage,
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          widget.gallery!.length,
          (index) => AnimatedContainer(
            duration: M3Durations.short4,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: index == _currentIndex ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color:
                  index == _currentIndex ? colorScheme.primary : Colors.white38,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}
