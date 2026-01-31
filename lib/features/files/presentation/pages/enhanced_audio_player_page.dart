import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
    _visualizationTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (timer) {
        if (!mounted || _disposed) return;
        bool needsUpdate = false;
        for (int i = 0; i < _audioLevels.length; i++) {
          final oldValue = _audioLevels[i];
          if (_isPlaying && !_isBuffering) {
            final target = math.Random().nextDouble() * 0.7 + 0.3;
            _audioLevels[i] = _audioLevels[i] * 0.5 + target * 0.5;
          } else {
            _audioLevels[i] = (_audioLevels[i] * 0.9).clamp(0.1, 1.0);
          }
          if ((oldValue - _audioLevels[i]).abs() > 0.02) needsUpdate = true;
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
    const storage = FlutterSecureStorage();
    _authToken = await storage.read(key: 'access_token');
    await _fetchMediaInfo();
    await _initializePlayer();
  }

  Future<void> _fetchMediaInfo() async {
    try {
      final uri = Uri.parse(widget.mediaUrl);
      final pathSegments = uri.pathSegments;
      String infoPath = '';
      bool foundPlay = false;
      for (final segment in pathSegments) {
        if (foundPlay) infoPath += '/$segment';
        if (segment == 'play' || segment == 'stream') foundPlay = true;
      }
      if (infoPath.isEmpty) {
        infoPath = uri.path.replaceFirst(
          RegExp(r'/api/v1/(streaming|filemanager)/(play|stream)/'),
          '/',
        );
      }
      final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';
      final infoUrl = '$baseUrl/api/v1/streaming/info$infoPath';
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

      // Use LockCachingAudioSource for better seek support
      final audioSource = LockCachingAudioSource(
        Uri.parse(streamUrl),
        headers: headers,
      );

      await _audioPlayer!.setAudioSource(audioSource).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Audio initialization timed out');
        },
      );

      _setupListeners();
      _startVisualization();
      _retryCount = 0;

      if (mounted && !_disposed) {
        setState(() => _isInitialized = true);
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
      if (mounted && !_disposed && !_isSeeking) {
        setState(() => _position = position);
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
    if (_audioPlayer == null || _isSeeking || _disposed) return;

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

      // Pause before seeking for smoother experience
      if (wasPlaying) {
        await _audioPlayer!.pause();
      }

      // Perform the seek
      await _audioPlayer!.seek(clampedPosition);

      // Wait for buffering to complete
      await Future.delayed(const Duration(milliseconds: 100));

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
    return AnimatedBuilder(
      animation: _rotationController,
      builder: (context, child) => Transform.rotate(
        angle: _rotationController.value * 2 * math.pi,
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
    return SizedBox(
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
    );
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
