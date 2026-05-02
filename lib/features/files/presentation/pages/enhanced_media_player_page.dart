import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/shell_scaffold.dart';

enum LoopMode { off, one, all }

enum OrientationLockMode { auto, portrait, landscape }

class EnhancedMediaPlayerPage extends ConsumerStatefulWidget {
  final String mediaUrl;
  final String fileName;
  final bool isVideo;
  final List<String>? playlist;
  final int currentIndex;

  const EnhancedMediaPlayerPage({
    super.key,
    required this.mediaUrl,
    required this.fileName,
    required this.isVideo,
    this.playlist,
    this.currentIndex = 0,
  });

  @override
  ConsumerState<EnhancedMediaPlayerPage> createState() =>
      _EnhancedMediaPlayerPageState();
}

class _EnhancedMediaPlayerPageState
    extends ConsumerState<EnhancedMediaPlayerPage> with WidgetsBindingObserver {
  Player? _player;
  VideoController? _videoController;
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
  bool _isBuffering = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterFullScreen();
    _loadTokenAndInitialize();
    _startHideControlsTimer();
    WakelockPlus.enable();
  }

  void _enterFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values);
    _applyOrientationLock();
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
      case OrientationLockMode.landscape:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
    }
  }

  void _cycleOrientationLock() {
    setState(() {
      _orientationLock = OrientationLockMode.values[
          (_orientationLock.index + 1) % OrientationLockMode.values.length];
    });
    _applyOrientationLock();
  }

  void _exitFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values);
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
    _hideControlsTimer?.cancel();
    _player?.dispose();
    _exitFullScreen();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _player?.pause();
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
      debugPrint('[EnhancedMediaPlayer] Initializing: ${widget.mediaUrl}');

      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024,
        ),
      );

      _videoController = VideoController(
        _player!,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );

      if (_player!.platform is NativePlayer) {
        final mpv = _player!.platform as NativePlayer;
        await mpv.setProperty('rebase-start-time', 'yes');
        await mpv.setProperty(
          'demuxer-lavf-o',
          'fflags=+genpts+discardcorrupt',
        );
        await mpv.setProperty('hwdec', 'auto-safe');
        await mpv.setProperty('cache', 'yes');
        await mpv.setProperty('cache-secs', '30');
        await mpv.setProperty('demuxer-max-bytes', '64MiB');
        await mpv.setProperty('demuxer-readahead-secs', '10');
      }

      _player!.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      });

      _player!.stream.position.listen((position) {
        if (mounted) setState(() => _position = position);
      });

      _player!.stream.duration.listen((duration) {
        if (mounted) setState(() => _duration = duration);
      });

      _player!.stream.buffering.listen((buffering) {
        if (mounted) setState(() => _isBuffering = buffering);
      });

      _player!.stream.error.listen((error) {
        if (error.isNotEmpty && mounted) {
          debugPrint('[EnhancedMediaPlayer] Error: $error');
          setState(() => _error = error);
        }
      });

      _player!.stream.completed.listen((completed) {
        if (completed && mounted) {
          _handlePlaybackComplete();
        }
      });

      final headers = <String, String>{};
      if (_authToken != null && _authToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_authToken';
      }

      await _player!.open(
        Media(widget.mediaUrl, httpHeaders: headers),
        play: true,
      );

      await _player!.setVolume(_volume * 100);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
        });
      }

      debugPrint('[EnhancedMediaPlayer] Initialized successfully');
    } catch (e, stack) {
      debugPrint('[EnhancedMediaPlayer] Error: $e');
      debugPrint('[EnhancedMediaPlayer] Stack: $stack');

      if (mounted) {
        setState(() {
          _error = 'Error messages: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _handlePlaybackComplete() {
    if (_loopMode == LoopMode.one || _loopMode == LoopMode.all) {
      _player?.seek(Duration.zero);
      _player?.play();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _player?.pause();
    } else {
      _player?.play();
      _startHideControlsTimer();
    }
  }

  void _seekTo(Duration position) {
    _player?.seek(position);
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
    _player?.setVolume(v * 100);
  }

  void _cycleLoopMode() {
    setState(() {
      _loopMode =
          LoopMode.values[(_loopMode.index + 1) % LoopMode.values.length];
    });
    _player?.setPlaylistMode(
      _loopMode == LoopMode.one ? PlaylistMode.single : PlaylistMode.none,
    );
  }

  IconData _getLoopIcon() {
    switch (_loopMode) {
      case LoopMode.off:
        return Icons.repeat_rounded;
      case LoopMode.one:
        return Icons.repeat_one_rounded;
      case LoopMode.all:
        return Icons.repeat_rounded;
    }
  }

  Future<void> _downloadFile() async {
    if (_isDownloading) return;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.storage.request();
      if (!status.isGranted && Platform.isAndroid) {
        final ms = await Permission.manageExternalStorage.request();
        if (!ms.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Storage permission is required')),
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
        throw Exception('Unable to resolve download directory');
      }
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final file = File('${downloadDir.path}/${widget.fileName}');
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
          setState(() => _downloadProgress = received / contentLength);
        }
      }

      await sink.close();
      client.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded to ${downloadDir.path}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Download failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
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
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          onDoubleTapDown: (d) {
            final w = MediaQuery.of(context).size.width;
            if (d.globalPosition.dx < w / 2) {
              _seekBackward();
            } else {
              _seekForward();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
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
              if (_isBuffering && !_isLoading)
                const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
              if (_isDownloading) _buildDownloadProgress(cs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_videoController == null) return const SizedBox.shrink();
    return SizedBox.expand(
      child: Video(
        controller: _videoController!,
        fill: Colors.black,
        controls: NoVideoControls,
      ),
    );
  }

  Widget _buildAudioPlayer() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.grey.shade800,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.music_note, size: 100, color: Colors.white54),
        ),
        const SizedBox(height: 24),
        Text(
          widget.fileName,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          textAlign: TextAlign.center,
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
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(_error!,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center),
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
            Colors.black54
          ],
          stops: [0.0, 0.2, 0.8, 1.0],
        ),
      ),
      child: Column(
        children: [
          _buildTopBar(cs),
          const Spacer(),
          _buildCenterControls(),
          const Spacer(),
          _buildBottomBar(cs),
        ],
      ),
    );
  }

  Widget _buildTopBar(ColorScheme cs) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                _exitFullScreen();
                Navigator.pop(context);
              },
            ),
            Expanded(
              child: Text(
                widget.fileName,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(
                _orientationLock == OrientationLockMode.auto
                    ? Icons.screen_rotation_rounded
                    : Icons.screen_lock_rotation_rounded,
                color: Colors.white,
              ),
              onPressed: _cycleOrientationLock,
            ),
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white),
              onPressed: _downloadFile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 48,
          icon: const Icon(Icons.replay_10, color: Colors.white),
          onPressed: _seekBackward,
        ),
        const SizedBox(width: 32),
        Container(
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(40),
          ),
          child: IconButton(
            iconSize: 64,
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white),
            onPressed: _togglePlayPause,
          ),
        ),
        const SizedBox(width: 32),
        IconButton(
          iconSize: 48,
          icon: const Icon(Icons.forward_10, color: Colors.white),
          onPressed: _seekForward,
        ),
      ],
    );
  }

  Widget _buildBottomBar(ColorScheme cs) {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                activeTrackColor: cs.primary,
                inactiveTrackColor: Colors.white24,
                thumbColor: cs.primary,
              ),
              child: Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: (value) {
                  final newPosition = Duration(
                    milliseconds: (value * _duration.inMilliseconds).round(),
                  );
                  _seekTo(newPosition);
                },
              ),
            ),
            Row(
              children: [
                Text(_formatDuration(_position),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
                const Spacer(),
                IconButton(
                    icon: Icon(_getLoopIcon(), color: Colors.white70, size: 20),
                    onPressed: _cycleLoopMode),
                SizedBox(
                  width: 100,
                  child: Row(
                    children: [
                      Icon(_volume == 0 ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white70, size: 20),
                      Expanded(
                        child: Slider(
                          value: _volume,
                          onChanged: _setVolume,
                          activeColor: Colors.white70,
                          inactiveColor: Colors.white24,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(_formatDuration(_duration),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadProgress(ColorScheme cs) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.black87, borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.download_rounded, color: Colors.white),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('Downloading...',
                        style: TextStyle(color: Colors.white))),
                Text('${(_downloadProgress * 100).toInt()}%',
                    style: const TextStyle(color: Colors.white)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: _downloadProgress,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation(cs.primary)),
          ],
        ),
      ),
    );
  }
}
