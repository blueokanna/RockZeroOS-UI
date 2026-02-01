import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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
  VideoPlayerController? _controller;
  String _status = '准备初始化...';
  String _details = '';
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void dispose() {
    _controller?.dispose();
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

      final headers = <String, String>{};
      if (widget.authToken != null) {
        headers['Authorization'] = 'Bearer ${widget.authToken}';
        _log('添加认证头');
      }

      _log('创建VideoPlayerController...');
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        httpHeaders: headers,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
          webOptions: const VideoPlayerWebOptions(
            controls: VideoPlayerWebOptionsControls.disabled(),
          ),
        ),
      );

      _log('调用initialize()...');
      await _controller!.initialize().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _log('❌ 超时！');
          throw TimeoutException('初始化超时');
        },
      );

      _log('✅ initialize()完成');
      _log('isInitialized: ${_controller!.value.isInitialized}');
      _log('hasError: ${_controller!.value.hasError}');
      _log('size: ${_controller!.value.size}');
      _log('duration: ${_controller!.value.duration}');

      if (!_controller!.value.isInitialized) {
        throw Exception('视频未正确初始化');
      }

      if (_controller!.value.hasError) {
        throw Exception(_controller!.value.errorDescription ?? '未知错误');
      }

      _log('调用play()...');
      await _controller!.play();
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
              _controller?.dispose();
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

          // 视频播放器
          if (_controller != null && _controller!.value.isInitialized)
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
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

          // 详细日志
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

          // 控制按钮
          if (_controller != null && _controller!.value.isInitialized)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      _controller!.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_controller!.value.isPlaying) {
                          _controller!.pause();
                          _log('暂停');
                        } else {
                          _controller!.play();
                          _log('播放');
                        }
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop),
                    onPressed: () {
                      _controller!.pause();
                      _controller!.seekTo(Duration.zero);
                      _log('停止');
                      setState(() {});
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
