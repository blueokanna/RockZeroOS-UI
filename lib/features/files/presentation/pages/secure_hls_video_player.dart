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
import '../../../../services/secure_hls_proxy.dart';

class SecureStreamStats {
  ProxyStreamStats? _proxyStats;
  DateTime? sessionStartTime;
  String encryptionMethod = 'AES-256-GCM';
  String keyExchange = 'SAE (WPA3)';

  void setProxyStats(ProxyStreamStats stats) => _proxyStats = stats;

  int get networkBytesReceived => _proxyStats?.networkBytesReceived ?? 0;
  int get decryptedBytesTotal => _proxyStats?.decryptedBytesTotal ?? 0;
  int get segmentsLoadedFromNetwork =>
      _proxyStats?.segmentsLoadedFromNetwork ?? 0;
  int get segmentsServedFromCache => _proxyStats?.segmentsServedFromCache ?? 0;
  int get segmentsDecrypted => _proxyStats?.segmentsDecrypted ?? 0;
  int get failedRequests => _proxyStats?.failedRequests ?? 0;
  double get cacheHitRate => _proxyStats?.cacheHitRate ?? 0;

  String get formattedNetworkBytes => _formatBytes(networkBytesReceived);
  String get formattedDecryptedBytes => _formatBytes(decryptedBytesTotal);

  String get sessionDuration {
    if (sessionStartTime == null) return '0s';
    final d = DateTime.now().difference(sessionStartTime!);
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

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
  }) : assert(filePath != null || fileId != null);

  @override
  ConsumerState<SecureHlsVideoPlayer> createState() =>
      _SecureHlsVideoPlayerState();
}

class _SecureHlsVideoPlayerState extends ConsumerState<SecureHlsVideoPlayer>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _videoController;
  SecureHlsProxyServer? _proxyServer;

  bool _isLoading = true;
  bool _isInitializing = false;
  String _loadingStatus = '初始化中...';
  double _loadingProgress = 0;
  String? _error;
  String? _authToken;
  String? _hlsSessionId;
  String? _userId;
  String? _userPassword;
  Uint8List? _pmk;

  bool _isDownloading = false;
  double _downloadProgress = 0;
  bool _isDisposed = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  Timer? _uiUpdateTimer;

  final SecureStreamStats _stats = SecureStreamStats();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isSeeking = false;

  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterFullscreen();
    WakelockPlus.enable();
    _stats.sessionStartTime = DateTime.now();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _player?.pause();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitializing && _player == null && _error == null) {
      _isInitializing = true;
      _initPlayer();
    }
  }

  Future<void> _initPlayer() async {
    if (_isDisposed) return;

    try {
      _updateLoading('正在获取凭据...', 0.1);

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
      if (_isDisposed) return;

      _updateLoading('正在建立安全连接...', 0.2);

      final handshakeService = SaeHandshakeService(
        baseUrl: widget.baseUrl,
        jwtToken: _authToken!,
      );
      final filePath = widget.filePath ?? '';

      final (sessionId, pmk) = await handshakeService.performHandshake(
        filePath: filePath,
        password: _userPassword!,
        userId: _userId!,
      );

      if (_isDisposed) return;
      _hlsSessionId = sessionId;
      _pmk = pmk;

      _updateLoading('正在启动安全代理...', 0.4);

      _proxyServer = SecureHlsProxyServer(
        baseUrl: widget.baseUrl,
        sessionId: _hlsSessionId!,
        pmk: _pmk!,
        jwtToken: _authToken ?? '',
      );
      _stats.setProxyStats(_proxyServer!.stats);

      final proxyPlaylistUrl = await _proxyServer!.start();
      if (_isDisposed) return;

      _updateLoading('正在初始化播放器...', 0.6);

      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 128 * 1024 * 1024,
        ),
      );

      _videoController = VideoController(
        _player!,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );

      _subscriptions.add(_player!.stream.playing.listen((p) {
        _isPlaying = p;
        if (mounted && !_isDisposed) setState(() {});
      }));

      _subscriptions.add(_player!.stream.position.listen((p) {
        if (!_isSeeking) _position = p;
      }));

      _subscriptions.add(_player!.stream.duration.listen((d) {
        _duration = d;
      }));

      _subscriptions.add(_player!.stream.buffering.listen((b) {
        _isBuffering = b;
        if (mounted && !_isDisposed) setState(() {});
      }));

      _updateLoading('正在加载视频...', 0.8);

      await _player!.open(Media(proxyPlaylistUrl), play: true);
      if (_isDisposed) return;

      _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted && !_isDisposed) setState(() {});
      });

      _startHideControlsTimer();

      if (mounted && !_isDisposed) {
        setState(() {
          _isLoading = false;
          _loadingProgress = 1.0;
        });
      }
    } catch (e) {
      _setError(_parseError(e.toString()));
    } finally {
      _isInitializing = false;
    }
  }

  void _updateLoading(String status, double progress) {
    if (mounted && !_isDisposed) {
      setState(() {
        _loadingStatus = status;
        _loadingProgress = progress;
      });
    }
  }

  void _setError(String error) {
    if (mounted && !_isDisposed) {
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  String _parseError(String e) {
    final lower = e.toLowerCase();
    if (lower.contains('key') || lower.contains('decrypt')) return '密钥错误，请重新登录';
    if (lower.contains('sae') ||
        lower.contains('handshake') ||
        lower.contains('verification')) {
      return 'SAE安全握手失败，请检查密码是否正确';
    }
    if (lower.contains('timeout')) return '连接超时，请检查网络';
    if (lower.contains('network') || lower.contains('connection'))
      return '网络错误，请检查连接';
    if (lower.contains('401') || lower.contains('unauthorized'))
      return '认证失败，请重新登录';
    if (lower.contains('404') || lower.contains('not found')) return '文件不存在';
    if (lower.contains('500')) return '服务器错误，请稍后重试';
    return '播放失败，请重试';
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isDisposed && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onTapVideo() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  void _togglePlayPause() {
    if (_player == null) return;
    if (_isPlaying) {
      _player!.pause();
    } else {
      _player!.play();
      _startHideControlsTimer();
    }
  }

  void _seekTo(Duration position) {
    if (_player == null || _duration == Duration.zero) return;

    final clampedPosition = Duration(
      milliseconds: position.inMilliseconds.clamp(0, _duration.inMilliseconds),
    );

    _isSeeking = true;
    _position = clampedPosition;
    setState(() {});

    final targetSegment = (clampedPosition.inSeconds / 6).floor();
    _proxyServer?.prefetchAroundSegment(targetSegment);

    _player!.seek(clampedPosition).then((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _isSeeking = false;
      });
    });
  }

  void _seekForward() {
    final newPos = _position + const Duration(seconds: 10);
    _seekTo(newPos < _duration ? newPos : _duration);
  }

  void _seekBackward() {
    final newPos = _position - const Duration(seconds: 10);
    _seekTo(newPos > Duration.zero ? newPos : Duration.zero);
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}';
    }
    return '${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds.remainder(60))}';
  }

  void _showSecurityInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.security, color: Colors.green.shade400),
            const SizedBox(width: 12),
            const Text('安全连接信息'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoSection('加密方式', Icons.lock, [
                _infoRow('算法', _stats.encryptionMethod),
                _infoRow('密钥交换', _stats.keyExchange),
                _infoRow('重放保护', '已启用'),
              ]),
              const Divider(height: 24),
              _infoSection('流量统计', Icons.data_usage, [
                _infoRow('网络接收', _stats.formattedNetworkBytes),
                _infoRow('解密数据', _stats.formattedDecryptedBytes),
                _infoRow('网络加载', '${_stats.segmentsLoadedFromNetwork} 段'),
                _infoRow('缓存命中', '${_stats.segmentsServedFromCache} 段'),
                _infoRow('命中率',
                    '${(_stats.cacheHitRate * 100).toStringAsFixed(1)}%'),
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Widget _infoSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Future<void> _retry() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _loadingProgress = 0;
      _loadingStatus = '正在重试...';
    });
    await _cleanup();
    _isInitializing = false;
    await _initPlayer();
  }

  Future<void> _cleanup() async {
    _uiUpdateTimer?.cancel();
    _hideControlsTimer?.cancel();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    _videoController = null;

    try {
      await _proxyServer?.stop();
    } catch (_) {}
    _proxyServer = null;

    if (_hlsSessionId != null && _authToken != null) {
      try {
        await http.post(
          Uri.parse('${widget.baseUrl}/api/v1/secure-hls/$_hlsSessionId/stop'),
          headers: {'Authorization': 'Bearer $_authToken'},
        ).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    _hlsSessionId = null;
    _pmk = null;
  }

  void _restoreNavigation() {
    // 恢复系统 UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 恢复底部导航栏
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(bottomNavVisibleProvider.notifier).show();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _cleanup();
    _restoreNavigation();
    WakelockPlus.disable();
    super.dispose();
  }

  void _enterFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky,
        overlays: []);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed) {
        ref.read(bottomNavVisibleProvider.notifier).hide();
      }
    });
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

      if (downloadDir == null) throw Exception('无法获取下载目录');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final downloadUrl = widget.filePath != null
          ? '${widget.baseUrl}/api/v1/filemanager/download?path=${Uri.encodeComponent(widget.filePath!)}'
          : '${widget.baseUrl}/api/v1/files/${widget.fileId}/download';

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
          const SnackBar(content: Text('下载失败'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _restoreNavigation();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _onTapVideo,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_videoController != null && !_isLoading && _error == null)
                Video(
                  controller: _videoController!,
                  fit: BoxFit.contain,
                  fill: Colors.black,
                ),
              if (_isLoading) _buildLoading(),
              if (_error != null) _buildError(),
              if (_isBuffering && !_isLoading && _error == null)
                const Center(
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 3),
                ),
              if (!_isLoading && _error == null) _buildControls(),
              if (_isDownloading) _buildDownloadProgress(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
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
                Color.fromRGBO(0, 0, 0, 0.7),
                Colors.transparent,
                Colors.transparent,
                Color.fromRGBO(0, 0, 0, 0.7),
              ],
              stops: [0.0, 0.2, 0.8, 1.0],
            ),
          ),
          child: Column(
            children: [
              _buildTopBar(),
              const Spacer(),
              _buildCenterControls(),
              const Spacer(),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              onPressed: () {
                _restoreNavigation();
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.fileName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.security, color: Colors.green, size: 24),
              onPressed: _showSecurityInfoDialog,
              tooltip: '安全连接信息',
            ),
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white, size: 24),
              onPressed: _downloadFile,
              tooltip: '下载视频',
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
        IconButton(
          icon: const Icon(Icons.replay_10, color: Colors.white, size: 40),
          onPressed: _seekBackward,
        ),
        const SizedBox(width: 32),
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: Color.fromRGBO(255, 255, 255, 0.2),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 48,
            ),
            onPressed: _togglePlayPause,
          ),
        ),
        const SizedBox(width: 32),
        IconButton(
          icon: const Icon(Icons.forward_10, color: Colors.white, size: 40),
          onPressed: _seekForward,
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: Colors.blue,
                inactiveTrackColor: const Color.fromRGBO(255, 255, 255, 0.3),
                thumbColor: Colors.blue,
                overlayColor: const Color.fromRGBO(33, 150, 243, 0.3),
              ),
              child: Slider(
                value: _duration.inMilliseconds > 0
                    ? _position.inMilliseconds
                        .toDouble()
                        .clamp(0, _duration.inMilliseconds.toDouble())
                    : 0,
                min: 0,
                max: _duration.inMilliseconds > 0
                    ? _duration.inMilliseconds.toDouble()
                    : 1,
                onChanged: (value) {
                  _seekTo(Duration(milliseconds: value.toInt()));
                },
                onChangeStart: (_) {
                  _isSeeking = true;
                  _hideControlsTimer?.cancel();
                },
                onChangeEnd: (_) {
                  _isSeeking = false;
                  _startHideControlsTimer();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(_position),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                  Row(
                    children: [
                      Icon(Icons.lock, color: Colors.green.shade400, size: 14),
                      const SizedBox(width: 4),
                      Text('AES-256-GCM',
                          style: TextStyle(
                              color: Colors.green.shade400, fontSize: 11)),
                    ],
                  ),
                  Text(_formatDuration(_duration),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                value: _loadingProgress > 0 ? _loadingProgress : null,
                strokeWidth: 4,
                color: Colors.blue,
                backgroundColor: const Color.fromRGBO(255, 255, 255, 0.2),
              ),
            ),
            const SizedBox(height: 24),
            Text(_loadingStatus,
                style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              '${(_loadingProgress * 100).toInt()}%',
              style: const TextStyle(
                  color: Color.fromRGBO(255, 255, 255, 0.7), fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.security, color: Colors.green.shade400, size: 16),
                const SizedBox(width: 8),
                Text('正在建立安全加密连接...',
                    style:
                        TextStyle(color: Colors.green.shade400, fontSize: 13)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade400, size: 64),
              const SizedBox(height: 24),
              Text(
                _error ?? '未知错误',
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      _restoreNavigation();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('返回'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadProgress() {
    return Positioned(
      bottom: 100,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(0, 0, 0, 0.8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('正在下载...',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 12),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  value: _downloadProgress,
                  backgroundColor: const Color.fromRGBO(255, 255, 255, 0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_downloadProgress * 100).toInt()}%',
                style: const TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.7), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
