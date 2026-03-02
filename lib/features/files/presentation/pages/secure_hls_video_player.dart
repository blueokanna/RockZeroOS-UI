import 'dart:async';
import 'dart:io';
import 'dart:ui';

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

/// 安全HLS视频播放器 - 使用SAE握手 + 直接HLS播放（media_kit/mpv）
///
/// 播放流程：
/// 1. SAE 握手建立安全会话（JWT + 密码验证 → session_id）
/// 2. 服务器用 ffmpeg 将视频分片为 HLS（VOD 模式）
/// 3. media_kit (mpv) 直接通过 GET 请求播放 HLS 流
/// 4. 段访问通过 session_id（128 位随机 UUID）鉴权
///
/// 优势：
/// - 使用 mpv 后端，支持广泛的编解码器和容器格式
/// - 直接 GET 请求获取段，无需本地代理，无需 ZKP 证明
/// - 支持随点随播，低延迟
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

      // SAE 握手
      setState(() => _loadingStatus = '正在执行 SAE 安全握手...');
      debugPrint('[SecureHLS] Starting SAE handshake...');

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

      // 直接播放列表 URL（服务器用 session_id 鉴权）
      final playlistUrl =
          '${widget.baseUrl}/api/v1/secure-hls/$_hlsSessionId/playlist.m3u8';

      debugPrint('[SecureHLS] HLS session created: $_hlsSessionId');
      debugPrint('[SecureHLS] Direct playlist URL: $playlistUrl');

      // 等待服务器 ffmpeg 分片完成
      setState(() => _loadingStatus = '正在等待视频分片...');
      debugPrint('[SecureHLS] Waiting for playlist to be ready...');

      bool playlistReady = false;
      for (int i = 0; i < 60; i++) {
        if (!mounted) return;

        try {
          final checkResponse = await http.get(
            Uri.parse(playlistUrl),
            headers: {
              'Accept': 'application/vnd.apple.mpegurl, */*',
              'User-Agent': 'RockZeroOS/1.0',
            },
          ).timeout(const Duration(seconds: 5));

          if (checkResponse.statusCode == 200) {
            final content = checkResponse.body;
            if (content.contains('#EXTM3U') &&
                (content.contains('#EXTINF') || content.contains('segment_'))) {
              debugPrint('[SecureHLS] Playlist ready after ${i + 1} seconds');
              playlistReady = true;
              break;
            }
          }
          debugPrint(
              '[SecureHLS] Playlist not ready (status=${checkResponse.statusCode}), waiting... (${i + 1}s)');
        } catch (e) {
          debugPrint(
              '[SecureHLS] Playlist check failed: $e, waiting... (${i + 1}s)');
        }

        await Future.delayed(const Duration(seconds: 1));
      }

      if (!playlistReady) {
        throw Exception('播放列表生成超时（已等待 60 秒），请检查服务器 ffmpeg 配置');
      }

      if (!mounted) return;

      // 创建 media_kit 播放器（mpv 后端，支持广泛的编解码器）
      setState(() => _loadingStatus = '正在初始化播放器...');
      debugPrint('[SecureHLS] Creating media_kit player with direct URL');

      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 64 * 1024 * 1024, // 64MB 缓冲
        ),
      );

      _videoController = VideoController(_player!);

      // 设置播放器事件监听
      _setupPlayerListeners();

      // 使用 media_kit 直接打开 HLS URL（mpv 原生支持 HLS）
      await _player!.open(
        Media(playlistUrl),
        play: true,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      debugPrint('[SecureHLS] Player initialized successfully (direct mode)');
    } catch (e, stack) {
      debugPrint('[SecureHLS] Error: $e');
      debugPrint('[SecureHLS] Stack: $stack');
      _setError('播放失败: ${_formatError(e.toString())}');
    }
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
            // SAE 安全标志 - MD3 chip style
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 14, color: Colors.greenAccent),
                  SizedBox(width: 4),
                  Text(
                    'SAE',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
          const Text(
            'SAE 握手 → HLS 分片 → 直接播放',
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
