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

import '../../../../core/theme/app_theme.dart';

/// Loop mode for media playback
enum LoopMode { off, one, all, shuffle }

/// Media player page with full controls
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterFullScreen();
    _loadTokenAndInitialize();
    _startHideControlsTimer();
  }

  /// Enter immersive full screen mode
  void _enterFullScreen() {
    // Hide system UI (status bar and navigation bar)
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );

    // Allow all orientations for video, enable auto-rotation with gravity sensor
    if (widget.isVideo) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  /// Exit full screen mode
  void _exitFullScreen() {
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );

    // Reset to portrait only
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
    // Get auth token from secure storage
    const storage = FlutterSecureStorage();
    _authToken = await storage.read(key: 'access_token');
    debugPrint('Auth token loaded: ${_authToken != null ? "yes" : "no"}');
    await _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Build headers with auth token
      final headers = <String, String>{'Accept': '*/*'};
      if (_authToken != null && _authToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_authToken';
      }

      debugPrint('Media URL: ${widget.mediaUrl}');
      debugPrint('Using auth header: ${headers.containsKey("Authorization")}');

      // Create video controller with network URL and headers
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.mediaUrl),
        httpHeaders: headers,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      // Initialize the controller
      await _videoController!.initialize();

      // Add listener for updates
      _videoController!.addListener(_onVideoUpdate);

      // Set looping based on mode
      await _videoController!.setLooping(_loopMode == LoopMode.one);

      // Set initial volume
      await _videoController!.setVolume(_volume);

      // Auto play
      await _videoController!.play();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
          _duration = _videoController!.value.duration;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Video initialization error: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _error = 'Failed to load media: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onVideoUpdate() {
    if (_videoController != null && mounted) {
      final value = _videoController!.value;
      setState(() {
        _position = value.position;
        _duration = value.duration;
      });

      // Check for errors
      if (value.hasError) {
        setState(() {
          _error = value.errorDescription ?? 'Unknown playback error';
        });
      }

      // Handle playback complete
      if (value.position >= value.duration &&
          value.duration > Duration.zero &&
          !value.isPlaying) {
        _handlePlaybackComplete();
      }
    }
  }

  void _handlePlaybackComplete() {
    switch (_loopMode) {
      case LoopMode.one:
        _videoController?.seekTo(Duration.zero);
        _videoController?.play();
        break;
      case LoopMode.all:
        if (widget.playlist != null &&
            widget.currentIndex < widget.playlist!.length - 1) {
          // Navigate to next - implement if needed
        } else {
          _videoController?.seekTo(Duration.zero);
          _videoController?.play();
        }
        break;
      case LoopMode.shuffle:
        // Random next - implement if needed
        break;
      case LoopMode.off:
        // Do nothing
        break;
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
    if (_showControls) {
      _startHideControlsTimer();
    }
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
    final newPosition = _position + const Duration(seconds: 10);
    _seekTo(newPosition > _duration ? _duration : newPosition);
  }

  void _seekBackward() {
    final newPosition = _position - const Duration(seconds: 10);
    _seekTo(newPosition < Duration.zero ? Duration.zero : newPosition);
  }

  void _setVolume(double volume) {
    setState(() => _volume = volume);
    _videoController?.setVolume(volume);
  }

  void _cycleLoopMode() {
    setState(() {
      switch (_loopMode) {
        case LoopMode.off:
          _loopMode = LoopMode.one;
          break;
        case LoopMode.one:
          _loopMode = LoopMode.all;
          break;
        case LoopMode.all:
          _loopMode = LoopMode.shuffle;
          break;
        case LoopMode.shuffle:
          _loopMode = LoopMode.off;
          break;
      }
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

    // Request storage permission on mobile
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        // Try requesting manage external storage for Android 11+
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

      // Download with auth header
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

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _exitFullScreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            children: [
              // Media content
              Center(
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : _error != null
                        ? _buildErrorWidget()
                        : widget.isVideo
                            ? _buildVideoPlayer()
                            : _buildAudioPlayer(),
              ),

              // Controls overlay
              if (_isInitialized)
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: M3Durations.medium2,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: _buildControlsOverlay(colorScheme),
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
                          valueColor: AlwaysStoppedAnimation(
                            colorScheme.primary,
                          ),
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

    return AspectRatio(
      aspectRatio: _videoController!.value.aspectRatio,
      child: VideoPlayer(_videoController!),
    );
  }

  Widget _buildAudioPlayer() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colorScheme.primary, colorScheme.tertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.4),
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
          const SizedBox(height: 16),
          Text(
            'URL: ${widget.mediaUrl}',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
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

  Widget _buildControlsOverlay(ColorScheme colorScheme) {
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
            _buildTopBar(colorScheme),
            const Spacer(),
            _buildCenterControls(),
            const Spacer(),
            _buildBottomControls(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(ColorScheme colorScheme) {
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

  Widget _buildBottomControls(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
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
                    activeTrackColor: colorScheme.primary,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: colorScheme.primary,
                    overlayColor: colorScheme.primary.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: _duration.inMilliseconds > 0
                        ? (_position.inMilliseconds / _duration.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0,
                    onChanged: (value) {
                      final newPosition = Duration(
                        milliseconds:
                            (value * _duration.inMilliseconds).round(),
                      );
                      _seekTo(newPosition);
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
          // Additional controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Loop mode
              IconButton(
                icon: Icon(
                  _getLoopIcon(),
                  color: _loopMode == LoopMode.off
                      ? Colors.white54
                      : colorScheme.primary,
                ),
                onPressed: _cycleLoopMode,
              ),
              // Volume
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
              // Placeholder for symmetry
              const SizedBox(width: 48),
            ],
          ),
        ],
      ),
    );
  }
}
