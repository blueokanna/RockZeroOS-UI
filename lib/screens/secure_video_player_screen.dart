import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/secure_hls_player.dart';

class SecureVideoPlayerScreen extends StatefulWidget {
  final String fileId;
  final String fileName;
  final String jwtToken;
  final String userId;
  final String password;
  final String baseUrl;

  const SecureVideoPlayerScreen({
    super.key,
    required this.fileId,
    required this.fileName,
    required this.jwtToken,
    required this.userId,
    required this.password,
    required this.baseUrl,
  });

  @override
  State<SecureVideoPlayerScreen> createState() =>
      _SecureVideoPlayerScreenState();
}

class _SecureVideoPlayerScreenState extends State<SecureVideoPlayerScreen> {
  SecureHlsPlayer? _securePlayer;
  Player? _player;
  VideoController? _controller;

  bool _isInitializing = true;
  bool _isBuffering = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _showControls = true;
  bool _isDisposed = false;
  bool _isVideoReady = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  bool _isPlaying = false;

  int _retryCount = 0;
  static const int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
    _initializePlayer();
  }

  void _enterFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky,
        overlays: []);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _initializePlayer() async {
    if (_isDisposed) return;

    try {
      setState(() {
        _isInitializing = true;
        _hasError = false;
        _errorMessage = null;
        _isVideoReady = false;
      });

      _securePlayer = SecureHlsPlayer(
        baseUrl: widget.baseUrl,
        jwtToken: widget.jwtToken,
      );

      await _securePlayer!.initializeSaeHandshake(
        widget.userId,
        widget.password,
        fileId: widget.fileId,
      );

      if (_isDisposed) return;

      final proxyUrl = await _securePlayer!.getProxyPlaylistUrl();

      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 64 * 1024 * 1024, // 64MB 缓冲
        ),
      );

      _controller = VideoController(_player!);

      _player!.stream.playing.listen((playing) {
        if (mounted && !_isDisposed) {
          setState(() => _isPlaying = playing);
        }
      });

      _player!.stream.position.listen((position) {
        if (mounted && !_isDisposed) {
          setState(() => _position = position);
        }
      });

      _player!.stream.duration.listen((duration) {
        if (mounted && !_isDisposed) {
          setState(() {
            _duration = duration;
            if (duration.inMilliseconds > 0) {
              _isVideoReady = true;
            }
          });
        }
      });

      _player!.stream.buffering.listen((buffering) {
        if (mounted && !_isDisposed) {
          setState(() => _isBuffering = buffering);
        }
      });

      _player!.stream.buffer.listen((buffer) {
        if (mounted && !_isDisposed) {
          setState(() => _bufferedPosition = buffer);
        }
      });

      _player!.stream.error.listen((error) {
        if (error.isNotEmpty && mounted && !_isDisposed) {
          debugPrint('[SecureVideoPlayer] Player error: $error');
          _handlePlaybackError(error);
        }
      });

      _player!.stream.completed.listen((completed) {
        if (completed && mounted && !_isDisposed) {
          debugPrint('[SecureVideoPlayer] Playback completed');
        }
      });

      await _player!.open(Media(proxyUrl), play: true);

      if (_isDisposed) {
        await _player?.dispose();
        return;
      }

      setState(() {
        _isInitializing = false;
        _retryCount = 0;
      });
    } catch (e, stack) {
      debugPrint('[SecureVideoPlayer] Error: $e');
      debugPrint('[SecureVideoPlayer] Stack: $stack');

      if (mounted && !_isDisposed) {
        setState(() {
          _isInitializing = false;
          _hasError = true;
          _errorMessage = _formatErrorMessage(e.toString());
        });
      }
    }
  }

  String _formatErrorMessage(String error) {
    if (error.contains('HTTP 500')) {
      return '服务器转码失败，请稍后重试';
    } else if (error.contains('HTTP 404')) {
      return '视频文件不存在';
    } else if (error.contains('timeout') || error.contains('Timeout')) {
      return '连接超时，请检查网络';
    } else if (error.contains('SAE') || error.contains('handshake')) {
      return '安全握手失败，请重新登录';
    } else if (error.contains('decrypt') || error.contains('Decrypt')) {
      return '解密失败，密钥可能不匹配';
    }
    return error;
  }

  void _handlePlaybackError(String error) {
    if (_retryCount < _maxRetries) {
      _retryCount++;
      debugPrint(
          '[SecureVideoPlayer] Retrying... (attempt $_retryCount/$_maxRetries)');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_isDisposed && _player != null) {
          _player!.play();
        }
      });
    } else {
      setState(() {
        _hasError = true;
        _errorMessage = _formatErrorMessage(error);
      });
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _player?.dispose();
    _securePlayer?.stop();
    _exitFullscreen();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_player == null || !_isVideoReady) return;
    if (_isPlaying) {
      _player!.pause();
    } else {
      _player!.play();
    }
  }

  void _seekTo(Duration position) {
    if (_player == null || !_isVideoReady) return;
    _player?.seek(position);
  }

  void _seekRelative(int seconds) {
    if (_player == null || !_isVideoReady) return;
    final newPosition = _position + Duration(seconds: seconds);
    final clampedPosition = Duration(
      milliseconds:
          newPosition.inMilliseconds.clamp(0, _duration.inMilliseconds),
    );
    _player?.seek(clampedPosition);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitializing) {
      return _buildInitializingView();
    }

    if (_hasError) {
      return _buildErrorView();
    }

    if (_controller == null) {
      return _buildInitializingView();
    }

    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: _controller!,
            controls: NoVideoControls,
          ),
          if (_isBuffering || !_isVideoReady) _buildBufferingIndicator(),
          if (_showControls && _isVideoReady) _buildControls(),
          if (_showControls) _buildTopBar(),
        ],
      ),
    );
  }

  Widget _buildInitializingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: Colors.green,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Establishing a secure connection...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'SAE handshake + AES-256-GCM encryption',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 32),
          TextButton.icon(
            onPressed: () {
              _exitFullscreen();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('取消'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBufferingIndicator() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isVideoReady ? '缓冲中...' : '加载中...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '播放失败',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage ?? '未知错误',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    _exitFullscreen();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('返回'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade400,
                    side: BorderSide(color: Colors.grey.shade600),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: () {
                    _retryCount = 0;
                    _initializePlayer();
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重试'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    _exitFullscreen();
                    Navigator.pop(context);
                  },
                ),
                Expanded(
                  child: Text(
                    widget.fileName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withAlpha(51),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withAlpha(102)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, color: Colors.green, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'SECURE',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.white),
                  onPressed: _showDownloadInfo,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    final bufferedProgress = _duration.inMilliseconds > 0
        ? _bufferedPosition.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10,
                        color: Colors.white, size: 36),
                    onPressed: () => _seekRelative(-10),
                  ),
                  const SizedBox(width: 32),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(26),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 48,
                      ),
                      onPressed: _togglePlayPause,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(width: 32),
                  IconButton(
                    icon: const Icon(Icons.forward_10,
                        color: Colors.white, size: 36),
                    onPressed: () => _seekRelative(10),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Stack(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: SliderComponentShape.noThumb,
                      activeTrackColor: Colors.white24,
                      inactiveTrackColor: Colors.white10,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: bufferedProgress.clamp(0.0, 1.0),
                      onChanged: null,
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: Colors.green,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: Colors.green,
                      overlayColor: Colors.green.withAlpha(51),
                    ),
                    child: Slider(
                      value: progress.clamp(0.0, 1.0),
                      onChanged: (value) {
                        final newPosition = Duration(
                          milliseconds:
                              (value * _duration.inMilliseconds).round(),
                        );
                        _seekTo(newPosition);
                      },
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_position),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      _formatDuration(_duration),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDownloadInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.green),
            SizedBox(width: 8),
            Text('安全播放', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('加密算法', 'AES-256-GCM'),
            _buildInfoRow('密钥交换', 'WPA3-SAE (Dragonfly)'),
            _buildInfoRow('认证方式', 'JWT Token'),
            _buildInfoRow('传输协议', 'HTTPS + TLS 1.3'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withAlpha(77)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This video uses end-to-end encryption and cannot be downloaded using standard tools.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade200,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: Colors.grey.shade400,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
