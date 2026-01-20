import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/secure_hls_player.dart';

/// 安全视频播放器界面
class SecureVideoPlayerScreen extends StatefulWidget {
  final String fileId;
  final String fileName;
  final String jwtToken;
  final String userId;
  final String password;

  const SecureVideoPlayerScreen({
    Key? key,
    required this.fileId,
    required this.fileName,
    required this.jwtToken,
    required this.userId,
    required this.password,
  }) : super(key: key);

  @override
  State<SecureVideoPlayerScreen> createState() =>
      _SecureVideoPlayerScreenState();
}

class _SecureVideoPlayerScreenState extends State<SecureVideoPlayerScreen> {
  SecureHlsPlayer? _player;
  VideoPlayerController? _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // 1. 创建安全播放器
      _player = SecureHlsPlayer(
        baseUrl: 'http://your-server.com', // 替换为实际服务器地址
        jwtToken: widget.jwtToken,
      );

      // 2. 初始化 SAE 握手
      await _player!.initializeSaeHandshake(
        widget.userId,
        widget.password,
        widget.fileId,
      );

      // 3. 开始播放
      _controller = await _player!.play();

      setState(() {
        _isLoading = false;
      });

      // 4. 自动播放
      _controller!.play();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('播放失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _player?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              _showSecurityInfo();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('正在建立安全连接...'),
            const SizedBox(height: 8),
            const Text(
              '使用 WPA3-SAE 握手 + ZKP 证明',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('播放失败', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializePlayer,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // 视频播放器
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),

        // 控制栏
        _buildControls(),

        // 安全指示器
        _buildSecurityIndicator(),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          // 播放/暂停按钮
          IconButton(
            icon: Icon(
              _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _controller!.value.isPlaying
                    ? _controller!.pause()
                    : _controller!.play();
              });
            },
          ),

          // 进度条
          Expanded(
            child: VideoProgressIndicator(
              _controller!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.blue,
                bufferedColor: Colors.grey,
                backgroundColor: Colors.white24,
              ),
            ),
          ),

          // 时间显示
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${_formatDuration(_controller!.value.position)} / ${_formatDuration(_controller!.value.duration)}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),

          // 全屏按钮
          IconButton(
            icon: const Icon(Icons.fullscreen, color: Colors.white),
            onPressed: () {
              // TODO: 实现全屏
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityIndicator() {
    return Container(
      color: Colors.green.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.lock, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          const Text(
            '安全连接',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          const Spacer(),
          TextButton(
            onPressed: _showSecurityInfo,
            child: const Text(
              '查看详情',
              style: TextStyle(color: Colors.white, fontSize: 12),
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
            _buildInfoRow('加密协议', 'AES-256-GCM'),
            _buildInfoRow('密钥协商', 'WPA3-SAE (Dragonfly)'),
            _buildInfoRow('身份验证', '零知识证明 (ZKP)'),
            _buildInfoRow('传输安全', 'HTTPS + TLS 1.3'),
            const SizedBox(height: 16),
            const Text(
              '此视频使用端到端加密传输，无法通过标准工具下载。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
}
