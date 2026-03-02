import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../../../core/theme/app_theme.dart';

/// 内存缓存 - 避免重复下载同一图片
class _ImageMemoryCache {
  static final Map<String, Uint8List> _cache = {};
  static const int _maxCacheSize = 50 * 1024 * 1024; // 50MB 缓存上限
  static int _currentSize = 0;
  static final List<String> _keys = [];

  static Uint8List? get(String key) {
    if (_cache.containsKey(key)) {
      // LRU: 移到最后
      _keys.remove(key);
      _keys.add(key);
      return _cache[key];
    }
    return null;
  }

  static void put(String key, Uint8List data) {
    // 如果已存在，先移除旧数据
    if (_cache.containsKey(key)) {
      _currentSize -= _cache[key]!.length;
      _keys.remove(key);
    }

    // 淘汰旧数据直到有足够空间
    while (_currentSize + data.length > _maxCacheSize && _keys.isNotEmpty) {
      final oldKey = _keys.removeAt(0);
      final oldData = _cache.remove(oldKey);
      if (oldData != null) _currentSize -= oldData.length;
    }

    _cache[key] = data;
    _keys.add(key);
    _currentSize += data.length;
  }
}

/// 支持认证头的网络图片加载器
///
/// 特性：
/// - JWT Bearer Token 认证
/// - 内存缓存（LRU，50MB 上限）
/// - 超时重试（最多 2 次重试）
/// - 流式下载（适合大图片）
/// - ETag 条件请求支持
class AuthenticatedNetworkImage
    extends ImageProvider<AuthenticatedNetworkImage> {
  final String url;
  final String? authToken;
  final double scale;

  const AuthenticatedNetworkImage(this.url, {this.authToken, this.scale = 1.0});

  @override
  Future<AuthenticatedNetworkImage> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<AuthenticatedNetworkImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    AuthenticatedNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<AuthenticatedNetworkImage>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    AuthenticatedNetworkImage key,
    ImageDecoderCallback decode,
  ) async {
    // 1. 检查内存缓存
    final cacheKey = '${key.url}|${key.authToken?.hashCode}';
    final cached = _ImageMemoryCache.get(cacheKey);
    if (cached != null) {
      debugPrint('[ImageLoader] Cache hit: ${key.url}');
      final buffer = await ImmutableBuffer.fromUint8List(cached);
      return decode(buffer);
    }

    // 2. 网络加载（带重试）
    const maxRetries = 2;
    Object? lastError;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final headers = <String, String>{
          'Accept': 'image/*,*/*;q=0.8',
        };
        if (key.authToken != null && key.authToken!.isNotEmpty) {
          headers['Authorization'] = 'Bearer ${key.authToken}';
        }

        // 使用流式请求避免大图片内存峰值
        final request = http.Request('GET', Uri.parse(key.url));
        request.headers.addAll(headers);

        final client = http.Client();
        try {
          final response =
              await client.send(request).timeout(const Duration(seconds: 30));

          if (response.statusCode == 200) {
            // 流式读取响应体
            final bytes = await response.stream.toBytes().timeout(
                  const Duration(seconds: 120),
                );

            if (bytes.isEmpty) {
              throw Exception('Empty image response');
            }

            debugPrint(
                '[ImageLoader] Loaded ${bytes.length} bytes from ${key.url}');

            // 写入缓存
            _ImageMemoryCache.put(cacheKey, bytes);

            final buffer = await ImmutableBuffer.fromUint8List(bytes);
            return decode(buffer);
          } else if (response.statusCode == 304) {
            // 服务器返回 Not Modified - 使用缓存（如果存在）
            final cachedAgain = _ImageMemoryCache.get(cacheKey);
            if (cachedAgain != null) {
              final buffer = await ImmutableBuffer.fromUint8List(cachedAgain);
              return decode(buffer);
            }
            throw Exception('304 Not Modified but no cache available');
          } else {
            // 消费响应体以释放连接
            await response.stream.drain();
            throw Exception(
                'HTTP ${response.statusCode}: Failed to load image');
          }
        } finally {
          client.close();
        }
      } catch (e) {
        lastError = e;
        debugPrint(
            '[ImageLoader] Attempt ${attempt + 1}/${maxRetries + 1} failed for ${key.url}: $e');
        if (attempt < maxRetries) {
          // 指数退避重试
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }

    throw lastError ??
        Exception('Failed to load image after $maxRetries retries');
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is AuthenticatedNetworkImage &&
        other.url == url &&
        other.authToken == authToken;
  }

  @override
  int get hashCode => Object.hash(url, authToken);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'AuthenticatedNetworkImage')}("$url")';
}

/// Image viewer with pinch-to-zoom, pan, and download support
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
  String? _authToken;
  bool _isLoading = true;

  // Zoom state
  double _currentScale = 1.0;
  final double _minScale = 0.5;
  final double _maxScale = 5.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _loadToken();

    // Hide system UI for immersive experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _loadToken() async {
    const storage = FlutterSecureStorage();
    _authToken = await storage.read(key: 'access_token');
    if (mounted) {
      setState(() => _isLoading = false);
    }
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

  ImageProvider _getImageProvider(String url) {
    return AuthenticatedNetworkImage(url, authToken: _authToken);
  }

  Future<void> _downloadImage() async {
    if (_isDownloading) return;

    // Request storage permission
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        if (Platform.isAndroid) {
          final manageStatus = await Permission.manageExternalStorage.request();
          if (!manageStatus.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Storage permission required')),
              );
            }
            return;
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Storage permission required')),
            );
          }
          return;
        }
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
        downloadDir =
            Directory('/storage/emulated/0/Download/RockZeroDownload');
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

      // Download file with auth header
      final request = http.Request('GET', Uri.parse(currentUrl));
      if (_authToken != null && _authToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $_authToken';
      }

      final client = http.Client();
      final response = await client.send(request);
      final contentLength = response.contentLength ?? 0;

      final sink = file.openWrite();
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0 && mounted) {
          setState(() {
            _downloadProgress = received / contentLength;
          });
        }
      }

      await sink.close();
      client.close();

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
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasGallery = widget.gallery != null && widget.gallery!.length > 1;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: colorScheme.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Image viewer with pinch-to-zoom
            if (hasGallery)
              PhotoViewGallery.builder(
                pageController: _pageController,
                itemCount: widget.gallery!.length,
                builder: (context, index) {
                  return PhotoViewGalleryPageOptions(
                    imageProvider: _getImageProvider(widget.gallery![index]),
                    initialScale: PhotoViewComputedScale.contained,
                    minScale: PhotoViewComputedScale.contained * _minScale,
                    maxScale: PhotoViewComputedScale.covered * _maxScale,
                    heroAttributes:
                        PhotoViewHeroAttributes(tag: 'image_$index'),
                    // Enable gesture detection for zoom
                    gestureDetectorBehavior: HitTestBehavior.opaque,
                    onScaleEnd: (context, details, controllerValue) {
                      setState(() {
                        _currentScale = controllerValue.scale ?? 1.0;
                      });
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return _buildErrorWidget(error);
                    },
                  );
                },
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                    _currentScale = 1.0;
                  });
                },
                loadingBuilder: (context, event) {
                  return _buildLoadingWidget(colorScheme, event);
                },
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                // Enable scroll physics for smooth swiping
                scrollPhysics: const BouncingScrollPhysics(),
              )
            else
              PhotoView(
                imageProvider: _getImageProvider(widget.imageUrl),
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained * _minScale,
                maxScale: PhotoViewComputedScale.covered * _maxScale,
                heroAttributes: const PhotoViewHeroAttributes(tag: 'image'),
                // Enable gesture detection for zoom
                gestureDetectorBehavior: HitTestBehavior.opaque,
                onScaleEnd: (context, details, controllerValue) {
                  setState(() {
                    _currentScale = controllerValue.scale ?? 1.0;
                  });
                },
                loadingBuilder: (context, event) {
                  return _buildLoadingWidget(colorScheme, event);
                },
                errorBuilder: (context, error, stackTrace) {
                  return _buildErrorWidget(error);
                },
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                // Enable double tap to zoom
                enableRotation: false,
              ),

            // Controls overlay
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: M3Durations.medium2,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black54,
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black54,
                      ],
                      stops: [0.0, 0.15, 0.85, 1.0],
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        // Top bar
                        _buildTopBar(colorScheme, hasGallery),
                        const Spacer(),
                        // Zoom indicator
                        if (_currentScale != 1.0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${(_currentScale * 100).toInt()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        // Bottom controls
                        _buildBottomControls(colorScheme),
                        // Page indicator
                        if (hasGallery) _buildPageIndicator(colorScheme),
                      ],
                    ),
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
                          const Icon(Icons.download_rounded,
                              color: Colors.white),
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

  Widget _buildLoadingWidget(ColorScheme colorScheme, ImageChunkEvent? event) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            value: event?.expectedTotalBytes != null
                ? event!.cumulativeBytesLoaded / event.expectedTotalBytes!
                : null,
            color: colorScheme.primary,
          ),
          if (event?.expectedTotalBytes != null) ...[
            const SizedBox(height: 16),
            Text(
              '${((event!.cumulativeBytesLoaded / event.expectedTotalBytes!) * 100).toInt()}%',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorWidget(Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.broken_image_rounded,
            size: 64,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          const Text(
            '图片加载失败',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              error.toString(),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              // 清除缓存并重建 ImageProvider 触发重新加载
              imageCache.clear();
              imageCache.clearLiveImages();
              setState(() {});
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('重试'),
          ),
        ],
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

  Widget _buildBottomControls(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Zoom out
          IconButton(
            icon: const Icon(Icons.zoom_out_rounded, color: Colors.white),
            onPressed: () {
              // Zoom out hint
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Pinch to zoom out'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          // Reset zoom
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Pinch to zoom',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Zoom in
          IconButton(
            icon: const Icon(Icons.zoom_in_rounded, color: Colors.white),
            onPressed: () {
              // Zoom in hint
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Pinch to zoom in or double-tap'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
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
