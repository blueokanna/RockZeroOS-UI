import 'dart:async';
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
import '../../../../services/sae_handshake_service.dart';
import '../../../../services/secure_hls_proxy.dart';

class SecureStreamStats {
  int bytesReceived = 0;
  int bytesSent = 0;
  int segmentsLoaded = 0;
  int segmentsDecrypted = 0;
  DateTime? sessionStartTime;
  String encryptionMethod = 'AES-256-GCM';
  String keyExchange = 'SAE (WPA3)';
  bool replayProtection = true;
  bool requestSigning = true;

  String get formattedBytesReceived => _formatBytes(bytesReceived);
  String get formattedBytesSent => _formatBytes(bytesSent);
  String get sessionDuration {
    if (sessionStartTime == null) return '0s';
    final duration = DateTime.now().difference(sessionStartTime!);
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    }
    return '${duration.inSeconds}s';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
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
  }) : assert(filePath != null || fileId != null,
            'Either filePath or fileId is required');

  @override
  ConsumerState<SecureHlsVideoPlayer> createState() =>
      _SecureHlsVideoPlayerState();
}

class _SecureHlsVideoPlayerState extends ConsumerState<SecureHlsVideoPlayer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  SecureHlsProxyServer? _proxyServer;

  bool _isLoading = true;
  bool _isInitializing = false;
  String _loadingStatus = '初始化...';
  double _loadingProgress = 0;
  String? _error;
  String? _authToken;
  String? _hlsSessionId;
  String? _userId;
  String? _userPassword;
  Uint8List? _pmk;

  bool _isDownloading = false;
  double _downloadProgress = 0;
  bool _isLooping = false;
  bool _isDisposed = false;

  final SecureStreamStats _stats = SecureStreamStats();
  Timer? _statsUpdateTimer;

  late Color _primaryColor;

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
    WakelockPlus.enable();
    _stats.sessionStartTime = DateTime.now();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _primaryColor = Theme.of(context).colorScheme.primary;
    if (!_isInitializing && _videoController == null && _error == null) {
      _isInitializing = true;
      _initPlayer();
    }
  }

  Future<void> _initPlayer() async {
    if (_isDisposed) return;

    try {
      setState(() {
        _isLoading = true;
        _loadingStatus = '正在获取凭据...';
        _loadingProgress = 0.1;
        _error = null;
      });

      const storage = FlutterSecureStorage();
      _authToken = await storage.read(key: 'access_token');
      _userId = await storage.read(key: 'user_id');
      _userPassword = await storage.read(key: 'user_password_hash');

      debugPrint(
          '[SecureHLS] Auth token: ${_authToken != null ? "present (${_authToken!.length} chars)" : "null"}');
      debugPrint('[SecureHLS] User ID: $_userId');
      debugPrint(
          '[SecureHLS] Password hash: ${_userPassword != null ? "present (${_userPassword!.length} chars)" : "null"}');

      if (_authToken == null || _authToken!.isEmpty) {
        if (mounted && !_isDisposed) {
          setState(() {
            _error = '未登录，请先登录';
            _isLoading = false;
          });
        }
        return;
      }

      if (_userId == null || _userPassword == null) {
        if (mounted && !_isDisposed) {
          setState(() {
            _error = '无法获取用户凭据，请重新登录';
            _isLoading = false;
          });
        }
        return;
      }

      if (_isDisposed) return;

      setState(() {
        _loadingStatus = '正在建立SAE安全握手...';
        _loadingProgress = 0.2;
      });

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

      setState(() {
        _loadingStatus = '正在启动安全代理...';
        _loadingProgress = 0.4;
      });

      _proxyServer = SecureHlsProxyServer(
        baseUrl: widget.baseUrl,
        sessionId: _hlsSessionId!,
        pmk: _pmk!,
        jwtToken: _authToken ?? '',
        onSegmentLoaded: _onSegmentLoaded,
      );

      final proxyPlaylistUrl = await _proxyServer!.start();
      debugPrint('[SecureHLS] Proxy server started: $proxyPlaylistUrl');

      if (_isDisposed) return;

      setState(() {
        _loadingStatus = '正在初始化播放器...';
        _loadingProgress = 0.7;
      });

      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(proxyPlaylistUrl),
        httpHeaders: {
          'Connection': 'keep-alive',
        },
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      _videoController!.addListener(_onVideoControllerUpdate);

      debugPrint(
          '[SecureHLS] Initializing video controller with URL: $proxyPlaylistUrl');

      try {
        await _videoController!.initialize().timeout(
          const Duration(seconds: 120),
          onTimeout: () {
            throw TimeoutException('视频加载超时，请检查网络连接');
          },
        );
      } catch (e) {
        debugPrint('[SecureHLS] Video initialization error: $e');
        // Check if it's a decryption error
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('source') ||
            errorStr.contains('decrypt') ||
            errorStr.contains('crypto') ||
            errorStr.contains('tag')) {
          throw Exception('解密失败，密钥可能不匹配。请重新登录后再试。');
        }
        rethrow;
      }

      if (_isDisposed) {
        _videoController?.dispose();
        return;
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
        progressIndicatorDelay: Duration.zero,
        additionalOptions: (context) => [
          OptionItem(
            onTap: (_) => _toggleLooping(),
            iconData: _isLooping ? Icons.repeat_one : Icons.repeat,
            title: _isLooping ? '循环: 开' : '循环: 关',
          ),
        ],
        errorBuilder: (_, errorMessage) => _buildInlineError(errorMessage),
        materialProgressColors: ChewieProgressColors(
          playedColor: _primaryColor,
          handleColor: _primaryColor,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
      );

      _statsUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && !_isDisposed) setState(() {});
      });

      if (mounted && !_isDisposed) {
        setState(() {
          _isLoading = false;
          _loadingProgress = 1.0;
        });
      }

      debugPrint('[SecureHLS] Player initialized successfully');
    } catch (e, stack) {
      debugPrint('[SecureHLS] Error: $e');
      debugPrint('[SecureHLS] Stack: $stack');
      if (mounted && !_isDisposed) {
        String errorMessage = '播放失败';
        final errorStr = e.toString().toLowerCase();

        if (errorStr.contains('sae') || errorStr.contains('handshake')) {
          errorMessage = 'SAE安全握手失败，请检查密码是否正确';
        } else if (errorStr.contains('timeout')) {
          errorMessage = '连接超时，请检查网络连接';
        } else if (errorStr.contains('decrypt') ||
            errorStr.contains('crypto')) {
          errorMessage = '解密失败，密钥可能不匹配';
        } else if (errorStr.contains('network') ||
            errorStr.contains('connection')) {
          errorMessage = '网络错误，请检查服务器连接';
        } else if (errorStr.contains('401') ||
            errorStr.contains('unauthorized')) {
          errorMessage = '认证失败，请重新登录';
        } else if (errorStr.contains('404') || errorStr.contains('not found')) {
          errorMessage = '文件不存在或已被删除';
        } else {
          errorMessage = '播放失败: $e';
        }

        setState(() {
          _error = errorMessage;
          _isLoading = false;
        });
      }
    } finally {
      _isInitializing = false;
    }
  }

  void _onVideoControllerUpdate() {
    if (_videoController == null || !mounted || _isDisposed) return;

    final value = _videoController!.value;

    if (value.hasError) {
      debugPrint('[SecureHLS] Video error: ${value.errorDescription}');
    }
  }

  void _onSegmentLoaded(int bytes, bool decrypted) {
    _stats.bytesReceived += bytes;
    _stats.segmentsLoaded++;
    if (decrypted) {
      _stats.segmentsDecrypted++;
    }
  }

  void _toggleLooping() {
    setState(() {
      _isLooping = !_isLooping;
    });
    _videoController?.setLooping(_isLooping);
    _chewieController?.setLooping(_isLooping);
  }

  void _showSecurityInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
              _buildSecurityInfoSection(
                '加密方式',
                Icons.lock,
                [
                  _buildInfoRow('算法', _stats.encryptionMethod),
                  _buildInfoRow('密钥交换', _stats.keyExchange),
                  _buildInfoRow(
                      '重放保护', _stats.replayProtection ? '已启用' : '未启用'),
                  _buildInfoRow('请求签名', _stats.requestSigning ? '已启用' : '未启用'),
                ],
              ),
              const Divider(height: 24),
              _buildSecurityInfoSection(
                '会话信息',
                Icons.vpn_key,
                [
                  _buildInfoRow(
                      '会话ID', _hlsSessionId?.substring(0, 8) ?? 'N/A'),
                  _buildInfoRow('会话时长', _stats.sessionDuration),
                ],
              ),
              const Divider(height: 24),
              _buildSecurityInfoSection(
                '流量统计',
                Icons.data_usage,
                [
                  _buildInfoRow('接收数据', _stats.formattedBytesReceived),
                  _buildInfoRow('发送数据', _stats.formattedBytesSent),
                  _buildInfoRow('已加载片段', '${_stats.segmentsLoaded}'),
                  _buildInfoRow('已解密片段', '${_stats.segmentsDecrypted}'),
                ],
              ),
              const Divider(height: 24),
              _buildSecurityInfoSection(
                '安全特性',
                Icons.verified_user,
                [
                  _buildSecurityFeature('端到端加密', true),
                  _buildSecurityFeature('前向保密', true),
                  _buildSecurityFeature('防中间人攻击', true),
                  _buildSecurityFeature('防重放攻击', true),
                ],
              ),
            ],
          ),
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

  Widget _buildSecurityInfoSection(
      String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
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

  Widget _buildSecurityFeature(String feature, bool enabled) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: enabled ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(feature),
        ],
      ),
    );
  }

  Widget _buildInlineError(String errorMessage) {
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
  }

  Future<void> _retry() async {
    await _cleanupAll();
    _isInitializing = false;
    await _initPlayer();
  }

  Future<void> _cleanupAll() async {
    debugPrint('[SecureHLS] Starting cleanup...');

    _statsUpdateTimer?.cancel();
    _statsUpdateTimer = null;

    // Stop video controller first
    try {
      _videoController?.removeListener(_onVideoControllerUpdate);
      await _videoController?.pause();
    } catch (e) {
      debugPrint('[SecureHLS] Error pausing video: $e');
    }

    // Dispose chewie controller
    try {
      _chewieController?.dispose();
    } catch (e) {
      debugPrint('[SecureHLS] Error disposing chewie: $e');
    }
    _chewieController = null;

    // Dispose video controller
    try {
      _videoController?.dispose();
    } catch (e) {
      debugPrint('[SecureHLS] Error disposing video controller: $e');
    }
    _videoController = null;

    // Stop proxy server
    if (_proxyServer != null) {
      try {
        await _proxyServer!.stop();
      } catch (e) {
        debugPrint('[SecureHLS] Error stopping proxy: $e');
      }
      _proxyServer = null;
    }

    // Stop HLS session on server
    if (_hlsSessionId != null && _authToken != null) {
      try {
        await http.post(
          Uri.parse('${widget.baseUrl}/api/v1/secure-hls/$_hlsSessionId/stop'),
          headers: {'Authorization': 'Bearer $_authToken'},
        ).timeout(const Duration(seconds: 5));
        debugPrint('[SecureHLS] Server session stopped');
      } catch (e) {
        debugPrint('[SecureHLS] Failed to stop server session: $e');
      }
    }
    _hlsSessionId = null;
    _pmk = null;

    debugPrint('[SecureHLS] Cleanup completed');
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cleanupAll();
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
      if (mounted && !_isDisposed) {
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
    if (mounted) {
      ref.read(bottomNavVisibleProvider.notifier).show();
    }
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
            if (!_isLoading && _error == null)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _showSecurityInfoDialog,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, size: 14, color: Colors.green),
                        SizedBox(width: 6),
                        Text(
                          'SECURE',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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
            if (_chewieController != null && !_isLoading && _error == null)
              Chewie(controller: _chewieController!),
            if (_isLoading) _buildLoading(),
            if (_error != null && !_isLoading) _buildError(),
            if (_isDownloading) _buildDownloadProgress(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                value: _loadingProgress > 0 ? _loadingProgress : null,
                color: Colors.green,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _loadingStatus,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _loadingProgress,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${(_loadingProgress * 100).toInt()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildSecurityChip('SAE握手', _loadingProgress >= 0.3),
                _buildSecurityChip('AES-256-GCM', _loadingProgress >= 0.4),
                _buildSecurityChip('安全代理', _loadingProgress >= 0.5),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityChip(String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? Colors.green.withValues(alpha: 0.2)
            : Colors.grey.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? Colors.green.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle : Icons.hourglass_empty,
            size: 12,
            color: active ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: active ? Colors.green : Colors.grey,
            ),
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
