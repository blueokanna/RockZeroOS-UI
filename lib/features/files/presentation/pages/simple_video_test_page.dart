import 'dart:async';

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
  String _status = 'Preparing player...';
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
      _status = 'Initializing...';
      _details = 'URL: ${widget.videoUrl}';
      _isLoading = true;
      _error = null;
    });

    try {
      _log('Initialization started');
      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024,
        ),
      );

      _controller = VideoController(_player!);

      _player!.stream.playing.listen((playing) {
        if (mounted) {
          setState(() => _isPlaying = playing);
        }
      });

      _player!.stream.error.listen((error) {
        if (error.isNotEmpty && mounted) {
          _log('Playback error: $error');
        }
      });

      _log('Opening media...');
      await _player!.open(
        Media(
          widget.videoUrl,
          httpHeaders: widget.authToken != null
              ? {'Authorization': 'Bearer ${widget.authToken}'}
              : null,
        ),
        play: true,
      );

      _log('Playback started');
      setState(() {
        _status = 'Success';
        _isLoading = false;
      });
    } catch (e, stack) {
      _log('Error: $e');
      _log('Stack: $stack');
      setState(() {
        _status = 'Failed';
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
        title: const Text('Video playback test'),
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
                    'Error: $_error',
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
              child: Center(child: CircularProgressIndicator()),
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
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: () {
                      if (_isPlaying) {
                        _player?.pause();
                        _log('Paused');
                      } else {
                        _player?.play();
                        _log('Playing');
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop),
                    onPressed: () {
                      _player?.pause();
                      _player?.seek(Duration.zero);
                      _log('Stopped');
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
