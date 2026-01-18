import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/shell_scaffold.dart';

/// Loop mode for media playback
enum LoopMode { off, one, all, shuffle }

/// Orientation lock mode
enum OrientationLockMode { auto, portrait, landscapeLeft, landscapeRight }

/// Media player page with full controls, orientation lock, and proper fullscreen
class MediaPlayerPage extends ConsumerStatefulWidget {
  final String mediaUrl;
  final String fileName;
  final bool isVideo;
  final List<String>? playlist;
  final int currentIndex;

  const MediaPlayerPage({
    super.key,
    required this.mediaUrl,
    required this.fileName,
    required this.isVideo,
    this.playlist,
    this.currentIndex = 0,
  });

  @override
  ConsumerState<MediaPlayerPage> createState() => _MediaPlayerPageState();
}

class _MediaPlayerPageState extends ConsumerState<MediaPlayerPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;
  bool _isLoading = true;
  String? _error;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  double _volume = 1.0;
  LoopMode _loopMode = LoopMode.off;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _authToken;
  OrientationLockMode _orientationLock = OrientationLockMode.auto;
  bool _isLandscape = false;
  bool _isBuffering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterFullScreen();
    _loadTokenAndInitialize();
    _startHideControlsTimer();
    // Enable wakelock to prevent screen from turning off during video playback
    WakelockPlus.enable();
  }

  void _enterFullScreen() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    _applyOrientationLock();
    // Hide bottom navigation bar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(bottomNavVisibleProvider.notifier).hide();
      }
    });
  }

  void _applyOrientationLock() {
    switch (_orientationLock) {
      case OrientationLockMode.auto:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
      case OrientationLockMode.portrait:
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        break;
      case OrientationLockMode.landscapeLeft:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
        ]);
        break;
      case OrientationLockMode.landscapeRight:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeRight,
        ]);
        break;
    }
  }

  void _cycleOrientationLock() {
    setState(() {
      final orientation = MediaQuery.of(context).orientation;
      _isLandscape = orientation == Orientation.landscape;
      switch (_orientationLock) {
        case OrientationLockMode.auto:
          _orientationLock = _isLandscape
              ? OrientationLockMode.landscapeLeft
              : OrientationLockMode.portrait;
          break;
        default:
          _orientationLock = OrientationLockMode.auto;
          break;
      }
    });
    _applyOrientationLock();
    _showOrientationLockToast();
  }

  void _showOrientationLockToast() {
    final message = _orientationLock == OrientationLockMode.auto
        ? 'Rotation unlocked'
        : 'Rotation locked';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _orientationLock == OrientationLockMode.auto
                  ? Icons.screen_rotation_rounded
                  : Icons.screen_lock_rotation_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  IconData _getOrientationLockIcon() {
    return _orientationLock == OrientationLockMode.auto
        ? Icons.screen_rotation_rounded
        : Icons.screen_lock_rotation_rounded;
  }

  void _exitFullScreen() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    // Allow all orientations after exiting video player
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Show bottom navigation bar again
    ref.read(bottomNavVisibleProvider.notifier).show();
    // Disable wakelock
    WakelockPlus.disable();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _videoController?.dispose();
    _exitFullScreen();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _videoController?.pause();
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

      debugPrint('[MediaPlayer] ========== Initialization Start ==========');
      debugPrint('[MediaPlayer] URL: ${widget.mediaUrl}');
      debugPrint('[MediaPlayer] File: ${widget.fileName}');
      debugPrint(
          '[MediaPlayer] Auth token present: ${_authToken != null && _authToken!.isNotEmpty}');

      // Check file type for special handling
      final fileName = widget.fileName.toLowerCase();
      final isMkv = fileName.endsWith('.mkv');
      final isLargeFileFormat = isMkv ||
          fileName.endsWith('.avi') ||
          fileName.endsWith('.mov') ||
          fileName.endsWith('.m2ts') ||
          fileName.endsWith('.ts') ||
          fileName.endsWith('.webm');

      debugPrint('[MediaPlayer] File type: ${fileName.split('.').last}');
      debugPrint('[MediaPlayer] Is large format: $isLargeFileFormat');

      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.mediaUrl),
        httpHeaders: headers,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
          webOptions: const VideoPlayerWebOptions(
            allowContextMenu: false,
            allowRemotePlayback: true,
            controls: VideoPlayerWebOptionsControls.disabled(),
          ),
        ),
        // For container formats that may have complex audio, use 'other' format hint
        formatHint: isLargeFileFormat ? VideoFormat.other : null,
      );

      debugPrint(
          '[MediaPlayer] Controller created, starting initialization...');

      // Initialize with extended timeout for large files (20GB+)
      try {
        await _videoController!.initialize().timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            debugPrint('[MediaPlayer] ❌ Initialization TIMEOUT');
            throw TimeoutException(
                'Video initialization timed out. The file may be very large or the connection is slow. Please try again.');
          },
        );

        debugPrint('[MediaPlayer] Initialize() completed');
        debugPrint(
            '[MediaPlayer] Is initialized: ${_videoController!.value.isInitialized}');
        debugPrint(
            '[MediaPlayer] Has error: ${_videoController!.value.hasError}');
        debugPrint('[MediaPlayer] Size: ${_videoController!.value.size}');
        debugPrint(
            '[MediaPlayer] Duration: ${_videoController!.value.duration}');
        debugPrint(
            '[MediaPlayer] Aspect ratio: ${_videoController!.value.aspectRatio}');

        // 验证视频是否真正初始化成功
        if (!_videoController!.value.isInitialized) {
          debugPrint('[MediaPlayer] ❌ Video NOT initialized properly');
          throw Exception('Video failed to initialize properly');
        }

        // 检查是否有错误
        if (_videoController!.value.hasError) {
          final errorDesc =
              _videoController!.value.errorDescription ?? 'Unknown video error';
          debugPrint('[MediaPlayer] ❌ Video has error: $errorDesc');
          throw Exception(errorDesc);
        }
      } catch (e) {
        debugPrint('[MediaPlayer] ❌ Initialization exception: $e');
        debugPrint('[MediaPlayer] Exception type: ${e.runtimeType}');
        rethrow;
      }

      debugPrint('[MediaPlayer] Adding listener...');
      _videoController!.addListener(_onVideoUpdate);

      debugPrint('[MediaPlayer] Setting looping: ${_loopMode == LoopMode.one}');
      await _videoController!.setLooping(_loopMode == LoopMode.one);

      debugPrint('[MediaPlayer] Setting volume: $_volume');
      await _videoController!.setVolume(_volume);

      // Start playback - the player will buffer as needed
      debugPrint('[MediaPlayer] Starting playback...');
      await _videoController!.play();
      debugPrint('[MediaPlayer] Play() called');

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
          _duration = _videoController!.value.duration;
        });
      }

      debugPrint('[MediaPlayer] ✅ Initialization SUCCESS');
      debugPrint('[MediaPlayer] ========== Initialization End ==========');
    } catch (e, stackTrace) {
      debugPrint('[MediaPlayer] ❌❌❌ FATAL ERROR ❌❌❌');
      debugPrint('[MediaPlayer] Error: $e');
      debugPrint('[MediaPlayer] Error type: ${e.runtimeType}');
      debugPrint('[MediaPlayer] Stack trace: $stackTrace');

      if (mounted) {
        String errorMessage = 'Failed to load media: $e';
        final errorStr = e.toString().toLowerCase();

        // 提供更友好的错误消息
        if (errorStr.contains('source error') || errorStr.contains('x0.i')) {
          errorMessage = '❌ 视频源加载失败\n\n'
              '📋 调试信息：\n'
              'URL: ${widget.mediaUrl}\n'
              'File: ${widget.fileName}\n'
              'Error: $e\n\n'
              '🔍 可能原因：\n'
              '• 视频编码格式不被支持\n'
              '• 网络连接中断或超时\n'
              '• 服务器响应异常\n'
              '• CORS配置问题（Web平台）\n'
              '• 视频文件损坏\n\n'
              '💡 建议：\n'
              '1. 打开浏览器开发者工具（F12）\n'
              '2. 查看Network标签页的请求\n'
              '3. 确认视频URL返回200状态\n'
              '4. 检查Content-Type是否正确\n'
              '5. 尝试在浏览器直接打开视频URL';
        } else if (errorStr.contains('timeout')) {
          errorMessage = '⏱️ 视频加载超时\n\n'
              '文件: ${widget.fileName}\n\n'
              '请检查：\n'
              '• 网络连接是否稳定\n'
              '• 文件是否过大\n'
              '• 服务器是否响应正常';
        } else if (errorStr.contains('network') ||
            errorStr.contains('connection')) {
          errorMessage = '🌐 网络连接失败\n\n'
              'URL: ${widget.mediaUrl}\n\n'
              '请检查：\n'
              '• 网络连接\n'
              '• 服务器是否运行\n'
              '• 防火墙设置';
        } else if (errorStr.contains('format') || errorStr.contains('codec')) {
          errorMessage = '🎬 视频格式不支持\n\n'
              '文件: ${widget.fileName}\n\n'
              'Web平台仅支持：\n'
              '• 视频：H.264 (AVC)\n'
              '• 音频：AAC\n'
              '• 容器：MP4\n\n'
              '建议：使用HLS播放器或转换格式';
        }

        setState(() {
          _error = errorMessage;
          _isLoading = false;
        });
      }

      debugPrint('[MediaPlayer] ========== Error End ==========');
    }
  }

  void _onVideoUpdate() {
    if (_videoController != null && mounted) {
      final value = _videoController!.value;
      setState(() {
        _position = value.position;
        _duration = value.duration;
        // Track buffering state for large files
        _isBuffering = value.isBuffering;
      });
      if (value.hasError) {
        setState(() {
          _error = value.errorDescription ?? 'Unknown error';
        });
      }
      if (value.position >= value.duration &&
          value.duration > Duration.zero &&
          !value.isPlaying) {
        _handlePlaybackComplete();
      }
    }
  }

  void _handlePlaybackComplete() {
    if (_loopMode == LoopMode.one || _loopMode == LoopMode.all) {
      _videoController?.seekTo(Duration.zero);
      _videoController?.play();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _videoController?.value.isPlaying == true) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  void _togglePlayPause() {
    if (_videoController?.value.isPlaying == true) {
      _videoController?.pause();
    } else {
      _videoController?.play();
      _startHideControlsTimer();
    }
    setState(() {});
  }

  void _seekTo(Duration position) {
    _videoController?.seekTo(position);
    _startHideControlsTimer();
  }

  void _seekForward() {
    final newPos = _position + const Duration(seconds: 10);
    _seekTo(newPos > _duration ? _duration : newPos);
  }

  void _seekBackward() {
    final newPos = _position - const Duration(seconds: 10);
    _seekTo(newPos < Duration.zero ? Duration.zero : newPos);
  }

  void _setVolume(double v) {
    setState(() => _volume = v);
    _videoController?.setVolume(v);
  }

  void _cycleLoopMode() {
    setState(() {
      _loopMode =
          LoopMode.values[(_loopMode.index + 1) % LoopMode.values.length];
    });
    _videoController?.setLooping(_loopMode == LoopMode.one);
  }

  IconData _getLoopIcon() {
    switch (_loopMode) {
      case LoopMode.off:
        return Icons.repeat_rounded;
      case LoopMode.one:
        return Icons.repeat_one_rounded;
      case LoopMode.all:
        return Icons.repeat_rounded;
      case LoopMode.shuffle:
        return Icons.shuffle_rounded;
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

  String _formatDuration(Duration d) {
    final h = d.inHours,
        m = d.inMinutes.remainder(60),
        s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _exitFullScreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // Remove system UI completely during video playback
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: GestureDetector(
          behavior: HitTestBehavior
              .opaque, // Capture all taps, even on transparent areas
          onTap: _toggleControls,
          onDoubleTapDown: (d) {
            final w = MediaQuery.of(context).size.width;
            if (d.globalPosition.dx < w / 2) {
              _seekBackward();
            } else {
              _seekForward();
            }
          },
          // Add horizontal drag for seeking
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity != null) {
              if (details.primaryVelocity! > 200) {
                _seekBackward();
              } else if (details.primaryVelocity! < -200) {
                _seekForward();
              }
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Black background to ensure full coverage
              Container(color: Colors.black),
              Center(
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : _error != null
                        ? _buildErrorWidget()
                        : widget.isVideo
                            ? _buildVideoPlayer()
                            : _buildAudioPlayer(),
              ),
              if (_isInitialized)
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: M3Durations.medium2,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: _buildControlsOverlay(cs),
                  ),
                ),
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
                          valueColor: AlwaysStoppedAnimation(cs.primary),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
        // Enhanced buffering indicator overlay with progress info
        if (_isBuffering)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Buffering...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Large file streaming',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildAudioPlayer() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primary, cs.tertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.4),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.audiotrack_rounded,
            size: 80,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            widget.fileName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Padding(
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
    );
  }

  Widget _buildControlsOverlay(ColorScheme cs) {
    return Container(
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
          stops: [0.0, 0.2, 0.8, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(cs),
            const Spacer(),
            _buildCenterControls(),
            const Spacer(),
            _buildBottomControls(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
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
            icon: Icon(
              _getOrientationLockIcon(),
              color: _orientationLock == OrientationLockMode.auto
                  ? Colors.white
                  : cs.primary,
            ),
            onPressed: _cycleOrientationLock,
            tooltip: _orientationLock == OrientationLockMode.auto
                ? 'Lock rotation'
                : 'Unlock rotation',
          ),
          IconButton(
            icon: _isDownloading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : const Icon(Icons.download_rounded, color: Colors.white),
            onPressed: _isDownloading ? null : _downloadFile,
          ),
        ],
      ),
    );
  }

  Widget _buildCenterControls() {
    final isPlaying = _videoController?.value.isPlaying ?? false;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 40,
          icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
          onPressed: _seekBackward,
        ),
        const SizedBox(width: 24),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            iconSize: 48,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
            onPressed: _togglePlayPause,
          ),
        ),
        const SizedBox(width: 24),
        IconButton(
          iconSize: 40,
          icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
          onPressed: _seekForward,
        ),
      ],
    );
  }

  Widget _buildBottomControls(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: cs.primary,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: cs.primary,
                    overlayColor: cs.primary.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: _duration.inMilliseconds > 0
                        ? (_position.inMilliseconds / _duration.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0,
                    onChanged: (v) {
                      _seekTo(
                        Duration(
                          milliseconds: (v * _duration.inMilliseconds).round(),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(
                  _getLoopIcon(),
                  color:
                      _loopMode == LoopMode.off ? Colors.white54 : cs.primary,
                ),
                onPressed: _cycleLoopMode,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _volume == 0
                          ? Icons.volume_off_rounded
                          : _volume < 0.5
                              ? Icons.volume_down_rounded
                              : Icons.volume_up_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () => _setVolume(_volume == 0 ? 1.0 : 0),
                  ),
                  SizedBox(
                    width: 100,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(value: _volume, onChanged: _setVolume),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 48),
            ],
          ),
        ],
      ),
    );
  }
}
