import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
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
  ChewieController? _chewieController;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePlayer();
    _startHideControlsTimer();

    // Lock orientation for video
    if (widget.isVideo) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _videoController?.dispose();
    _chewieController?.dispose();

    // Reset orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _videoController?.pause();
    }
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.mediaUrl),
        httpHeaders: {'Accept': '*/*'},
      );

      await _videoController!.initialize();

      _videoController!.addListener(_onVideoUpdate);

      if (widget.isVideo) {
        _chewieController = ChewieController(
          videoPlayerController: _videoController!,
          autoPlay: true,
          looping: _loopMode == LoopMode.one,
          showControls: false, // We use custom controls
          aspectRatio: _videoController!.value.aspectRatio,
          allowFullScreen: true,
          allowMuting: true,
          placeholder: Container(color: Colors.black),
          errorBuilder: (context, errorMessage) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    errorMessage,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        );
      } else {
        // Audio only - auto play
        await _videoController!.play();
      }

      setState(() {
        _isInitialized = true;
        _isLoading = false;
        _duration = _videoController!.value.duration;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load media: $e';
        _isLoading = false;
      });
    }
  }

  void _onVideoUpdate() {
    if (_videoController != null && mounted) {
      setState(() {
        _position = _videoController!.value.position;
        _duration = _videoController!.value.duration;
      });

      // Handle loop modes
      if (_videoController!.value.position >=
          _videoController!.value.duration) {
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
        // Play next in playlist or restart
        if (widget.playlist != null &&
            widget.currentIndex < widget.playlist!.length - 1) {
          // Navigate to next
        } else {
          _videoController?.seekTo(Duration.zero);
          _videoController?.play();
        }
        break;
      case LoopMode.shuffle:
        // Random next
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

      final filePath = '${downloadDir.path}/${widget.fileName}';
      final file = File(filePath);

      // Download file
      final request = http.Request('GET', Uri.parse(widget.mediaUrl));
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
      setState(() => _isDownloading = false);
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

    return Scaffold(
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
                child: _buildControlsOverlay(colorScheme),
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

  Widget _buildVideoPlayer() {
    if (_chewieController == null) return const SizedBox.shrink();
    return Chewie(controller: _chewieController!);
  }

  Widget _buildAudioPlayer() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Album art placeholder
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
        // Title
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
    return Column(
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
    );
  }

  Widget _buildControlsOverlay(ColorScheme colorScheme) {
    return Container(
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
          stops: const [0.0, 0.2, 0.8, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            _buildTopBar(colorScheme),

            const Spacer(),

            // Center controls
            _buildCenterControls(),

            const Spacer(),

            // Bottom controls
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
            onPressed: () => Navigator.pop(context),
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
        // Rewind
        IconButton(
          iconSize: 40,
          icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
          onPressed: _seekBackward,
        ),
        const SizedBox(width: 24),
        // Play/Pause
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
        // Forward
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
                        ? _position.inMilliseconds / _duration.inMilliseconds
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
                    onPressed: () {
                      _setVolume(_volume == 0 ? 1.0 : 0);
                    },
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
              // Fullscreen (video only)
              if (widget.isVideo)
                IconButton(
                  icon: const Icon(
                    Icons.fullscreen_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    _chewieController?.enterFullScreen();
                  },
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ],
      ),
    );
  }
}
