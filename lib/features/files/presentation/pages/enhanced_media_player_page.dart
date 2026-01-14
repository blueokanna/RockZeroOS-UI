import 'dart:async';
import 'dart:io';

import 'package:better_player/better_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/widgets/shell_scaffold.dart';

/// Enhanced media player with ExoPlayer support for DTS, AC3, and better buffering
class EnhancedMediaPlayerPage extends ConsumerStatefulWidget {
  final String mediaUrl;
  final String fileName;
  final bool isVideo;

  const EnhancedMediaPlayerPage({
    super.key,
    required this.mediaUrl,
    required this.fileName,
    required this.isVideo,
  });

  @override
  ConsumerState<EnhancedMediaPlayerPage> createState() =>
      _EnhancedMediaPlayerPageState();
}

class _EnhancedMediaPlayerPageState
    extends ConsumerState<EnhancedMediaPlayerPage> with WidgetsBindingObserver {
  BetterPlayerController? _betterPlayerController;
  bool _isLoading = true;
  String? _error;
  String? _authToken;
  bool _isDownloading = false;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterFullScreen();
    _loadTokenAndInitialize();
    WakelockPlus.enable();
  }

  void _enterFullScreen() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(bottomNavVisibleProvider.notifier).hide();
      }
    });
  }

  void _exitFullScreen() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    ref.read(bottomNavVisibleProvider.notifier).show();
    WakelockPlus.disable();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _betterPlayerController?.dispose();
    _exitFullScreen();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _betterPlayerController?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _enterFullScreen();
    }
  }

  Future<void> _loadTokenAndInitialize() async {
    const storage = FlutterSecureStorage();
    _authToken = await storage.read(key: 'access_token');
    await _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final headers = <String, String>{
        'Accept': '*/*',
        'Accept-Ranges': 'bytes',
        'Connection': 'keep-alive',
      };
      if (_authToken != null && _authToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_authToken';
      }

      // Detect file type for optimal configuration
      final fileName = widget.fileName.toLowerCase();
      final isMkv = fileName.endsWith('.mkv');

      // Configure BetterPlayer with aggressive buffering and ExoPlayer optimizations
      final betterPlayerDataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.mediaUrl,
        headers: headers,
        // Enable caching for smoother playback with larger buffers
        cacheConfiguration: const BetterPlayerCacheConfiguration(
          useCache: true,
          preCacheSize: 50 * 1024 * 1024, // 50MB pre-cache for faster start
          maxCacheSize: 500 * 1024 * 1024, // 500MB max cache
          maxCacheFileSize: 200 * 1024 * 1024, // 200MB per file
        ),
        // Buffer configuration for smooth playback
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 15000, // 15 seconds minimum buffer
          maxBufferMs: 50000, // 50 seconds maximum buffer
          bufferForPlaybackMs: 2500, // Start playback after 2.5 seconds
          bufferForPlaybackAfterRebufferMs:
              5000, // Resume after 5 seconds rebuffer
        ),
        // Notify when buffering state changes
        notificationConfiguration: const BetterPlayerNotificationConfiguration(
          showNotification: false,
        ),
      );

      final betterPlayerConfiguration = BetterPlayerConfiguration(
        // Aspect ratio handling
        aspectRatio: 16 / 9,
        fit: BoxFit.contain,
        // Auto play
        autoPlay: true,
        looping: false,
        // Full screen by default
        autoDetectFullscreenAspectRatio: true,
        autoDetectFullscreenDeviceOrientation: true,
        // Control bar configuration
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enableFullscreen: true,
          enablePip: true,
          enableSkips: true,
          enableAudioTracks: true,
          enableSubtitles: true,
          enableQualities: false,
          enablePlaybackSpeed: true,
          enableMute: true,
          enableProgressBar: true,
          enableProgressText: true,
          enableProgressBarDrag: true,
          showControlsOnInitialize: true,
          controlBarColor: Colors.black.withValues(alpha: 0.5),
          iconsColor: Colors.white,
          progressBarPlayedColor: Theme.of(context).colorScheme.primary,
          progressBarHandleColor: Theme.of(context).colorScheme.primary,
          progressBarBufferedColor: Colors.white38,
          progressBarBackgroundColor: Colors.white24,
          // Skip durations
          forwardSkipTimeInMilliseconds: 10000, // 10 seconds
          backwardSkipTimeInMilliseconds: 10000, // 10 seconds
          // Show controls for 3 seconds
          controlsHideTime: const Duration(seconds: 3),
          // Custom loading widget
          loadingWidget: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading ${widget.fileName}...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
                if (isMkv) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Processing MKV container',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Event listeners
        eventListener: (BetterPlayerEvent event) {
          if (event.betterPlayerEventType ==
              BetterPlayerEventType.initialized) {
            setState(() {
              _isLoading = false;
            });
          } else if (event.betterPlayerEventType ==
              BetterPlayerEventType.exception) {
            setState(() {
              _error = 'Playback error occurred';
              _isLoading = false;
            });
          }
        },
        // Error handling
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white54,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    errorMessage ?? 'Unknown error',
                    style: const TextStyle(color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _initializePlayer,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        },
        // Translations
        translations: [
          BetterPlayerTranslations(
            languageCode: 'en',
            generalDefaultError: 'Failed to load video',
            generalNone: 'None',
            generalDefault: 'Default',
            generalRetry: 'Retry',
            playlistLoadingNextVideo: 'Loading next video',
            controlsLive: 'LIVE',
            controlsNextVideoIn: 'Next video in',
            overflowMenuPlaybackSpeed: 'Playback speed',
            overflowMenuAudioTracks: 'Audio tracks',
            overflowMenuSubtitles: 'Subtitles',
            overflowMenuQuality: 'Quality',
          ),
        ],
      );

      _betterPlayerController = BetterPlayerController(
        betterPlayerConfiguration,
        betterPlayerDataSource: betterPlayerDataSource,
      );

      // For Android, configure ExoPlayer for better codec support
      if (!kIsWeb && Platform.isAndroid) {
        // ExoPlayer will automatically handle DTS, AC3, EAC3, TrueHD, etc.
        // through Android's MediaCodec API
        debugPrint('[EnhancedPlayer] Using ExoPlayer for ${widget.fileName}');
        if (isMkv) {
          debugPrint(
              '[EnhancedPlayer] MKV detected - ExoPlayer will handle complex audio codecs');
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load media: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _downloadFile() async {
    if (_isDownloading) return;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        if (Platform.isAndroid) {
          final ms = await Permission.manageExternalStorage.request();
          if (!ms.isGranted) {
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

      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final filePath = '${downloadDir.path}/${widget.fileName}';
      final file = File(filePath);

      final request = http.Request('GET', Uri.parse(widget.mediaUrl));
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
                Expanded(child: Text('Downloaded to ${downloadDir.path}')),
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
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _exitFullScreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else if (_error != null)
              _buildErrorWidget()
            else if (_betterPlayerController != null)
              BetterPlayer(controller: _betterPlayerController!),
            // Download progress overlay
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
                        valueColor: AlwaysStoppedAnimation(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Custom top bar with download button
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () {
                          _exitFullScreen();
                          Navigator.pop(context);
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.fileName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: _isDownloading
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              )
                            : const Icon(Icons.download_rounded,
                                color: Colors.white),
                        onPressed: _isDownloading ? null : _downloadFile,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Unknown error',
              style: const TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _initializePlayer,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
