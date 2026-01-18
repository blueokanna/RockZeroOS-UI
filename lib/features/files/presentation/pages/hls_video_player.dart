import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/widgets/shell_scaffold.dart';

/// 音轨信息
class AudioTrackInfo {
  final int index;
  final String language;
  final String title;
  final String codec;

  AudioTrackInfo({
    required this.index,
    required this.language,
    required this.title,
    required this.codec,
  });

  factory AudioTrackInfo.fromJson(Map<String, dynamic> json) {
    return AudioTrackInfo(
      index: json['index'] as int,
      language: json['language'] as String? ?? 'und',
      title: json['title'] as String? ?? '音轨 ${json['index']}',
      codec: json['codec'] as String? ?? 'unknown',
    );
  }

  String get displayName {
    final lang = _languageNames[language] ?? language;
    if (title.isNotEmpty && title != '音轨 $index') {
      return '$title ($lang)';
    }
    return '$lang - ${codec.toUpperCase()}';
  }

  static const _languageNames = {
    'und': '未知',
    'chi': '中文',
    'zho': '中文',
    'eng': '英语',
    'jpn': '日语',
    'kor': '韩语',
    'fra': '法语',
    'deu': '德语',
    'spa': '西班牙语',
    'rus': '俄语',
  };
}

class HlsVideoPlayer extends ConsumerStatefulWidget {
  final String? filePath;
  final String? fileId;
  final String fileName;
  final String baseUrl;

  const HlsVideoPlayer({
    super.key,
    this.filePath,
    this.fileId,
    required this.fileName,
    required this.baseUrl,
  }) : assert(filePath != null || fileId != null,
            'Either filePath or fileId is required');

  @override
  ConsumerState<HlsVideoPlayer> createState() => _HlsVideoPlayerState();
}

class _HlsVideoPlayerState extends ConsumerState<HlsVideoPlayer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  bool _isLoading = true;
  String? _error;
  String? _authToken;
  String? _hlsSessionId;

  List<AudioTrackInfo> _audioTracks = [];
  int _currentAudioTrack = 0;
  String _currentQuality = 'auto';
  final List<String> _availableQualities = [
    'auto',
    '1080p',
    '720p',
    '480p',
    '360p'
  ];

  bool _isDownloading = false;
  double _downloadProgress = 0;

  bool _isLooping = false;

  late Color _primaryColor;

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
    WakelockPlus.enable();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _primaryColor = Theme.of(context).colorScheme.primary;
    if (_videoController == null && _error == null) {
      _initPlayer();
    }
  }

  Future<void> _initPlayer({String? quality, int? audioTrack}) async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      const storage = FlutterSecureStorage();
      _authToken = await storage.read(key: 'access_token');

      if (_authToken == null || _authToken!.isEmpty) {
        setState(() {
          _error = '未登录，请先登录';
          _isLoading = false;
        });
        return;
      }

      final startUrl = '${widget.baseUrl}/api/v1/media/hls/start';
      debugPrint('[HlsPlayer] Starting HLS session: $startUrl');

      final requestBody = <String, dynamic>{};
      if (widget.filePath != null) {
        requestBody['file_path'] = widget.filePath;
      } else if (widget.fileId != null) {
        requestBody['file_id'] = widget.fileId;
      }

      if (quality != null && quality != 'auto') {
        requestBody['quality'] = quality;
      }
      if (audioTrack != null) {
        requestBody['audio_track'] = audioTrack;
      }

      final response = await http.post(
        Uri.parse(startUrl),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        String errorMessage = '启动 HLS 流失败';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map) {
            errorMessage = errorData['message']?.toString() ??
                errorData['error']?.toString() ??
                response.body;
          }
        } catch (_) {
          errorMessage = response.body;
        }
        debugPrint('[HlsPlayer] Error: $errorMessage');
        throw Exception(errorMessage);
      }

      final data = jsonDecode(response.body);
      _hlsSessionId = data['session_id'] as String;
      final playlistUrl = '${widget.baseUrl}${data['playlist_url']}';

      if (data['audio_tracks'] != null) {
        _audioTracks = (data['audio_tracks'] as List)
            .map((e) => AudioTrackInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      debugPrint('[HlsPlayer] HLS session created: $_hlsSessionId');
      debugPrint('[HlsPlayer] Playlist URL: $playlistUrl');
      debugPrint('[HlsPlayer] Audio tracks: ${_audioTracks.length}');

      await Future.delayed(const Duration(seconds: 2));

      _chewieController?.dispose();
      _videoController?.dispose();

      debugPrint('[HlsPlayer] Creating video controller for: $playlistUrl');

      // 创建简单可靠的HTTP头
      final headers = <String, String>{
        'Accept': '*/*',
      };

      if (_authToken != null && _authToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_authToken';
      }

      debugPrint('[HlsPlayer] Headers: ${headers.keys.join(", ")}');

      // 添加更详细的错误处理和超时设置
      try {
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(playlistUrl),
          httpHeaders: headers,
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: false,
            allowBackgroundPlayback: false,
            webOptions: const VideoPlayerWebOptions(
              allowContextMenu: false,
              allowRemotePlayback: true,
              controls: VideoPlayerWebOptionsControls.disabled(),
            ),
          ),
        );

        debugPrint('[HlsPlayer] Initializing video controller...');
        await _videoController!.initialize().timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            debugPrint('[HlsPlayer] ❌ Initialization timeout');
            throw TimeoutException('视频加载超时，请检查网络连接');
          },
        );

        debugPrint('[HlsPlayer] ✅ Video controller initialized');
        debugPrint(
            '[HlsPlayer] Is initialized: ${_videoController!.value.isInitialized}');
        debugPrint(
            '[HlsPlayer] Has error: ${_videoController!.value.hasError}');
        debugPrint('[HlsPlayer] Size: ${_videoController!.value.size}');
        debugPrint('[HlsPlayer] Duration: ${_videoController!.value.duration}');

        if (!_videoController!.value.isInitialized) {
          throw Exception('Video failed to initialize');
        }

        if (_videoController!.value.hasError) {
          throw Exception(
              _videoController!.value.errorDescription ?? 'Unknown error');
        }
      } catch (e) {
        debugPrint('[HlsPlayer] ❌ Initialize error: $e');
        rethrow;
      }

      _videoController!.setLooping(_isLooping);

      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        looping: _isLooping,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        showControlsOnInitialize: true,
        placeholder: Container(color: Colors.black),
        autoInitialize: true,
        // 自定义控制栏
        additionalOptions: (context) => [
          // 音轨选择
          if (_audioTracks.length > 1)
            OptionItem(
              onTap: (ctx) => _showAudioTrackDialog(ctx),
              iconData: Icons.audiotrack,
              title: '音轨',
            ),
          // 清晰度选择
          OptionItem(
            onTap: (ctx) => _showQualityDialog(ctx),
            iconData: Icons.high_quality,
            title: '清晰度',
          ),
          // 循环播放
          OptionItem(
            onTap: (_) => _toggleLooping(),
            iconData: _isLooping ? Icons.repeat_one : Icons.repeat,
            title: _isLooping ? '循环: 开' : '循环: 关',
          ),
        ],
        errorBuilder: (_, errorMessage) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, color: Colors.white54, size: 48),
                const SizedBox(height: 16),
                Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          );
        },
        materialProgressColors: ChewieProgressColors(
          playedColor: _primaryColor,
          handleColor: _primaryColor,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentQuality = quality ?? 'auto';
          _currentAudioTrack = audioTrack ?? 0;
        });
      }

      debugPrint('[HlsPlayer] Player initialized successfully');
    } catch (e, stack) {
      debugPrint('[HlsPlayer] Error: $e');
      debugPrint('[HlsPlayer] Stack: $stack');
      if (mounted) {
        String errorMessage = '播放失败: $e';
        final errorStr = e.toString().toLowerCase();

        // 提供更友好的错误消息
        if (errorStr.contains('source error') || errorStr.contains('x0.i')) {
          errorMessage = 'HLS视频源加载失败\n'
              '可能原因：\n'
              '1. 视频转码失败\n'
              '2. 网络连接中断\n'
              '3. 服务器FFmpeg配置问题\n'
              '4. 视频格式不支持\n\n'
              '建议：检查服务器日志或尝试其他视频';
        } else if (errorStr.contains('timeout')) {
          errorMessage = 'HLS流加载超时\n请检查网络连接和服务器状态';
        } else if (errorStr.contains('network') ||
            errorStr.contains('connection')) {
          errorMessage = '网络连接失败\n无法连接到HLS流服务器';
        } else if (errorStr.contains('404') || errorStr.contains('not found')) {
          errorMessage = 'HLS流不存在\n可能会话已过期，请重试';
        }

        setState(() {
          _error = errorMessage;
          _isLoading = false;
        });
      }
    }
  }

  void _showAudioTrackDialog(BuildContext ctx) {
    Navigator.of(ctx).pop(); // 关闭 Chewie 菜单
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择音轨',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(color: Colors.white24),
            ...List.generate(_audioTracks.length, (index) {
              final track = _audioTracks[index];
              final isSelected = index == _currentAudioTrack;
              return ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: isSelected ? _primaryColor : Colors.white54,
                ),
                title: Text(
                  track.displayName,
                  style: TextStyle(
                    color: isSelected ? _primaryColor : Colors.white,
                  ),
                ),
                subtitle: Text(
                  track.codec.toUpperCase(),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (index != _currentAudioTrack) {
                    _switchAudioTrack(index);
                  }
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showQualityDialog(BuildContext ctx) {
    Navigator.of(ctx).pop(); // 关闭 Chewie 菜单
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择清晰度',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(color: Colors.white24),
            ...List.generate(_availableQualities.length, (index) {
              final quality = _availableQualities[index];
              final isSelected = quality == _currentQuality;
              return ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: isSelected ? _primaryColor : Colors.white54,
                ),
                title: Text(
                  quality == 'auto' ? '自动' : quality,
                  style: TextStyle(
                    color: isSelected ? _primaryColor : Colors.white,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (quality != _currentQuality) {
                    _switchQuality(quality);
                  }
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _switchAudioTrack(int trackIndex) async {
    // 保存当前播放位置
    final position = _videoController?.value.position;

    // 停止当前会话并重新开始
    await _cleanupHlsSession();
    await _initPlayer(quality: _currentQuality, audioTrack: trackIndex);

    // 恢复播放位置
    if (position != null && _videoController != null) {
      await Future.delayed(const Duration(milliseconds: 500));
      _videoController!.seekTo(position);
    }
  }

  Future<void> _switchQuality(String quality) async {
    // 保存当前播放位置
    final position = _videoController?.value.position;

    // 停止当前会话并重新开始
    await _cleanupHlsSession();
    await _initPlayer(quality: quality, audioTrack: _currentAudioTrack);

    // 恢复播放位置
    if (position != null && _videoController != null) {
      await Future.delayed(const Duration(milliseconds: 500));
      _videoController!.seekTo(position);
    }
  }

  void _toggleLooping() {
    setState(() {
      _isLooping = !_isLooping;
    });
    _videoController?.setLooping(_isLooping);
    _chewieController?.setLooping(_isLooping);
  }

  Future<void> _retry() async {
    await _cleanupHlsSession();
    _chewieController?.dispose();
    _videoController?.dispose();
    _chewieController = null;
    _videoController = null;
    await _initPlayer();
  }

  Future<void> _cleanupHlsSession() async {
    if (_hlsSessionId != null && _authToken != null) {
      try {
        await http.post(
          Uri.parse('${widget.baseUrl}/api/v1/media/hls/$_hlsSessionId/stop'),
          headers: {'Authorization': 'Bearer $_authToken'},
        );
        debugPrint('[HlsPlayer] HLS session stopped: $_hlsSessionId');
      } catch (e) {
        debugPrint('[HlsPlayer] Failed to stop HLS session: $e');
      }
      _hlsSessionId = null;
    }
  }

  @override
  void dispose() {
    _cleanupHlsSession();
    _chewieController?.dispose();
    _videoController?.dispose();
    _exitFullscreen();
    WakelockPlus.disable();
    super.dispose();
  }

  void _enterFullscreen() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(bottomNavVisibleProvider.notifier).hide();
      }
    });
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    ref.read(bottomNavVisibleProvider.notifier).show();
  }

  Future<void> _downloadFile() async {
    if (_isDownloading) return;

    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.storage.request();
      if (!status.isGranted && Platform.isAndroid) {
        final ms = await Permission.manageExternalStorage.request();
        if (!ms.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('需要存储权限')));
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
        final docDir = await getApplicationDocumentsDirectory();
        downloadDir = Directory('${docDir.path}/RockZeroDownload');
      } else {
        final dlDir = await getDownloadsDirectory();
        if (dlDir != null) {
          downloadDir = Directory('${dlDir.path}/RockZeroDownload');
        }
      }

      if (downloadDir == null) {
        throw Exception('无法获取下载目录');
      }
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      // 根据 filePath 或 fileId 构建下载 URL
      final String downloadUrl;
      if (widget.filePath != null) {
        downloadUrl =
            '${widget.baseUrl}/api/v1/filemanager/download?path=${Uri.encodeComponent(widget.filePath!)}';
      } else {
        downloadUrl =
            '${widget.baseUrl}/api/v1/files/${widget.fileId}/download';
      }

      final file = File('${downloadDir.path}/${widget.fileName}');
      final request = http.Request('GET', Uri.parse(downloadUrl));
      if (_authToken != null) {
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
              content: Text('已下载到 ${downloadDir.path}'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _exitFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(
            widget.fileName,
            style: const TextStyle(fontSize: 16),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            // 当前清晰度指示
            if (!_isLoading && _error == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _currentQuality == 'auto' ? 'AUTO' : _currentQuality,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _downloadFile,
              tooltip: '下载原文件',
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 播放器
            if (_chewieController != null && !_isLoading && _error == null)
              Chewie(controller: _chewieController!),

            // 加载中
            if (_isLoading) _buildLoading(),

            // 错误
            if (_error != null && !_isLoading) _buildError(),

            // 下载进度
            if (_isDownloading) _buildDownloadProgress(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text('正在准备视频流...', style: TextStyle(color: Colors.white)),
          SizedBox(height: 8),
          Text(
            '服务器正在转码视频，请稍候\n（支持 mkv/ts/avi 等所有格式）',
            style: TextStyle(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            Text(_error!,
                style: const TextStyle(color: Colors.white54),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _retry,
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

  Widget _buildDownloadProgress() {
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
                const Icon(Icons.download, color: Colors.white),
                const SizedBox(width: 12),
                const Expanded(
                    child:
                        Text('下载中...', style: TextStyle(color: Colors.white))),
                Text('${(_downloadProgress * 100).toInt()}%',
                    style: const TextStyle(color: Colors.white)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: _downloadProgress, backgroundColor: Colors.white24),
          ],
        ),
      ),
    );
  }
}
