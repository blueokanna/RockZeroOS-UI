import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/services/audio_player_service.dart';
import '../../../../core/widgets/shell_scaffold.dart';

/// Enhanced audio player with improved stability and seek support
class EnhancedAudioPlayerPage extends ConsumerStatefulWidget {
  final String mediaUrl;
  final String fileName;

  const EnhancedAudioPlayerPage({
    super.key,
    required this.mediaUrl,
    required this.fileName,
  });

  @override
  ConsumerState<EnhancedAudioPlayerPage> createState() =>
      _EnhancedAudioPlayerPageState();
}

class _EnhancedAudioPlayerPageState
    extends ConsumerState<EnhancedAudioPlayerPage>
    with TickerProviderStateMixin {
  AudioPlayer? _audioPlayer;
  bool _isInitialized = false;
  String? _error;
  String? _authToken;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isLooping = false;
  bool _isSeeking = false;
  double _volume = 1.0;
  double _speed = 1.0;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  String? _audioCodec;
  bool _isTranscoding = false;
  String? _transcodeUrl;
  double? _mediaDuration;
  bool _disposed = false;

  late AnimationController _rotationController;
  final List<double> _audioLevels = List.filled(24, 0.1);
  Timer? _visualizationTimer;

  // State captured from global AudioPlayerService when resuming from mini-player
  Duration? _resumePosition;
  double? _resumeVolume;
  double? _resumeSpeed;
  bool _resumeLooping = false;
  bool _resumeFromGlobalService = false;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _bufferedSubscription;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    _loadTokenAndInitialize();
    WakelockPlus.enable();
  }

  void _startVisualization() {
    _visualizationTimer?.cancel();
    // 200ms interval (5 fps) — sufficient for visual feedback,
    // avoids excessive rebuilds on Snapdragon 835 class SoCs.
    _visualizationTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (timer) {
        if (!mounted || _disposed) return;
        bool needsUpdate = false;
        for (int i = 0; i < _audioLevels.length; i++) {
          final oldValue = _audioLevels[i];
          if (_isPlaying && !_isBuffering) {
            final target = math.Random().nextDouble() * 0.7 + 0.3;
            _audioLevels[i] = _audioLevels[i] * 0.6 + target * 0.4;
          } else {
            _audioLevels[i] = (_audioLevels[i] * 0.85).clamp(0.1, 1.0);
          }
          if ((oldValue - _audioLevels[i]).abs() > 0.03) needsUpdate = true;
        }
        if (needsUpdate && mounted && !_disposed) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _visualizationTimer?.cancel();
    _rotationController.dispose();
    _cancelSubscriptions();
    _audioPlayer?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  void _cancelSubscriptions() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _bufferedSubscription?.cancel();
    _playerStateSubscription = null;
    _positionSubscription = null;
    _durationSubscription = null;
    _bufferedSubscription = null;
  }

  Future<void> _loadTokenAndInitialize() async {
    // If the global AudioPlayerService is already playing the same URL
    // (i.e. user tapped the mini-player), capture its state and stop it
    // to prevent dual playback.
    final globalState = ref.read(audioPlayerServiceProvider);
    if (globalState.hasAudio && globalState.currentUrl == widget.mediaUrl) {
      _resumeFromGlobalService = true;
      _resumePosition = globalState.position;
      _resumeVolume = globalState.volume;
      _resumeSpeed = globalState.speed;
      _resumeLooping = globalState.isLooping;
      // Stop global service immediately — kills mini-player audio
      await ref.read(audioPlayerServiceProvider.notifier).stop();
    }

    const storage = FlutterSecureStorage();
    _authToken = await storage.read(key: 'access_token');
    await _fetchMediaInfo();
    await _initializePlayer();
  }

  Future<void> _fetchMediaInfo() async {
    try {
      final uri = Uri.parse(widget.mediaUrl);
      final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';

      // 从 stream URL 提取原始文件路径
      // 支持两种 URL 格式：
      // 1. /api/v1/streaming/play/{path}
      // 2. /api/v1/filemanager/media/stream?path={encoded_path}
      String infoPath = '';

      // 优先从 query 参数获取（filemanager 格式）
      final queryPath = uri.queryParameters['path'];
      if (queryPath != null && queryPath.isNotEmpty) {
        infoPath = queryPath;
        if (!infoPath.startsWith('/')) infoPath = '/$infoPath';
      } else {
        // 从 URL 路径提取（streaming 格式）
        final pathSegments = uri.pathSegments;
        bool foundPlay = false;
        for (final segment in pathSegments) {
          if (foundPlay) infoPath += '/$segment';
          if (segment == 'play' || segment == 'stream') foundPlay = true;
        }
      }

      if (infoPath.isEmpty) {
        debugPrint('[AudioPlayer] Could not extract file path from URL');
        return;
      }

      // URI 编码路径用于 info 请求
      final encodedPath = Uri.encodeComponent(
          infoPath.startsWith('/') ? infoPath.substring(1) : infoPath);
      final infoUrl = '$baseUrl/api/v1/streaming/info/$encodedPath';
      debugPrint('[AudioPlayer] Fetching media info from: $infoUrl');

      final response = await http.get(
        Uri.parse(infoUrl),
        headers:
            _authToken != null ? {'Authorization': 'Bearer $_authToken'} : {},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        _audioCodec = json['audio_codec'];
        final needsTranscode = json['needs_audio_transcode'] ?? false;
        _transcodeUrl = json['transcode_url'];
        _mediaDuration = (json['duration'] as num?)?.toDouble();

        if (needsTranscode && _transcodeUrl != null) {
          _isTranscoding = true;
        }

        debugPrint('[AudioPlayer] Audio codec: $_audioCodec');
        debugPrint('[AudioPlayer] Needs transcode: $needsTranscode');
        debugPrint('[AudioPlayer] Duration: $_mediaDuration');
      }
    } catch (e) {
      debugPrint('[AudioPlayer] Failed to fetch media info: $e');
    }
  }

  String _getStreamUrl() {
    if (_isTranscoding && _transcodeUrl != null) {
      final uri = Uri.parse(widget.mediaUrl);
      final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';
      return '$baseUrl$_transcodeUrl';
    }
    return widget.mediaUrl;
  }

  Future<void> _initializePlayer() async {
    if (_disposed) return;

    setState(() {
      _isInitialized = false;
      _error = null;
    });

    try {
      // Dispose previous player if exists
      _cancelSubscriptions();
      await _audioPlayer?.dispose();
      _audioPlayer = AudioPlayer();

      final headers = <String, String>{};
      if (_authToken != null && _authToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_authToken';
      }

      final streamUrl = _getStreamUrl();
      debugPrint('[AudioPlayer] Using stream URL: $streamUrl');

      // Try multiple audio source strategies in order of preference:
      // 1. LockCachingAudioSource (supports seeking with caching)
      // 2. AudioSource.uri with headers (basic URL streaming)
      // 3. Plain setUrl fallback (simplest)
      bool sourceSet = false;

      // Strategy 1: LockCachingAudioSource — best for seek support
      if (!sourceSet) {
        try {
          // ignore: experimental_member_use
          final audioSource = LockCachingAudioSource(
            Uri.parse(streamUrl),
            headers: headers,
          );
          await _audioPlayer!.setAudioSource(audioSource).timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              throw TimeoutException('LockCaching audio source timed out');
            },
          );
          sourceSet = true;
          debugPrint('[AudioPlayer] LockCachingAudioSource succeeded');
        } catch (e) {
          debugPrint('[AudioPlayer] LockCachingAudioSource failed: $e');
        }
      }

      // Strategy 2: AudioSource.uri with headers
      if (!sourceSet) {
        try {
          await _audioPlayer!
              .setAudioSource(
            AudioSource.uri(
              Uri.parse(streamUrl),
              headers: headers,
            ),
          )
              .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              throw TimeoutException('AudioSource.uri timed out');
            },
          );
          sourceSet = true;
          debugPrint('[AudioPlayer] AudioSource.uri succeeded');
        } catch (e) {
          debugPrint('[AudioPlayer] AudioSource.uri failed: $e');
        }
      }

      // Strategy 3: setUrl (simplest, works for most straightforward streams)
      if (!sourceSet) {
        try {
          await _audioPlayer!.setUrl(streamUrl, headers: headers).timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              throw TimeoutException('setUrl timed out');
            },
          );
          sourceSet = true;
          debugPrint('[AudioPlayer] setUrl succeeded');
        } catch (e) {
          debugPrint('[AudioPlayer] setUrl also failed: $e');
        }
      }

      if (!sourceSet) {
        throw Exception('All audio source strategies failed');
      }

      _setupListeners();
      _startVisualization();
      _retryCount = 0;

      if (mounted && !_disposed) {
        setState(() => _isInitialized = true);
      }

      // Restore state from global service if resuming from mini-player
      if (_resumeFromGlobalService) {
        if (_resumeVolume != null && _resumeVolume != 1.0) {
          _volume = _resumeVolume!;
          await _audioPlayer!.setVolume(_resumeVolume!);
        }
        if (_resumeSpeed != null && _resumeSpeed != 1.0) {
          _speed = _resumeSpeed!;
          await _audioPlayer!.setSpeed(_resumeSpeed!);
        }
        if (_resumeLooping) {
          _isLooping = true;
          await _audioPlayer!.setLoopMode(LoopMode.one);
        }
        // Seek to the position the global service was at
        if (_resumePosition != null && _resumePosition! > Duration.zero) {
          await _audioPlayer!.seek(_resumePosition!);
        }
        _resumeFromGlobalService = false;
      }

      // Start playing
      await _audioPlayer!.play();
    } catch (e) {
      debugPrint('[AudioPlayer] Error: $e');

      if (_retryCount < _maxRetries) {
        _retryCount++;
        debugPrint(
            '[AudioPlayer] Retrying... attempt $_retryCount/$_maxRetries');
        await Future.delayed(Duration(milliseconds: 500 * _retryCount));
        if (mounted && !_disposed) await _initializePlayer();
        return;
      }

      // Try transcoded stream if direct stream failed
      if (!_isTranscoding && _transcodeUrl != null) {
        debugPrint('[AudioPlayer] Retrying with transcoded stream...');
        _isTranscoding = true;
        _retryCount = 0;
        await _initializePlayer();
        return;
      }

      if (mounted && !_disposed) setState(() => _error = _getErrorMessage(e));
    }
  }

  void _setupListeners() {
    _playerStateSubscription = _audioPlayer!.playerStateStream.listen((state) {
      if (!mounted || _disposed) return;
      final playing = state.playing;
      final processing = state.processingState;

      setState(() {
        _isPlaying = playing;
        _isBuffering = processing == ProcessingState.buffering ||
            processing == ProcessingState.loading;
      });

      // Reset seeking state when buffering completes
      if (_isSeeking && !_isBuffering && processing == ProcessingState.ready) {
        setState(() => _isSeeking = false);
      }

      if (playing && !_isBuffering) {
        _rotationController.repeat();
      } else {
        _rotationController.stop();
      }

      // Handle completion
      if (processing == ProcessingState.completed) {
        if (_isLooping) {
          _audioPlayer?.seek(Duration.zero);
          _audioPlayer?.play();
        }
      }
    });

    _positionSubscription = _audioPlayer!.positionStream.listen((position) {
      if (mounted && !_disposed) {
        // Always update position, even when seeking
        // This ensures the progress bar moves correctly
        setState(() => _position = position);

        // If we're seeking and position is close to target, reset seeking state
        if (_isSeeking) {
          // Position is being updated, so seek is progressing
          debugPrint('[AudioPlayer] Position update during seek: $position');
        }
      }
    });

    _durationSubscription = _audioPlayer!.durationStream.listen((duration) {
      if (mounted && !_disposed && duration != null) {
        setState(() => _duration = duration);
      }
    });

    _bufferedSubscription =
        _audioPlayer!.bufferedPositionStream.listen((buffered) {
      if (mounted && !_disposed) {
        setState(() => _bufferedPosition = buffered);
      }
    });
  }

  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('codec') || errorStr.contains('format')) {
      return '不支持的音频格式\n编码: ${_audioCodec ?? "unknown"}';
    }
    if (errorStr.contains('network') ||
        errorStr.contains('connection') ||
        errorStr.contains('timeout')) {
      return '网络错误，请检查连接';
    }
    return '加载音频失败: $error';
  }

  void _togglePlayPause() async {
    if (_audioPlayer == null || _disposed) return;
    if (_isPlaying) {
      await _audioPlayer!.pause();
    } else {
      await _audioPlayer!.play();
    }
  }

  Future<void> _seekTo(Duration position) async {
    if (_audioPlayer == null || _disposed) return;

    // If already seeking, just update the target position
    if (_isSeeking) {
      setState(() => _position = position);
      return;
    }

    final clampedPosition = Duration(
      milliseconds: position.inMilliseconds.clamp(0, _duration.inMilliseconds),
    );

    setState(() {
      _isSeeking = true;
      _position = clampedPosition;
    });

    try {
      debugPrint('[AudioPlayer] Seeking to: $clampedPosition');

      // Remember if we were playing
      final wasPlaying = _isPlaying;

      // Perform the seek directly without pausing first
      // This provides better UX for streaming audio
      await _audioPlayer!.seek(clampedPosition);

      // Wait for the seek to complete and position to update
      // Listen for position updates to confirm seek completed
      int attempts = 0;
      const maxAttempts = 50; // 5 seconds max wait

      while (attempts < maxAttempts && mounted && !_disposed) {
        await Future.delayed(const Duration(milliseconds: 100));

        final currentPos = _audioPlayer!.position;
        final diff =
            (currentPos.inMilliseconds - clampedPosition.inMilliseconds).abs();

        // Consider seek complete if within 500ms of target
        if (diff < 500) {
          debugPrint('[AudioPlayer] Seek confirmed at: $currentPos');
          break;
        }

        attempts++;
      }

      // Resume playback if we were playing
      if (wasPlaying && mounted && !_disposed) {
        await _audioPlayer!.play();
      }

      debugPrint('[AudioPlayer] Seek completed to: $clampedPosition');
    } catch (e) {
      debugPrint('[AudioPlayer] Seek error: $e');
      if (mounted && !_disposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('跳转失败: ${e.toString().split('\n').first}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted && !_disposed) {
        // Always reset seeking state
        setState(() => _isSeeking = false);
      }
    }
  }

  void _seekForward() {
    final newPos = _position + const Duration(seconds: 10);
    _seekTo(newPos > _duration ? _duration : newPos);
  }

  void _seekBackward() {
    final newPos = _position - const Duration(seconds: 10);
    _seekTo(newPos < Duration.zero ? Duration.zero : newPos);
  }

  void _toggleLoop() {
    setState(() => _isLooping = !_isLooping);
    _audioPlayer?.setLoopMode(_isLooping ? LoopMode.one : LoopMode.off);
  }

  void _setVolume(double volume) {
    setState(() => _volume = volume);
    _audioPlayer?.setVolume(volume);
  }

  void _setSpeed(double speed) {
    setState(() => _speed = speed);
    _audioPlayer?.setSpeed(speed);
  }

  /// 将当前播放转移到全局 AudioPlayerService（后台播放），然后关闭页面。
  /// MiniAudioPlayer 会自动出现在底部导航栏上方，系统通知栏也会显示控制按钮。
  Future<void> _minimizeToBackground() async {
    final service = ref.read(audioPlayerServiceProvider.notifier);

    // 1. 用同一 URL & 文件名启动全局播放服务
    final url = _getStreamUrl();
    await service.play(url, widget.fileName);

    // 2. 恢复当前进度 & 音量/速度
    if (_position > Duration.zero) {
      await service.seekTo(_position);
    }
    if (_volume != 1.0) {
      await service.setVolume(_volume);
    }
    if (_speed != 1.0) {
      await service.setSpeed(_speed);
    }
    if (_isLooping) {
      service.toggleLoop();
    }

    // 3. 停止本地播放器（不触发 dispose 错误）
    _disposed = true;
    _visualizationTimer?.cancel();
    _cancelSubscriptions();
    await _audioPlayer?.stop();
    await _audioPlayer?.dispose();
    _audioPlayer = null;

    // 4. 关闭页面，显示底部导航栏
    if (mounted) {
      ref.read(bottomNavVisibleProvider.notifier).show();
      Navigator.pop(context);
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) ref.read(bottomNavVisibleProvider.notifier).show();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            // 最小化到后台按钮 — 转移播放到全局服务
            IconButton(
              icon: const Icon(Icons.picture_in_picture_alt_rounded),
              tooltip: '后台播放',
              onPressed: _minimizeToBackground,
            ),
            PopupMenuButton<double>(
              icon: const Icon(Icons.speed_rounded),
              tooltip: '播放速度',
              onSelected: _setSpeed,
              itemBuilder: (context) => [
                for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                  PopupMenuItem(
                    value: speed,
                    child: Row(
                      children: [
                        if (_speed == speed)
                          Icon(Icons.check,
                              color: colorScheme.primary, size: 18)
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 8),
                        Text('${speed}x'),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colorScheme.primary.withValues(alpha: 0.15),
                colorScheme.surface,
              ],
            ),
          ),
          child: SafeArea(
            child: _error != null
                ? _buildErrorState(colorScheme, textTheme)
                : !_isInitialized
                    ? _buildLoadingState(colorScheme, textTheme)
                    : _buildPlayerContent(colorScheme, textTheme),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary.withValues(alpha: 0.3),
                  colorScheme.secondary.withValues(alpha: 0.3),
                ],
              ),
            ),
            child: Center(
              child: CircularProgressIndicator(
                color: colorScheme.primary,
                strokeWidth: 3,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _isTranscoding ? '正在转码...' : '加载中...',
            style:
                textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              widget.fileName,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_retryCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              '重试 $_retryCount/$_maxRetries',
              style: textTheme.bodySmall?.copyWith(color: Colors.orange),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 72, color: colorScheme.error),
            const SizedBox(height: 24),
            Text('播放错误',
                style: textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_error ?? '未知错误',
                style: textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                _retryCount = 0;
                _initializePlayer();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerContent(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      children: [
        const Spacer(flex: 1),
        _buildAlbumArt(colorScheme),
        const SizedBox(height: 24),
        _buildAudioVisualizer(colorScheme),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Text(widget.fileName,
                  style: textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              if (_isBuffering || _isSeeking)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: colorScheme.primary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isSeeking
                          ? '跳转中...'
                          : (_isTranscoding ? '转码中...' : '缓冲中...'),
                      style: textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('正在播放',
                        style: textTheme.bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant)),
                    if (_isTranscoding) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${_audioCodec?.toUpperCase() ?? "DTS"} → AAC',
                          style: textTheme.labelSmall?.copyWith(
                              color: Colors.orange,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        _buildProgressBar(colorScheme, textTheme),
        const SizedBox(height: 24),
        _buildMainControls(colorScheme),
        const SizedBox(height: 16),
        _buildVolumeControl(colorScheme, textTheme),
        const Spacer(flex: 2),
      ],
    );
  }

  Widget _buildAlbumArt(ColorScheme colorScheme) {
    // RepaintBoundary isolates the continuous rotation from the rest of the tree.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _rotationController,
        builder: (context, child) => Transform.rotate(
          angle: _rotationController.value * 2 * math.pi,
          child: child,
        ),
        child: Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primary,
                colorScheme.secondary,
                colorScheme.tertiary
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.3),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Icon(Icons.music_note_rounded,
              size: 80, color: colorScheme.onPrimary),
        ),
      ),
    );
  }

  Widget _buildAudioVisualizer(ColorScheme colorScheme) {
    return RepaintBoundary(
        child: SizedBox(
      height: 50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          _audioLevels.length,
          (index) => Container(
            width: 5,
            height: 50 * _audioLevels[index],
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [colorScheme.primary, colorScheme.secondary],
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    ));
  }

  Widget _buildProgressBar(ColorScheme colorScheme, TextTheme textTheme) {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final buffered = _duration.inMilliseconds > 0
        ? (_bufferedPosition.inMilliseconds / _duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.surfaceContainerHighest,
              secondaryActiveTrackColor:
                  colorScheme.primary.withValues(alpha: 0.3),
              thumbColor: colorScheme.primary,
              overlayColor: colorScheme.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: progress,
              secondaryTrackValue: buffered,
              onChanged: (value) {
                final newPosition = Duration(
                  milliseconds: (value * _duration.inMilliseconds).round(),
                );
                setState(() => _position = newPosition);
              },
              onChangeEnd: (value) {
                final newPosition = Duration(
                  milliseconds: (value * _duration.inMilliseconds).round(),
                );
                _seekTo(newPosition);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_position),
                    style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace')),
                Text(_formatDuration(_duration),
                    style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainControls(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            iconSize: 28,
            icon: Icon(
              _isLooping ? Icons.repeat_one_rounded : Icons.repeat_rounded,
              color: _isLooping
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            onPressed: _toggleLoop,
          ),
          IconButton(
            iconSize: 40,
            icon: const Icon(Icons.replay_10_rounded),
            onPressed: _seekBackward,
          ),
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.secondary]),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.4),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: IconButton(
              iconSize: 32,
              icon: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: colorScheme.onPrimary,
              ),
              onPressed: _togglePlayPause,
            ),
          ),
          IconButton(
            iconSize: 40,
            icon: const Icon(Icons.forward_10_rounded),
            onPressed: _seekForward,
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }

  Widget _buildVolumeControl(ColorScheme colorScheme, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Row(
        children: [
          Icon(
            _volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            color: colorScheme.onSurfaceVariant,
            size: 20,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: colorScheme.primary,
                inactiveTrackColor: colorScheme.surfaceContainerHighest,
                thumbColor: colorScheme.primary,
              ),
              child: Slider(value: _volume, onChanged: _setVolume),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text('${(_volume * 100).round()}%',
                style: textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
