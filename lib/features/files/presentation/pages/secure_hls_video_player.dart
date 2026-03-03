import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/widgets/shell_scaffold.dart';
import '../../../../services/sae_handshake_service.dart';

/// 智能视频播放器 - 优先直接流式播放，回退到安全 HLS
///
/// 播放策略（快到慢）：
/// 1. 【直接播放】HTTP Range 流式传输（最快，零延迟）
///    - media_kit (mpv) 原生支持 Range 请求
///    - 通过 HTTP headers 传递 JWT 认证
///    - 支持所有 mpv 支持的格式（MP4/MKV/AVI/WebM 等）
///    - 即时开始播放，支持快进快退
///
/// 2. 【安全 HLS】SAE 握手 + ffmpeg 渐进式分片（回退）
///    - 仅在直接播放失败时使用（例如需要转码的格式）
///    - 渐进式分片：ffmpeg 在后台分片，首个片段可用即开始播放
///    - 不再等待全部分片完成
/// - ARM 设备友好，无加解密开销
class SecureHlsVideoPlayer extends ConsumerStatefulWidget {
  final String? filePath;
  final String? fileId;
  final String fileName;
  final String baseUrl;

  const SecureHlsVideoPlayer({
    super.key,
    this.filePath,
    this.fileId,
    required this.fileName,
    required this.baseUrl,
  }) : assert(filePath != null || fileId != null,
            'Either filePath or fileId is required');

  @override
  ConsumerState<SecureHlsVideoPlayer> createState() =>
      _SecureHlsVideoPlayerState();
}

class _SecureHlsVideoPlayerState extends ConsumerState<SecureHlsVideoPlayer> {
  Player? _player;
  VideoController? _videoController;

  bool _isLoading = true;
  String? _error;
  String _loadingStatus = '正在建立安全连接...';
  String? _authToken;
  String? _hlsSessionId;
  String? _userId;
  String? _userPassword;

  bool _isDownloading = false;
  double _downloadProgress = 0;

  /// 当前播放模式 - 用于 UI 显示
  /// 'direct' = 直接 HTTP Range 流式传输（最快）
  /// 'hls'    = SAE + HLS 安全播放（回退）
  String _playbackMode = 'direct';

  // 播放器状态
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _showControls = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Timer? _hideControlsTimer;

  // 播放速度选项
  double _playbackSpeed = 1.0;
  static const List<double> _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
    WakelockPlus.enable();
    _initPlayer();
    _startHideControlsTimer();
  }

  Future<void> _initPlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
        _loadingStatus = '正在获取凭据...';
      });

      // 获取用户凭据
      const storage = FlutterSecureStorage();
      _authToken = await storage.read(key: 'access_token');
      _userId = await storage.read(key: 'user_id');
      _userPassword = await storage.read(key: 'user_password_hash');

      if (_authToken == null || _authToken!.isEmpty) {
        _setError('未登录，请先登录');
        return;
      }

      if (_userId == null || _userPassword == null) {
        _setError('无法获取用户凭据，请重新登录');
        return;
      }

      // ===== 策略 1：直接 HTTP Range 流式传输（最快） =====
      // media_kit (mpv) 原生支持 Range 请求 + httpHeaders 传递 JWT 认证
      // 对于 MP4/MKV/AVI/WebM/FLV 等常见格式，即时播放、支持快进快退
      final directSuccess = await _tryDirectStreaming();
      if (directSuccess) return;

      if (!mounted) return;

      // ===== 策略 2：SAE + HLS 安全播放（回退） =====
      // 对于需要转码的格式或直接播放失败的场景，走 HLS 管道
      debugPrint(
          '[VideoPlayer] Direct streaming failed, falling back to HLS...');
      await _tryHlsStreaming();
    } catch (e, stack) {
      debugPrint('[VideoPlayer] Error: $e');
      debugPrint('[VideoPlayer] Stack: $stack');
      _setError('播放失败: ${_formatError(e.toString())}');
    }
  }

  /// 策略 1：直接 HTTP Range 流式传输
  ///
  /// 使用 /api/v1/filemanager/media/stream 端点
  /// media_kit (mpv) 通过 HTTP headers 传递 JWT 认证
  /// 支持所有 mpv 支持的容器/编解码器格式
  /// 无需 ffmpeg 分片，无需 SAE 握手，延迟 < 1 秒
  Future<bool> _tryDirectStreaming() async {
    try {
      setState(() {
        _loadingStatus = '正在连接视频流...';
        _playbackMode = 'direct';
      });

      final filePath = widget.filePath ?? '';
      final streamUrl =
          '${widget.baseUrl}/api/v1/filemanager/media/stream?path=${Uri.encodeComponent(filePath)}';

      debugPrint('[VideoPlayer] Trying direct streaming: $streamUrl');

      // 先验证 URL 可访问（HEAD 请求检查，避免播放器黑屏卡死）
      try {
        final checkResponse = await http.head(
          Uri.parse(streamUrl),
          headers: {
            'Authorization': 'Bearer $_authToken',
            'Accept': '*/*',
          },
        ).timeout(const Duration(seconds: 8));

        if (checkResponse.statusCode != 200 &&
            checkResponse.statusCode != 206 &&
            checkResponse.statusCode != 416) {
          debugPrint(
              '[VideoPlayer] Direct stream not available (status: ${checkResponse.statusCode})');
          return false;
        }

        // 检查是否支持 Range 请求
        final acceptRanges = checkResponse.headers['accept-ranges'] ?? '';
        final contentLength = checkResponse.headers['content-length'] ?? '0';
        debugPrint(
            '[VideoPlayer] Direct stream: Accept-Ranges=$acceptRanges, Content-Length=$contentLength');
      } catch (e) {
        debugPrint('[VideoPlayer] Direct stream HEAD check failed: $e');
        return false;
      }

      if (!mounted) return false;

      setState(() => _loadingStatus = '正在初始化播放器...');

      // 创建 media_kit 播放器
      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 96 * 1024 * 1024, // 96MB 缓冲 - 适合大文件
        ),
      );

      _videoController = VideoController(_player!);

      // 设置播放器事件监听
      _setupPlayerListeners();

      // 监听第一个错误，如果播放器无法解码则回退
      final errorCompleter = Completer<String?>();
      StreamSubscription<String>? errorSub;
      errorSub = _player!.stream.error.listen((error) {
        if (error.isNotEmpty && !errorCompleter.isCompleted) {
          errorCompleter.complete(error);
          errorSub?.cancel();
        }
      });

      // 监听成功开始播放
      final playingCompleter = Completer<bool>();
      StreamSubscription<bool>? playingSub;
      playingSub = _player!.stream.playing.listen((playing) {
        if (playing && !playingCompleter.isCompleted) {
          playingCompleter.complete(true);
          playingSub?.cancel();
        }
      });

      // 使用 media_kit 直接打开流媒体 URL，传递 JWT 认证头
      await _player!.open(
        Media(
          streamUrl,
          httpHeaders: {
            'Authorization': 'Bearer $_authToken',
          },
        ),
        play: true,
      );

      // 等待播放器开始播放或报错（最多 10 秒）
      final result = await Future.any([
        playingCompleter.future.then((_) => 'playing'),
        errorCompleter.future.then((e) => 'error:$e'),
        Future.delayed(const Duration(seconds: 10), () => 'timeout'),
      ]);

      errorSub.cancel();
      playingSub.cancel();

      if (result == 'playing') {
        debugPrint('[VideoPlayer] Direct streaming successful!');
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return true;
      }

      // 直接播放失败 - 清理播放器，准备回退
      debugPrint('[VideoPlayer] Direct playback issue: $result');
      _cancelSubscriptions();
      await _player?.stop();
      await _player?.dispose();
      _player = null;
      _videoController = null;
      return false;
    } catch (e) {
      debugPrint('[VideoPlayer] Direct streaming exception: $e');
      // 清理以便回退
      _cancelSubscriptions();
      await _player?.stop();
      await _player?.dispose();
      _player = null;
      _videoController = null;
      return false;
    }
  }

  /// 策略 2：SAE 握手 + HLS 安全播放（回退）
  ///
  /// 使用 SAE 密码认证握手建立安全会话
  /// 服务器使用 ffmpeg 渐进式分片（首个片段即可播放，不等待全部分片完成）
  /// media_kit (mpv) 播放 HLS 流
  Future<void> _tryHlsStreaming() async {
    setState(() {
      _loadingStatus = '正在执行 SAE 安全握手...';
      _playbackMode = 'hls';
    });

    debugPrint('[VideoPlayer] Starting SAE handshake for HLS fallback...');

    final handshakeService = SaeHandshakeService(
      baseUrl: widget.baseUrl,
      jwtToken: _authToken!,
    );

    final filePath = widget.filePath ?? '';
    final (sessionId, _) = await handshakeService.performHandshake(
      filePath: filePath,
      password: _userPassword!,
      userId: _userId!,
    );

    _hlsSessionId = sessionId;

    // 渐进式分片 - 服务器使用 -hls_playlist_type event，首个片段可用即返回
    final playlistUrl =
        '${widget.baseUrl}/api/v1/secure-hls/$_hlsSessionId/playlist.m3u8';

    debugPrint('[VideoPlayer] HLS session: $_hlsSessionId');
    debugPrint('[VideoPlayer] Playlist URL: $playlistUrl');

    // 等待播放列表就绪（渐进式分片后通常 2-5 秒即可）
    setState(() => _loadingStatus = '正在等待视频分片...');

    bool playlistReady = false;
    for (int i = 0; i < 60; i++) {
      if (!mounted) return;

      try {
        final checkResponse = await http.get(
          Uri.parse(playlistUrl),
          headers: {
            'Authorization': 'Bearer $_authToken',
            'Accept': 'application/vnd.apple.mpegurl, */*',
            'User-Agent': 'RockZeroOS/1.0',
          },
        ).timeout(const Duration(seconds: 5));

        if (checkResponse.statusCode == 200) {
          final content = checkResponse.body;
          if (content.contains('#EXTM3U') &&
              (content.contains('#EXTINF') || content.contains('segment_'))) {
            debugPrint(
                '[VideoPlayer] HLS playlist ready after ${i + 1} seconds');
            playlistReady = true;
            break;
          }
        }
        debugPrint(
            '[VideoPlayer] HLS playlist not ready (status=${checkResponse.statusCode}), waiting... (${i + 1}s)');
      } catch (e) {
        debugPrint(
            '[VideoPlayer] HLS playlist check failed: $e, waiting... (${i + 1}s)');
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    if (!playlistReady) {
      throw Exception('播放列表生成超时（已等待 60 秒），请检查服务器 ffmpeg 配置');
    }

    if (!mounted) return;

    setState(() => _loadingStatus = '正在初始化播放器...');

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024, // 64MB 缓冲
      ),
    );

    _videoController = VideoController(_player!);
    _setupPlayerListeners();

    await _player!.open(
      Media(
        playlistUrl,
        httpHeaders: {
          'Authorization': 'Bearer $_authToken',
        },
      ),
      play: true,
    );

    if (mounted) {
      setState(() => _isLoading = false);
    }

    debugPrint('[VideoPlayer] HLS player initialized successfully');
  }

  void _setupPlayerListeners() {
    _cancelSubscriptions();

    _subscriptions.add(_player!.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    }));

    _subscriptions.add(_player!.stream.position.listen((position) {
      if (mounted) setState(() => _position = position);
    }));

    _subscriptions.add(_player!.stream.duration.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    }));

    _subscriptions.add(_player!.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    }));

    _subscriptions.add(_player!.stream.buffer.listen((buffer) {
      if (mounted) setState(() => _bufferedPosition = buffer);
    }));

    _subscriptions.add(_player!.stream.error.listen((error) {
      if (error.isNotEmpty && mounted) {
        debugPrint('[SecureHLS] Player error: $error');
      }
    }));

    _subscriptions.add(_player!.stream.completed.listen((completed) {
      if (completed && mounted) {
        debugPrint('[SecureHLS] Playback completed');
      }
    }));
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  void _setError(String error) {
    if (mounted) {
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  String _formatError(String error) {
    if (error.contains('HTTP 500') || error.contains('500')) {
      return '服务器转码失败，请稍后重试';
    }
    if (error.contains('HTTP 404') || error.contains('404')) {
      return '视频文件不存在';
    }
    if (error.contains('timeout') || error.contains('Timeout')) {
      return '连接超时，请检查网络';
    }
    if (error.contains('SAE') || error.contains('handshake')) {
      return '安全握手失败，请重新登录';
    }
    return error;
  }

  Future<void> _retry() async {
    await _cleanupHlsSession();
    _cancelSubscriptions();
    await _player?.stop();
    await _player?.dispose();
    _player = null;
    _videoController = null;
    _playbackMode = 'direct';
    await _initPlayer();
  }

  Future<void> _cleanupHlsSession() async {
    // 停止 HLS 会话
    if (_hlsSessionId != null && _authToken != null) {
      try {
        await http.post(
          Uri.parse('${widget.baseUrl}/api/v1/secure-hls/$_hlsSessionId/stop'),
          headers: {'Authorization': 'Bearer $_authToken'},
        );
        debugPrint('[SecureHLS] HLS session stopped: $_hlsSessionId');
      } catch (e) {
        debugPrint('[SecureHLS] Failed to stop HLS session: $e');
      }
      _hlsSessionId = null;
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _cancelSubscriptions();
    _player?.dispose();
    _cleanupHlsSession();
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

  // ============ 播放控制 ============

  void _togglePlayPause() {
    if (_player == null) return;
    if (_isPlaying) {
      _player!.pause();
    } else {
      _player!.play();
    }
  }

  void _seekTo(Duration position) {
    if (_player == null) return;
    final clamped = Duration(
      milliseconds: position.inMilliseconds.clamp(0, _duration.inMilliseconds),
    );
    _player!.seek(clamped);
  }

  void _seekRelative(int seconds) {
    _seekTo(_position + Duration(seconds: seconds));
  }

  void _setPlaybackSpeed(double speed) {
    _player?.setRate(speed);
    setState(() => _playbackSpeed = speed);
  }

  // ============ 控制栏显示/隐藏 ============

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  // ============ 下载 ============

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

  // ============ 格式化工具 ============

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ============ UI 构建 ============

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
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 视频画面
            if (_videoController != null && !_isLoading && _error == null)
              GestureDetector(
                onTap: _toggleControls,
                onDoubleTapDown: (details) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  if (details.globalPosition.dx < screenWidth / 3) {
                    _seekRelative(-10);
                  } else if (details.globalPosition.dx > screenWidth * 2 / 3) {
                    _seekRelative(10);
                  } else {
                    _togglePlayPause();
                  }
                },
                child: Video(
                  controller: _videoController!,
                  fill: Colors.black,
                  controls: NoVideoControls,
                ),
              ),

            // 缓冲指示器
            if (_isBuffering && !_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              ),

            // 自定义控制栏
            if (!_isLoading && _error == null && _showControls)
              _buildControlsOverlay(),

            // 加载状态
            if (_isLoading) _buildLoading(),

            // 错误状态
            if (_error != null && !_isLoading) _buildError(),

            // 下载进度
            if (_isDownloading) _buildDownloadProgress(),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: IgnorePointer(
        ignoring: !_showControls,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black54,
                Colors.transparent,
                Colors.transparent,
                Colors.black54,
              ],
              stops: [0.0, 0.15, 0.85, 1.0],
            ),
          ),
          child: Column(
            children: [
              // 顶部栏
              _buildTopBar(),
              const Spacer(),
              // 中间播放按钮
              _buildCenterControls(),
              const Spacer(),
              // 底部进度条和控制按钮
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () {
                _exitFullscreen();
                Navigator.pop(context);
              },
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                widget.fileName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showEncryptionDetails(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _playbackMode == 'direct'
                      ? Colors.blue.withValues(alpha: 0.25)
                      : Colors.green.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _playbackMode == 'direct'
                        ? Colors.blue.withValues(alpha: 0.5)
                        : Colors.green.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 14,
                      color: _playbackMode == 'direct'
                          ? Colors.lightBlueAccent
                          : Colors.greenAccent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _playbackMode == 'direct' ? 'AES256' : 'SAE+AES256',
                      style: TextStyle(
                        fontSize: 11,
                        color: _playbackMode == 'direct'
                            ? Colors.lightBlueAccent
                            : Colors.greenAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.white),
              onPressed: _downloadFile,
              tooltip: '下载原文件',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 快退 10 秒
        IconButton(
          icon: const Icon(Icons.replay_10_rounded,
              color: Colors.white, size: 36),
          onPressed: () => _seekRelative(-10),
          splashRadius: 28,
        ),
        const SizedBox(width: 32),
        // 播放/暂停
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _togglePlayPause,
            splashColor: Colors.white24,
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),
          ),
        ),
        const SizedBox(width: 32),
        // 快进 10 秒
        IconButton(
          icon: const Icon(Icons.forward_10_rounded,
              color: Colors.white, size: 36),
          onPressed: () => _seekRelative(10),
          splashRadius: 28,
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final totalMs = _duration.inMilliseconds.toDouble();
    final posMs = _position.inMilliseconds.toDouble();
    final bufMs = _bufferedPosition.inMilliseconds.toDouble();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 时间行 - 放在 slider 上方
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    _formatDuration(_position),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDuration(_duration),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            // MD3 风格进度条 - 单层 slider，用自定义 track 显示缓冲
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                  elevation: 2,
                  pressedElevation: 4,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: colorScheme.primary,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                thumbColor: colorScheme.primary,
                overlayColor: colorScheme.primary.withValues(alpha: 0.12),
                secondaryActiveTrackColor: Colors.white.withValues(alpha: 0.3),
              ),
              child: Slider(
                value: totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0,
                secondaryTrackValue:
                    totalMs > 0 ? (bufMs / totalMs).clamp(0.0, 1.0) : 0.0,
                onChanged: (value) {
                  final newPos = Duration(
                    milliseconds: (value * totalMs).round(),
                  );
                  _seekTo(newPos);
                },
                onChangeStart: (_) {
                  _hideControlsTimer?.cancel();
                },
                onChangeEnd: (_) {
                  _startHideControlsTimer();
                },
              ),
            ),
            // 底部控制按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Spacer(),
                  // 播放速度
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _showSpeedPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          '${_playbackSpeed}x',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示加密协议详情弹窗 — 带流水线动画
  void _showEncryptionDetails() {
    final isHls = _playbackMode != 'direct';
    final sessionId = _hlsSessionId;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _EncryptionPipelineSheet(
        isHls: isHls,
        sessionId: sessionId,
      ),
    );
  }

  void _showSpeedPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '播放速度',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ..._speedOptions.map((speed) => ListTile(
                  title: Text(
                    '${speed}x',
                    style: TextStyle(
                      color: _playbackSpeed == speed
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white,
                      fontWeight: _playbackSpeed == speed
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: _playbackSpeed == speed
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    _setPlaybackSpeed(speed);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 16),
          Text(_loadingStatus, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 8),
          Text(
            _playbackMode == 'direct'
                ? '正在尝试直接流式播放...'
                : '直连失败 → SAE 握手 → HLS 分片播放',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
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

// ============================================================
// 加密流水线动画底部弹窗
// ============================================================

/// 数据模型 —— 流水线中的每个协议节点
class _ProtocolNode {
  final IconData icon;
  final String title;
  final String subtitle;
  final String detail;
  final Color color;

  const _ProtocolNode({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.color,
  });
}

/// 动画加密详情面板 —— 工厂流水线风格
class _EncryptionPipelineSheet extends StatefulWidget {
  final bool isHls;
  final String? sessionId;

  const _EncryptionPipelineSheet({
    required this.isHls,
    this.sessionId,
  });

  @override
  State<_EncryptionPipelineSheet> createState() =>
      _EncryptionPipelineSheetState();
}

class _EncryptionPipelineSheetState extends State<_EncryptionPipelineSheet>
    with TickerProviderStateMixin {
  // 主时间线控制器（驱动所有卡片的出场）
  late final AnimationController _masterController;
  // 盾牌脉冲
  late final AnimationController _shieldPulseController;
  // 数据粒子流动
  late final AnimationController _particleController;
  // 节点激活闪光
  late final AnimationController _glowController;

  late final List<_ProtocolNode> _nodes;

  // 为每个节点计算的入场动画（slide + fade）
  final List<Animation<double>> _slideAnimations = [];
  final List<Animation<double>> _fadeAnimations = [];
  // 连接线动画
  final List<Animation<double>> _connectorAnimations = [];
  // 激活状态动画
  final List<Animation<double>> _activateAnimations = [];

  @override
  void initState() {
    super.initState();

    // 构建节点列表
    _nodes = _buildNodes();

    // ---- 主时间线 ----
    // 总时长 = 节点数 * 350ms（交错间隔）+ 尾部余量
    final totalMs = _nodes.length * 350 + 400;
    _masterController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );

    // 为每个节点创建交错动画
    for (int i = 0; i < _nodes.length; i++) {
      final startFraction = (i * 350) / totalMs;
      final endFraction = ((i * 350) + 400) / totalMs;
      final start = startFraction.clamp(0.0, 1.0);
      final end = endFraction.clamp(0.0, 1.0);

      _slideAnimations.add(
        Tween<double>(begin: 60.0, end: 0.0).animate(
          CurvedAnimation(
            parent: _masterController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        ),
      );
      _fadeAnimations.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _masterController,
            curve: Interval(start, end, curve: Curves.easeOut),
          ),
        ),
      );

      // 激活动画（卡片出现后 → 光环扩散）
      final activateStart = (end + 0.02).clamp(0.0, 1.0);
      final activateEnd = (activateStart + 0.15).clamp(0.0, 1.0);
      _activateAnimations.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _masterController,
            curve: Interval(activateStart, activateEnd, curve: Curves.easeOut),
          ),
        ),
      );

      // 连接线（从上一个节点到当前节点之间的管道）
      if (i > 0) {
        final connStart = ((i * 350) - 100) / totalMs;
        final connEnd = ((i * 350) + 100) / totalMs;
        _connectorAnimations.add(
          Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(
              parent: _masterController,
              curve: Interval(
                connStart.clamp(0.0, 1.0),
                connEnd.clamp(0.0, 1.0),
                curve: Curves.easeInOut,
              ),
            ),
          ),
        );
      }
    }

    // ---- 盾牌脉冲 ----
    _shieldPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    // ---- 数据粒子 ----
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    // ---- 光效 ----
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // 启动主时间线
    _masterController.forward();
  }

  List<_ProtocolNode> _buildNodes() {
    final List<_ProtocolNode> nodes = [];
    nodes.add(_ProtocolNode(
      icon: Icons.vpn_key_rounded,
      title: '密钥交换',
      subtitle: widget.isHls
          ? 'WPA3-SAE (Simultaneous Authentication of Equals)'
          : 'JWT Token + Blake3 HKDF',
      detail: widget.isHls
          ? 'Dragonfly 密钥交换协议，抵抗离线字典攻击'
          : '基于 Blake3 的密钥派生函数生成会话密钥',
      color: Colors.orangeAccent,
    ));
    if (widget.isHls) {
      nodes.add(const _ProtocolNode(
        icon: Icons.verified_user_rounded,
        title: '零知识证明',
        subtitle: 'Bulletproofs Range Proof',
        detail: '每个分片请求附带 ZKP 证明，服务端验证访问权限而无需暴露凭据',
        color: Colors.purpleAccent,
      ));
    }
    nodes.add(const _ProtocolNode(
      icon: Icons.lock_rounded,
      title: '数据加密',
      subtitle: 'AES-256-GCM (Galois/Counter Mode)',
      detail: '每个数据块使用唯一 nonce 加密，提供认证加密和完整性保护',
      color: Colors.cyanAccent,
    ));
    nodes.add(const _ProtocolNode(
      icon: Icons.fingerprint_rounded,
      title: '完整性校验',
      subtitle: 'Blake3 Cryptographic Hash',
      detail: '所有传输数据使用 Blake3 哈希验证完整性，防止篡改',
      color: Colors.tealAccent,
    ));
    return nodes;
  }

  @override
  void dispose() {
    _masterController.dispose();
    _shieldPulseController.dispose();
    _particleController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 拖拽指示条
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 盾牌标题行
              _buildAnimatedHeader(),
              const SizedBox(height: 6),
              _buildSubtitleRow(),
              const SizedBox(height: 24),
              // 流水线节点列表
              ..._buildPipelineNodes(),
              // 会话信息卡
              if (widget.isHls && widget.sessionId != null) ...[
                const SizedBox(height: 20),
                _buildSessionInfo(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 盾牌标题 — 带脉冲光效
  Widget _buildAnimatedHeader() {
    final themeColor =
        widget.isHls ? Colors.greenAccent : Colors.lightBlueAccent;
    return AnimatedBuilder(
      animation: _shieldPulseController,
      builder: (context, child) {
        final pulse = _shieldPulseController.value;
        return Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: themeColor.withValues(alpha: 0.3 + pulse * 0.3),
                    blurRadius: 12 + pulse * 8,
                    spreadRadius: pulse * 4,
                  ),
                ],
              ),
              child: Icon(
                Icons.shield_rounded,
                color: themeColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              '端到端加密保护',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSubtitleRow() {
    final themeColor =
        widget.isHls ? Colors.greenAccent : Colors.lightBlueAccent;
    return Text(
      widget.isHls
          ? 'SAE + Bulletproofs ZKP + AES-256-GCM'
          : 'AES-256-GCM + Blake3 密钥派生',
      style: TextStyle(
        color: themeColor,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// 构建流水线节点列表（卡片 + 连接线交替排列）
  List<Widget> _buildPipelineNodes() {
    final List<Widget> widgets = [];
    for (int i = 0; i < _nodes.length; i++) {
      // 连接线（除了第一个节点之前）
      if (i > 0) {
        widgets.add(_buildAnimatedConnector(i - 1));
      }
      // 节点卡片
      widgets.add(_buildAnimatedNode(i));
    }
    return widgets;
  }

  /// 带动画的连接管道线
  Widget _buildAnimatedConnector(int connectorIndex) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _connectorAnimations[connectorIndex],
        _particleController,
      ]),
      builder: (context, _) {
        final progress = _connectorAnimations[connectorIndex].value;
        if (progress <= 0) return const SizedBox(height: 8);

        return SizedBox(
          height: 32,
          child: CustomPaint(
            size: const Size(double.infinity, 32),
            painter: _PipelineConnectorPainter(
              progress: progress,
              particlePhase: _particleController.value,
              fromColor: _nodes[connectorIndex].color,
              toColor: _nodes[connectorIndex + 1].color,
            ),
          ),
        );
      },
    );
  }

  /// 带动画的协议节点卡片
  Widget _buildAnimatedNode(int index) {
    final node = _nodes[index];
    return AnimatedBuilder(
      animation: _masterController,
      builder: (context, _) {
        final slide = _slideAnimations[index].value;
        final fade = _fadeAnimations[index].value;
        final activate = _activateAnimations[index].value;

        if (fade <= 0) return const SizedBox.shrink();

        return Transform.translate(
          offset: Offset(slide, 0),
          child: Opacity(
            opacity: fade,
            child: _NodeCard(
              node: node,
              activateProgress: activate,
              glowAnimation: _glowController,
              particleAnimation: _particleController,
            ),
          ),
        );
      },
    );
  }

  /// 会话信息卡片
  Widget _buildSessionInfo() {
    final sessionId = widget.sessionId!;
    return AnimatedBuilder(
      animation: _masterController,
      builder: (context, _) {
        // 在所有节点出现后再显示
        final showProgress = _masterController.value > 0.85
            ? ((_masterController.value - 0.85) / 0.15).clamp(0.0, 1.0)
            : 0.0;
        if (showProgress <= 0) return const SizedBox.shrink();

        return Opacity(
          opacity: showProgress,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - showProgress)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: Colors.white54, size: 14),
                      const SizedBox(width: 6),
                      const Text(
                        '会话信息',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Session: ${sessionId.length > 20 ? '${sessionId.substring(0, 20)}...' : sessionId}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '传输模式: 安全 HLS (UDP 70% + TCP 30%)',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 单个协议节点卡片 —— 带激活动效和光粒子
class _NodeCard extends StatelessWidget {
  final _ProtocolNode node;
  final double activateProgress;
  final AnimationController glowAnimation;
  final AnimationController particleAnimation;

  const _NodeCard({
    required this.node,
    required this.activateProgress,
    required this.glowAnimation,
    required this.particleAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([glowAnimation, particleAnimation]),
      builder: (context, _) {
        final glow = glowAnimation.value;
        final borderAlpha = 0.15 + activateProgress * 0.25 + glow * 0.1;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: node.color.withValues(alpha: 0.06 + activateProgress * 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: node.color.withValues(alpha: borderAlpha.clamp(0.0, 1.0)),
              width: 1.2,
            ),
            boxShadow: activateProgress > 0.5
                ? [
                    BoxShadow(
                      color: node.color.withValues(alpha: 0.08 + glow * 0.06),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 图标 + 激活光环
              _buildIconWithGlow(glow),
              const SizedBox(width: 14),
              // 文字区域
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          node.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadge(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      node.subtitle,
                      style: TextStyle(
                        color: node.color.withValues(alpha: 0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      node.detail,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIconWithGlow(double glow) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: node.color.withValues(alpha: 0.12 + activateProgress * 0.08),
        borderRadius: BorderRadius.circular(10),
        boxShadow: activateProgress > 0.3
            ? [
                BoxShadow(
                  color: node.color.withValues(alpha: 0.2 + glow * 0.15),
                  blurRadius: 10 + glow * 6,
                  spreadRadius: glow * 2,
                ),
              ]
            : null,
      ),
      child: Icon(node.icon, color: node.color, size: 22),
    );
  }

  Widget _buildStatusBadge() {
    return AnimatedOpacity(
      opacity: activateProgress,
      duration: Duration.zero,
      child: Transform.scale(
        scale: 0.8 + activateProgress * 0.2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: Colors.greenAccent.withValues(alpha: 0.3),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded,
                  color: Colors.greenAccent, size: 10),
              const SizedBox(width: 3),
              const Text(
                '已启用',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 流水线连接管道绘制器 —— 带流动粒子
class _PipelineConnectorPainter extends CustomPainter {
  final double progress;
  final double particlePhase;
  final Color fromColor;
  final Color toColor;

  _PipelineConnectorPainter({
    required this.progress,
    required this.particlePhase,
    required this.fromColor,
    required this.toColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final top = 0.0;
    final bottom = size.height * progress;

    // 管道线（渐变）
    final linePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          fromColor.withValues(alpha: 0.6),
          toColor.withValues(alpha: 0.6),
        ],
      ).createShader(Rect.fromLTRB(centerX - 1, top, centerX + 1, bottom))
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(centerX, top), Offset(centerX, bottom), linePaint);

    // 发光管道背景
    final glowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          fromColor.withValues(alpha: 0.08),
          toColor.withValues(alpha: 0.08),
        ],
      ).createShader(Rect.fromLTRB(centerX - 6, top, centerX + 6, bottom))
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawLine(Offset(centerX, top), Offset(centerX, bottom), glowPaint);

    // 流动粒子（3 个粒子沿管道上下流动）
    if (progress > 0.5) {
      for (int i = 0; i < 3; i++) {
        final phase = (particlePhase + i / 3.0) % 1.0;
        final y = top + (bottom - top) * phase;
        final opacity = (1.0 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
        final blendColor = Color.lerp(fromColor, toColor, phase)!;
        final particlePaint = Paint()
          ..color = blendColor.withValues(alpha: opacity * 0.8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

        canvas.drawCircle(Offset(centerX, y), 3, particlePaint);
      }
    }

    // 箭头 (▽) 在管道末端
    if (progress > 0.9) {
      final arrowPaint = Paint()
        ..color = toColor.withValues(alpha: 0.7)
        ..style = PaintingStyle.fill;

      final arrowPath = Path()
        ..moveTo(centerX - 5, bottom - 6)
        ..lineTo(centerX + 5, bottom - 6)
        ..lineTo(centerX, bottom)
        ..close();

      canvas.drawPath(arrowPath, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PipelineConnectorPainter old) =>
      old.progress != progress || old.particlePhase != particlePhase;
}
