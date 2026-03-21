import 'dart:async';
<<<<<<< HEAD
import 'dart:io';
=======
>>>>>>> a3328d4715e908bd0bcd5c2c8bece0c2ab502f8f
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class SimpleVideoTestPage extends StatefulWidget {
  final String videoUrl;
  final String? authToken;

  const SimpleVideoTestPage({
    super.key,
    required this.videoUrl,
    this.authToken,
  });

  @override
  State<SimpleVideoTestPage> createState() => _SimpleVideoTestPageState();
}

class _SimpleVideoTestPageState extends State<SimpleVideoTestPage> {
  Player? _player;
  VideoController? _controller;
  String _status = '准备初始化...';
  String _details = '';
  bool _isLoading = true;
  String? _error;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    setState(() {
      _status = '正在初始化...';
      _details = 'URL: ${widget.videoUrl}';
      _isLoading = true;
      _error = null;
    });

    try {
      _log('开始初始化');
      _log('URL: ${widget.videoUrl}');

      _log('创建Player...');
      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024,
        ),
      );

<<<<<<< HEAD
      if (_player!.platform is NativePlayer) {
        final mpv = _player!.platform as NativePlayer;
        if (Platform.isAndroid) {
          await mpv.setProperty('hwdec', 'mediacodec-copy');
          await mpv.setProperty('hwdec-codecs', 'all');
          await mpv.setProperty('vd-lavc-software-fallback', 'no');
          await mpv.setProperty('vo', 'gpu');
          await mpv.setProperty('gpu-context', 'android');
        } else {
          await mpv.setProperty('hwdec', 'auto-safe');
        }
      }

=======
>>>>>>> a3328d4715e908bd0bcd5c2c8bece0c2ab502f8f
      _controller = VideoController(_player!);

      _player!.stream.playing.listen((playing) {
        if (mounted) {
          setState(() => _isPlaying = playing);
        }
      });

      _player!.stream.error.listen((error) {
        if (error.isNotEmpty && mounted) {
          _log('❌ 播放错误: $error');
        }
      });

      _log('打开媒体...');
      await _player!.open(
        Media(
          widget.videoUrl,
          httpHeaders: widget.authToken != null
              ? {'Authorization': 'Bearer ${widget.authToken}'}
              : null,
        ),
        play: true,
      );

      _log('✅ 播放开始');

      setState(() {
        _status = '✅ 成功！';
        _isLoading = false;
      });
    } catch (e, stack) {
      _log('❌ 错误: $e');
      _log('Stack: $stack');
      setState(() {
        _status = '❌ 失败';
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _log(String message) {
    debugPrint('[SimpleVideoTest] $message');
    setState(() {
      _details += '\n$message';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频播放测试'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _player?.dispose();
              _player = null;
              _controller = null;
              _initVideo();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _error != null
                ? Colors.red.shade100
                : _isLoading
                    ? Colors.orange.shade100
                    : Colors.green.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _status,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '错误: $_error',
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
          if (_controller != null && !_isLoading && _error == null)
            Expanded(
              child: Video(
                controller: _controller!,
                controls: AdaptiveVideoControls,
              ),
            )
          else if (_isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else
            const Expanded(
              child: Center(
                child: Icon(Icons.error, size: 64, color: Colors.red),
              ),
            ),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade200,
              child: SingleChildScrollView(
                child: SelectableText(
                  _details,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          if (_controller != null && !_isLoading && _error == null)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: () {
                      if (_isPlaying) {
                        _player?.pause();
                        _log('暂停');
                      } else {
                        _player?.play();
                        _log('播放');
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop),
                    onPressed: () {
                      _player?.pause();
                      _player?.seek(Duration.zero);
                      _log('停止');
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
