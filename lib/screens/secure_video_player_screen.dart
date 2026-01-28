import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/secure_hls_player.dart';

/// Secure video player screen
///
/// Uses WPA3-SAE handshake + AES-256-GCM encryption
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

      // 1. Create secure player
      _player = SecureHlsPlayer(
        baseUrl: widget.baseUrl,
        jwtToken: widget.jwtToken,
      );

      // 2. Initialize SAE handshake
      await _player!.initializeSaeHandshake(
        widget.userId,
        widget.password,
        widget.fileId,
      );

      // 3. Start playback
      _controller = await _player!.play();

      setState(() {
        _isLoading = false;
      });

      // 4. Auto play
      _controller!.play();
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
            content: Text('Playback failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
            const Text('Establishing secure connection...'),
            const SizedBox(height: 8),
            const Text(
              'Using WPA3-SAE handshake + AES-256-GCM encryption',
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
            Text('Playback failed',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializePlayer,
              child: const Text('Retry'),
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
        // Video player
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),

        // Control bar
        _buildControls(),

        // Security indicator
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
          // Play/pause button
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

          // Progress bar
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

          // Time display
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${_formatDuration(_controller!.value.position)} / ${_formatDuration(_controller!.value.duration)}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),

          // Fullscreen button
          IconButton(
            icon: const Icon(Icons.fullscreen, color: Colors.white),
            onPressed: () {
              // TODO: Implement fullscreen
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
            'Secure Connection',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          const Spacer(),
          TextButton(
            onPressed: _showSecurityInfo,
            child: const Text(
              'View Details',
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
            Text('Security Connection Info'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Encryption', 'AES-256-GCM'),
            _buildInfoRow('Key Exchange', 'WPA3-SAE (Dragonfly)'),
            _buildInfoRow('Authentication', 'JWT Token'),
            _buildInfoRow('Transport', 'HTTPS + TLS 1.3'),
            const SizedBox(height: 16),
            const Text(
              'This video uses end-to-end encryption and cannot be downloaded with standard tools.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
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
