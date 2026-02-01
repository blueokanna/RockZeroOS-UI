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
  bool _isLoading = true;
  String? _error;
  bool _showControls = true;
  bool _isDisposed = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

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
    try {
      setState(() {
        _isLoading = true;
        _error = null;
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

      final proxyUrl = await _securePlayer!.getProxyPlaylistUrl();

      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024,
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
          setState(() => _duration = duration);
        }
      });

      _player!.stream.error.listen((error) {
        if (error.isNotEmpty && mounted && !_isDisposed) {
          debugPrint('[SecureVideoPlayer] Player error: $error');
        }
      });

      await _player!.open(Media(proxyUrl), play: true);

      if (_isDisposed) {
        await _player?.dispose();
        return;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e, stack) {
      debugPrint('[SecureVideoPlayer] Error: $e');
      debugPrint('[SecureVideoPlayer] Stack: $stack');

      setState(() {
        _isLoading = false;
        _error = e.toString();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
    if (_player == null) return;
    if (_isPlaying) {
      _player!.pause();
    } else {
      _player!.play();
    }
  }

  void _seekTo(Duration position) {
    _player?.seek(position);
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
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              '正在建立安全连接...',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              '使用 WPA3-SAE 握手 + AES-256-GCM 加密',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                '播放器初始化失败',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                ),
                onPressed: _initializePlayer,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  _exitFullscreen();
                  Navigator.pop(context);
                },
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    if (_controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.green),
      );
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
          if (_showControls) _buildControls(),
          if (_showControls) _buildSecurityIndicator(),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
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
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                  activeTrackColor: Colors.blue,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.blue,
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
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    onPressed: _togglePlayPause,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.info_outline, color: Colors.white),
                    onPressed: _showSecurityInfo,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityIndicator() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 8,
      right: 8,
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
              style: const TextStyle(color: Colors.white, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(77),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withAlpha(128)),
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
        ],
      ),
    );
  }

  void _showSecurityInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.green),
            SizedBox(width: 8),
            Text('安全连接信息'),
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
            Text(
              '此视频使用端到端加密，无法使用标准工具下载。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
