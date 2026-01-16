import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
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

class AudioTrackInfo {
  final int index;
  final String codec;
  final int channels;
  final int sampleRate;
  final int? bitrate;
  final String? language;
  final String? title;

  AudioTrackInfo({
    required this.index,
    required this.codec,
    required this.channels,
    required this.sampleRate,
    this.bitrate,
    this.language,
    this.title,
  });

  factory AudioTrackInfo.fromJson(Map<String, dynamic> json) {
    return AudioTrackInfo(
      index: json['index'] ?? 0,
      codec: json['codec'] ?? 'unknown',
      channels: json['channels'] ?? 2,
      sampleRate: json['sample_rate'] ?? 44100,
      bitrate: json['bitrate'],
      language: json['language'],
      title: json['title'],
    );
  }

  String get displayName {
    final parts = <String>[];
    if (title != null && title!.isNotEmpty) {
      parts.add(title!);
    }
    if (language != null && language!.isNotEmpty) {
      parts.add('[$language]');
    }
    parts.add(codec.toUpperCase());
    parts.add('${channels}ch');
    return parts.join(' ');
  }
}

/// 字幕轨道信息
class SubtitleTrackInfo {
  final int index;
  final String? language;
  final String? title;
  final String codec;
  final bool isExternal;
  final String? externalPath;

  SubtitleTrackInfo({
    required this.index,
    this.language,
    this.title,
    required this.codec,
    this.isExternal = false,
    this.externalPath,
  });

  factory SubtitleTrackInfo.fromJson(Map<String, dynamic> json) {
    return SubtitleTrackInfo(
      index: json['index'] ?? 0,
      language: json['language'],
      title: json['title'],
      codec: json['codec'] ?? 'unknown',
      isExternal: json['is_external'] ?? false,
      externalPath: json['external_path'],
    );
  }

  String get displayName {
    final parts = <String>[];
    if (title != null && title!.isNotEmpty) {
      parts.add(title!);
    } else if (language != null && language!.isNotEmpty) {
      parts.add(language!);
    } else {
      parts.add('字幕 ${index + 1}');
    }
    if (isExternal) {
      parts.add('[外挂]');
    }
    return parts.join(' ');
  }
}

/// 媒体流信息
class MediaStreamInfo {
  final String filename;
  final String contentType;
  final int size;
  final double? duration;
  final int? width;
  final int? height;
  final String? videoCodec;
  final String? audioCodec;
  final int? bitrate;
  final bool supportsRange;
  final bool needsAudioTranscode;
  final String? transcodeUrl;
  final bool hasAudio;
  final List<AudioTrackInfo> audioTracks;
  final List<SubtitleTrackInfo> subtitleTracks;
  final double? frameRate;
  final String? containerFormat;

  MediaStreamInfo({
    required this.filename,
    required this.contentType,
    required this.size,
    this.duration,
    this.width,
    this.height,
    this.videoCodec,
    this.audioCodec,
    this.bitrate,
    this.supportsRange = true,
    this.needsAudioTranscode = false,
    this.transcodeUrl,
    this.hasAudio = true,
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.frameRate,
    this.containerFormat,
  });

  factory MediaStreamInfo.fromJson(Map<String, dynamic> json) {
    return MediaStreamInfo(
      filename: json['filename'] ?? '',
      contentType: json['content_type'] ?? '',
      size: json['size'] ?? 0,
      duration: json['duration']?.toDouble(),
      width: json['width'],
      height: json['height'],
      videoCodec: json['video_codec'],
      audioCodec: json['audio_codec'],
      bitrate: json['bitrate'],
      supportsRange: json['supports_range'] ?? true,
      needsAudioTranscode: json['needs_audio_transcode'] ?? false,
      transcodeUrl: json['transcode_url'],
      hasAudio: json['has_audio'] ?? true,
      audioTracks: (json['audio_tracks'] as List<dynamic>?)
              ?.map((e) => AudioTrackInfo.fromJson(e))
              .toList() ??
          [],
      subtitleTracks: (json['subtitle_tracks'] as List<dynamic>?)
              ?.map((e) => SubtitleTrackInfo.fromJson(e))
              .toList() ??
          [],
      frameRate: json['frame_rate']?.toDouble(),
      containerFormat: json['container_format'],
    );
  }

  String get codecInfo {
    final parts = <String>[];
    if (videoCodec != null) {
      parts.add(videoCodec!.toUpperCase());
    }
    if (audioCodec != null) {
      parts.add(audioCodec!.toUpperCase());
    }
    return parts.join(' / ');
  }

  String get resolutionInfo {
    if (width != null && height != null) {
      return '${width}x$height';
    }
    return '';
  }
}

/// 专业级媒体播放器 - 支持全格式、多轨道、字幕、流媒体协议
class EnhancedMediaPlayerPage extends ConsumerStatefulWidget {
  final String mediaUrl;
  final String fileName;
  final bool isVideo;
  final String? subtitlePath; // 外挂字幕路径

  const EnhancedMediaPlayerPage({
    super.key,
    required this.mediaUrl,
    required this.fileName,
    required this.isVideo,
    this.subtitlePath,
  });

  @override
  ConsumerState<EnhancedMediaPlayerPage> createState() =>
      _EnhancedMediaPlayerPageState();
}

class _EnhancedMediaPlayerPageState
    extends ConsumerState<EnhancedMediaPlayerPage> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  bool _isLoading = true;
  String? _error;
  String? _authToken;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  bool _isLooping = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  MediaStreamInfo? _mediaInfo;
  bool _isTranscoding = false;
  String? _originalAudioCodec;
  bool _isInitializing = false;
  bool _disposed = false;

  // 播放状态监控
  Timer? _playbackMonitor;
  DateTime? _lastPositionUpdate;
  Duration _lastPosition = Duration.zero;
  int _stallCount = 0;

  // 多轨道支持
  int _selectedAudioTrack = 0;
  int _selectedSubtitleTrack = -1; // -1 表示关闭字幕
  final List<SubtitleTrackInfo> _externalSubtitles = [];

  // 播放速度
  double _playbackSpeed = 1.0;
  static const List<double> _playbackSpeeds = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0
  ];

  // 流媒体协议检测
  bool _isStreamingProtocol = false;
  String? _streamingProtocol;

  @override
  void initState() {
    super.initState();
    _detectStreamingProtocol();
    _enterFullScreen();
    _loadTokenAndInitialize();
    WakelockPlus.enable();
  }

  void _detectStreamingProtocol() {
    final url = widget.mediaUrl.toLowerCase();
    if (url.startsWith('rtsp://')) {
      _isStreamingProtocol = true;
      _streamingProtocol = 'RTSP';
    } else if (url.startsWith('rtp://')) {
      _isStreamingProtocol = true;
      _streamingProtocol = 'RTP';
    } else if (url.startsWith('udp://')) {
      _isStreamingProtocol = true;
      _streamingProtocol = 'UDP';
    } else if (url.contains('.m3u8')) {
      _isStreamingProtocol = true;
      _streamingProtocol = 'HLS';
    } else if (url.contains('.mpd')) {
      _isStreamingProtocol = true;
      _streamingProtocol = 'DASH';
    }
  }

  void _enterFullScreen() {
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

  void _exitFullScreen() {
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
    WakelockPlus.disable();
  }

  @override
  void dispose() {
    _disposed = true;
    _playbackMonitor?.cancel();
    _chewieController?.dispose();
    _videoController?.dispose();
    _exitFullScreen();
    super.dispose();
  }

  Future<void> _loadTokenAndInitialize() async {
    const storage = FlutterSecureStorage();
    _authToken = await storage.read(key: 'access_token');
    await _fetchMediaInfo();
    await _scanExternalSubtitles();
    await _initializePlayer();
  }

  Future<void> _fetchMediaInfo() async {
    try {
      final uri = Uri.parse(widget.mediaUrl);
      String infoPath = '';
      bool foundPlay = false;
      for (final segment in uri.pathSegments) {
        if (foundPlay) {
          infoPath += '/$segment';
        }
        if (segment == 'play' || segment == 'stream') {
          foundPlay = true;
        }
      }
      if (infoPath.isEmpty) {
        infoPath = uri.path.replaceFirst(
          RegExp(r'/api/v1/(streaming|filemanager)/(play|stream)/'),
          '/',
        );
      }
      final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';
      final infoUrl = '$baseUrl/api/v1/streaming/info$infoPath';
      debugPrint('[MediaPlayer] Fetching media info: $infoUrl');

      final response = await http
          .get(
            Uri.parse(infoUrl),
            headers: _authToken != null
                ? {'Authorization': 'Bearer $_authToken'}
                : {},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        _mediaInfo = MediaStreamInfo.fromJson(json);
        _originalAudioCodec = _mediaInfo?.audioCodec;
        debugPrint(
          '[MediaPlayer] Video: ${_mediaInfo?.videoCodec}, '
          'Audio: ${_mediaInfo?.audioCodec}, '
          'Tracks: ${_mediaInfo?.audioTracks.length}',
        );
      }
    } catch (e) {
      debugPrint('[MediaPlayer] Failed to fetch media info: $e');
    }
  }

  /// 扫描同目录下的外挂字幕文件
  Future<void> _scanExternalSubtitles() async {
    try {
      final uri = Uri.parse(widget.mediaUrl);
      final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';

      // 获取视频文件所在目录
      String videoPath = '';
      bool foundPlay = false;
      for (final segment in uri.pathSegments) {
        if (foundPlay) {
          videoPath += '/$segment';
        }
        if (segment == 'play' || segment == 'stream') {
          foundPlay = true;
        }
      }

      if (videoPath.isEmpty) {
        return;
      }

      // 获取目录路径
      final lastSlash = videoPath.lastIndexOf('/');
      if (lastSlash <= 0) {
        return;
      }
      final dirPath = videoPath.substring(0, lastSlash);
      final videoFileName = videoPath
          .substring(lastSlash + 1)
          .replaceAll(RegExp(r'\.[^.]+$'), '');

      // 请求目录列表
      final listUrl = '$baseUrl/api/v1/filemanager/list?path=$dirPath';
      final response = await http
          .get(
            Uri.parse(listUrl),
            headers: _authToken != null
                ? {'Authorization': 'Bearer $_authToken'}
                : {},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final files = json['files'] as List<dynamic>? ?? [];

        int subtitleIndex = 100; // 外挂字幕从100开始编号
        for (final file in files) {
          final fileName = file['name'] as String? ?? '';
          final ext = fileName.toLowerCase();

          // 检查是否是字幕文件
          if (ext.endsWith('.srt') ||
              ext.endsWith('.ass') ||
              ext.endsWith('.ssa') ||
              ext.endsWith('.vtt') ||
              ext.endsWith('.sub')) {
            // 检查是否与视频文件名匹配
            final subBaseName = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
            if (subBaseName
                .toLowerCase()
                .startsWith(videoFileName.toLowerCase())) {
              // 提取语言标识
              String? language;
              final langMatch = RegExp(r'\.([a-z]{2,3})\.')
                  .firstMatch(fileName.toLowerCase());
              if (langMatch != null) {
                language = langMatch.group(1);
              }

              _externalSubtitles.add(SubtitleTrackInfo(
                index: subtitleIndex++,
                language: language,
                title: fileName,
                codec: ext.split('.').last,
                isExternal: true,
                externalPath: '$dirPath/$fileName',
              ));
            }
          }
        }

        debugPrint(
            '[MediaPlayer] Found ${_externalSubtitles.length} external subtitles');
      }
    } catch (e) {
      debugPrint('[MediaPlayer] Failed to scan external subtitles: $e');
    }
  }

  String _getStreamUrl({int? audioTrack}) {
    String url = widget.mediaUrl;

    // 如果需要转码，使用转码URL
    if (_isTranscoding && _mediaInfo?.transcodeUrl != null) {
      final uri = Uri.parse(widget.mediaUrl);
      final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';
      url = '$baseUrl${_mediaInfo!.transcodeUrl}';
    }

    // 添加音轨选择参数
    if (audioTrack != null && audioTrack > 0) {
      final separator = url.contains('?') ? '&' : '?';
      url = '$url${separator}audio_track=$audioTrack';
    }

    return url;
  }

  Future<void> _initializePlayer() async {
    if (_isInitializing || _disposed) {
      return;
    }
    _isInitializing = true;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      // 清理旧的控制器
      _playbackMonitor?.cancel();
      await _chewieController?.pause();
      _chewieController?.dispose();
      _chewieController = null;
      await _videoController?.dispose();
      _videoController = null;

      // 等待资源释放
      await Future.delayed(const Duration(milliseconds: 200));
      if (_disposed) {
        return;
      }

      final headers = <String, String>{};
      if (_authToken != null && _authToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_authToken';
      }

      final streamUrl = _getStreamUrl(audioTrack: _selectedAudioTrack);
      debugPrint('[MediaPlayer] Initializing: $streamUrl');

      // 创建视频控制器
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        httpHeaders: headers,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      // 初始化，带超时 - 流媒体协议使用更长的超时
      final timeout = _isStreamingProtocol
          ? const Duration(seconds: 60)
          : const Duration(seconds: 30);

      await _videoController!.initialize().timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException('视频加载超时，请检查网络连接');
        },
      );

      if (_disposed || !mounted) {
        return;
      }

      // 检查视频是否真的初始化成功
      if (!_videoController!.value.isInitialized) {
        throw Exception('视频初始化失败');
      }

      debugPrint(
        '[MediaPlayer] Video initialized: ${_videoController!.value.size}',
      );

      // 获取主题颜色
      final primaryColor = Theme.of(context).colorScheme.primary;

      // 创建 Chewie 控制器
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        looping: _isLooping,
        showControls: true,
        allowFullScreen: false,
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        playbackSpeeds: _playbackSpeeds,
        autoInitialize: false,
        showOptions: false,
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
        errorBuilder: (context, errorMessage) =>
            _buildInlineError(errorMessage),
        materialProgressColors: ChewieProgressColors(
          playedColor: primaryColor,
          handleColor: primaryColor,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
      );

      // 设置播放速度
      await _videoController!.setPlaybackSpeed(_playbackSpeed);

      // 启动播放监控
      _startPlaybackMonitor();

      _retryCount = 0;
      _stallCount = 0;

      if (mounted && !_disposed) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[MediaPlayer] Error: $e');

      // 自动重试
      if (_retryCount < _maxRetries) {
        _retryCount++;
        debugPrint('[MediaPlayer] Retry $_retryCount/$_maxRetries');
        _isInitializing = false;
        await Future.delayed(Duration(milliseconds: 1000 * _retryCount));
        if (!_disposed && mounted) {
          await _initializePlayer();
        }
        return;
      }

      // 尝试转码
      if (!_isTranscoding &&
          _mediaInfo?.needsAudioTranscode == true &&
          !_disposed) {
        debugPrint('[MediaPlayer] Trying transcoded stream...');
        _isTranscoding = true;
        _retryCount = 0;
        _isInitializing = false;
        await _initializePlayer();
        return;
      }

      if (mounted && !_disposed) {
        setState(() {
          _error = _getErrorMessage(e);
          _isLoading = false;
        });
      }
    } finally {
      _isInitializing = false;
    }
  }

  void _startPlaybackMonitor() {
    _playbackMonitor?.cancel();
    _lastPositionUpdate = DateTime.now();
    _lastPosition = Duration.zero;

    _playbackMonitor = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_disposed || _videoController == null || !mounted) {
        timer.cancel();
        return;
      }

      final value = _videoController!.value;
      final now = DateTime.now();

      if (value.isPlaying && !value.isBuffering) {
        if (_lastPosition == value.position &&
            _lastPositionUpdate != null &&
            now.difference(_lastPositionUpdate!).inSeconds > 3) {
          _stallCount++;
          debugPrint('[MediaPlayer] Playback stalled, count: $_stallCount');

          if (_stallCount >= 3) {
            _recoverPlayback();
          }
        } else {
          _stallCount = 0;
        }
      }

      _lastPosition = value.position;
      _lastPositionUpdate = now;
    });
  }

  Future<void> _recoverPlayback() async {
    if (_disposed || _videoController == null) {
      return;
    }

    debugPrint('[MediaPlayer] Attempting to recover playback...');
    _stallCount = 0;

    try {
      final currentPosition = _videoController!.value.position;
      await _videoController!.pause();
      await Future.delayed(const Duration(milliseconds: 200));
      final newPosition = currentPosition + const Duration(milliseconds: 500);
      await _videoController!.seekTo(newPosition);
      await Future.delayed(const Duration(milliseconds: 100));

      await _videoController!.play();
    } catch (e) {
      debugPrint('[MediaPlayer] Recovery failed: $e');
    }
  }

  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('timeout')) {
      return '加载超时\n请检查网络连接后重试';
    }
    if (errorStr.contains('codec') ||
        errorStr.contains('audio') ||
        errorStr.contains('dts') ||
        errorStr.contains('ac3') ||
        errorStr.contains('truehd')) {
      return '不支持的音频格式\n编码: ${_originalAudioCodec ?? "unknown"}\n'
          '${_isTranscoding ? "转码失败，请检查服务器FFmpeg" : "正在尝试转码..."}';
    }
    if (errorStr.contains('network') ||
        errorStr.contains('connection') ||
        errorStr.contains('socket') ||
        errorStr.contains('host')) {
      return '网络连接失败\n请检查网络后重试';
    }
    if (errorStr.contains('format') ||
        errorStr.contains('container') ||
        errorStr.contains('source') ||
        errorStr.contains('datasource')) {
      return '不支持的视频格式\n'
          '视频编码: ${_mediaInfo?.videoCodec ?? "unknown"}\n'
          '音频编码: ${_mediaInfo?.audioCodec ?? "unknown"}';
    }
    if (errorStr.contains('permission')) {
      return '没有播放权限';
    }
    if (errorStr.contains('rtsp') || errorStr.contains('rtp')) {
      return 'RTSP/RTP流连接失败\n请检查流地址是否正确';
    }

    return '播放失败\n$error';
  }

  Widget _buildInlineError(String errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(
              errorMessage,
              style: const TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                _retryCount = 0;
                _initializePlayer();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleLoop() {
    setState(() => _isLooping = !_isLooping);
    _chewieController?.setLooping(_isLooping);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isLooping ? '循环播放已开启' : '循环播放已关闭'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _changePlaybackSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _videoController?.setPlaybackSpeed(speed);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('播放速度: ${speed}x'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _changeAudioTrack(int trackIndex) {
    if (trackIndex == _selectedAudioTrack) {
      return;
    }

    setState(() => _selectedAudioTrack = trackIndex);

    final currentPosition = _videoController?.value.position;

    _retryCount = 0;
    _initializePlayer().then((_) {
      if (currentPosition != null && _videoController != null) {
        _videoController!.seekTo(currentPosition);
      }
    });

    if (mounted) {
      final track = _mediaInfo?.audioTracks[trackIndex];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('已切换音轨: ${track?.displayName ?? "音轨 ${trackIndex + 1}"}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _changeSubtitleTrack(int trackIndex) {
    setState(() => _selectedSubtitleTrack = trackIndex);

    if (trackIndex == -1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('字幕已关闭'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } else {
      SubtitleTrackInfo? track;
      final allSubtitles = [
        ...(_mediaInfo?.subtitleTracks ?? []),
        ..._externalSubtitles,
      ];
      if (trackIndex < allSubtitles.length) {
        track = allSubtitles[trackIndex];
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('已选择字幕: ${track?.displayName ?? "字幕 ${trackIndex + 1}"}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Future<void> _downloadFile() async {
    if (_isDownloading) {
      return;
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.storage.request();
      if (!status.isGranted && Platform.isAndroid) {
        final ms = await Permission.manageExternalStorage.request();
        if (!ms.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('需要存储权限')),
            );
          }
          return;
        }
      }
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    Directory? downloadDir;
    try {
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

      final file = File('${downloadDir.path}/${widget.fileName}');
      final request = http.Request('GET', Uri.parse(widget.mediaUrl));
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
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSettingsSheet(),
    );
  }

  Widget _buildSettingsSheet() {
    final colorScheme = Theme.of(context).colorScheme;
    final allSubtitles = [
      ...(_mediaInfo?.subtitleTracks ?? []),
      ..._externalSubtitles,
    ];

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.settings, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  '播放设置',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSettingSection(
                    icon: Icons.speed,
                    title: '播放速度',
                    child: Wrap(
                      spacing: 8,
                      children: _playbackSpeeds.map((speed) {
                        final isSelected = _playbackSpeed == speed;
                        return ChoiceChip(
                          label: Text('${speed}x'),
                          selected: isSelected,
                          onSelected: (_) {
                            Navigator.pop(context);
                            _changePlaybackSpeed(speed);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_mediaInfo != null && _mediaInfo!.audioTracks.isNotEmpty)
                    _buildSettingSection(
                      icon: Icons.audiotrack,
                      title: '音轨 (${_mediaInfo!.audioTracks.length})',
                      child: Column(
                        children: _mediaInfo!.audioTracks
                            .asMap()
                            .entries
                            .map((entry) {
                          final index = entry.key;
                          final track = entry.value;
                          return RadioListTile<int>(
                            value: index,
                            groupValue: _selectedAudioTrack,
                            title: Text(track.displayName),
                            subtitle: Text(
                                '${track.codec.toUpperCase()} ${track.sampleRate}Hz'),
                            dense: true,
                            onChanged: (value) {
                              Navigator.pop(context);
                              if (value != null) {
                                _changeAudioTrack(value);
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ),

                  // 字幕选择
                  if (allSubtitles.isNotEmpty)
                    _buildSettingSection(
                      icon: Icons.subtitles,
                      title: '字幕 (${allSubtitles.length})',
                      child: Column(
                        children: [
                          RadioListTile<int>(
                            value: -1,
                            groupValue: _selectedSubtitleTrack,
                            title: const Text('关闭字幕'),
                            dense: true,
                            onChanged: (value) {
                              Navigator.pop(context);
                              if (value != null) {
                                _changeSubtitleTrack(value);
                              }
                            },
                          ),
                          ...allSubtitles.asMap().entries.map((entry) {
                            final index = entry.key;
                            final track = entry.value;
                            return RadioListTile<int>(
                              value: index,
                              groupValue: _selectedSubtitleTrack,
                              title: Text(track.displayName),
                              subtitle: Text(track.codec.toUpperCase()),
                              dense: true,
                              onChanged: (value) {
                                Navigator.pop(context);
                                if (value != null) {
                                  _changeSubtitleTrack(value);
                                }
                              },
                            );
                          }),
                        ],
                      ),
                    ),

                  // 媒体信息
                  if (_mediaInfo != null)
                    _buildSettingSection(
                      icon: Icons.info_outline,
                      title: '媒体信息',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow(
                              '格式', _mediaInfo!.containerFormat ?? '未知'),
                          _buildInfoRow('视频编码', _mediaInfo!.videoCodec ?? '无'),
                          _buildInfoRow('音频编码', _mediaInfo!.audioCodec ?? '无'),
                          _buildInfoRow('分辨率', _mediaInfo!.resolutionInfo),
                          if (_mediaInfo!.frameRate != null)
                            _buildInfoRow('帧率',
                                '${_mediaInfo!.frameRate!.toStringAsFixed(2)} fps'),
                          if (_mediaInfo!.duration != null)
                            _buildInfoRow(
                                '时长', _formatDuration(_mediaInfo!.duration!)),
                          _buildInfoRow('文件大小', _formatBytes(_mediaInfo!.size)),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingSection({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _exitFullScreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoPlayer(),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(colorScheme),
            ),
            if (_error != null && !_isLoading) _buildErrorState(),
            if (_isDownloading) _buildDownloadOverlay(),
            if (_isTranscoding && !_isLoading && _error == null)
              _buildTranscodingIndicator(),
            if (_isStreamingProtocol && !_isLoading && _error == null)
              _buildStreamingIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              _isTranscoding ? '正在转码...' : '加载中...',
              style: const TextStyle(color: Colors.white),
            ),
            if (_mediaInfo != null) ...[
              const SizedBox(height: 8),
              Text(
                _mediaInfo!.codecInfo,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            if (_retryCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '重试 $_retryCount/$_maxRetries',
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ],
            if (_isStreamingProtocol) ...[
              const SizedBox(height: 8),
              Text(
                '协议: $_streamingProtocol',
                style: const TextStyle(color: Colors.blue, fontSize: 12),
              ),
            ],
          ],
        ),
      );
    }

    if (_chewieController != null &&
        _videoController != null &&
        _videoController!.value.isInitialized) {
      return Chewie(controller: _chewieController!);
    }

    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }

  Widget _buildTopBar(ColorScheme colorScheme) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  _exitFullScreen();
                  Navigator.pop(context);
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.fileName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_mediaInfo != null)
                      Text(
                        _mediaInfo!.codecInfo +
                            (_isTranscoding ? ' → AAC' : '') +
                            (_playbackSpeed != 1.0
                                ? ' (${_playbackSpeed}x)'
                                : ''),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              // 设置按钮
              IconButton(
                icon: const Icon(Icons.tune, color: Colors.white),
                onPressed: _showSettingsMenu,
                tooltip: '播放设置',
              ),
              // 下载按钮
              if (_isDownloading)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      value: _downloadProgress,
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.white),
                  onPressed: _downloadFile,
                  tooltip: '下载',
                ),
              // 循环按钮
              IconButton(
                icon: Icon(
                  _isLooping ? Icons.repeat_one : Icons.repeat,
                  color: _isLooping ? colorScheme.primary : Colors.white,
                ),
                onPressed: _toggleLoop,
                tooltip: '循环播放',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                _retryCount = 0;
                _initializePlayer();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _exitFullScreen();
                Navigator.pop(context);
              },
              child: const Text('返回'),
            ),
            const SizedBox(height: 24),
            // 显示媒体信息帮助调试
            if (_mediaInfo != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '媒体信息:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '格式: ${_mediaInfo!.containerFormat ?? "未知"}\n'
                      '视频编码: ${_mediaInfo!.videoCodec ?? "未知"}\n'
                      '音频编码: ${_mediaInfo!.audioCodec ?? "未知"}\n'
                      '分辨率: ${_mediaInfo!.resolutionInfo}\n'
                      '文件大小: ${_formatBytes(_mediaInfo!.size)}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadOverlay() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.download, color: Colors.white),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('下载中...', style: TextStyle(color: Colors.white)),
                ),
                Text(
                  '${(_downloadProgress * 100).toInt()}%',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _downloadProgress,
              backgroundColor: Colors.white24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscodingIndicator() {
    return Positioned(
      bottom: 80,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.transform, color: Colors.orange.shade300, size: 16),
            const SizedBox(width: 6),
            Text(
              '${_originalAudioCodec?.toUpperCase() ?? "DTS"} → AAC',
              style: TextStyle(
                color: Colors.orange.shade300,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamingIndicator() {
    return Positioned(
      bottom: 80,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.stream, color: Colors.blue.shade300, size: 16),
            const SizedBox(width: 6),
            Text(
              _streamingProtocol ?? 'STREAM',
              style: TextStyle(
                color: Colors.blue.shade300,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
