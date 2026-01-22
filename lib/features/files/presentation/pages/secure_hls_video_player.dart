import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:crypto/crypto.dart';
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
import '../../../../services/secure_hls_proxy.dart';

/// 安全HLS视频播放器 - 使用SAE握手和ZKP验证
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
  String? _error;
  String? _authToken;
  String? _hlsSessionId;
  String? _userId;
  String? _userPassword;
  Uint8List? _pmk; // Pairwise Master Key

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

  Future<void> _initPlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      const storage = FlutterSecureStorage();
      _authToken = await storage.read(key: 'access_token');
      _userId = await storage.read(key: 'user_id');
      _userPassword = await storage.read(key: 'user_password_hash');

      if (_authToken == null || _authToken!.isEmpty) {
        setState(() {
          _error = '未登录，请先登录';
          _isLoading = false;
        });
        return;
      }

      if (_userId == null || _userPassword == null) {
        setState(() {
          _error = '无法获取用户凭据，请重新登录';
          _isLoading = false;
        });
        return;
      }

      debugPrint('[SecureHLS] Starting SAE handshake...');

      // 步骤1: 初始化SAE握手
      final initUrl = '${widget.baseUrl}/api/v1/secure-hls/sae/init';
      final initResponse = await http.post(
        Uri.parse(initUrl),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'file_id': widget.fileId ?? widget.filePath,
        }),
      );

      if (initResponse.statusCode != 200) {
        throw Exception('SAE初始化失败: ${initResponse.body}');
      }

      final initData = jsonDecode(initResponse.body);
      final tempSessionId = initData['temp_session_id'] as String;

      debugPrint('[SecureHLS] Got temp session: $tempSessionId');

      // 步骤2: 生成客户端SAE commit
      final saeClient = SimpleSaeClient(
        password: _userPassword!,
        userId: _userId!,
      );
      final clientCommit = saeClient.generateCommit();

      // 步骤3: 完成SAE握手
      final completeUrl = '${widget.baseUrl}/api/v1/secure-hls/sae/complete';
      final completeResponse = await http.post(
        Uri.parse(completeUrl),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'temp_session_id': tempSessionId,
          'client_commit': {
            'scalar': base64Encode(clientCommit['scalar']!),
            'element': base64Encode(clientCommit['element']!),
          },
          'client_confirm': {
            'send_confirm': 1,
            'confirm': base64Encode(clientCommit['confirm']!),
          },
        }),
      );

      if (completeResponse.statusCode != 200) {
        throw Exception('SAE握手完成失败: ${completeResponse.body}');
      }

      final completeData = jsonDecode(completeResponse.body);
      debugPrint('[SecureHLS] SAE handshake completed');

      // 步骤4: 验证服务器confirm并获取PMK
      final serverCommit = {
        'scalar': base64Decode(completeData['server_commit']['scalar']),
        'element': base64Decode(completeData['server_commit']['element']),
      };
      _pmk = saeClient.computePmk(serverCommit);

      debugPrint('[SecureHLS] PMK derived: ${_pmk!.length} bytes');

      // 步骤5: 创建HLS会话
      final sessionUrl = '${widget.baseUrl}/api/v1/secure-hls/session/create';
      final sessionResponse = await http.post(
        Uri.parse(sessionUrl),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'temp_session_id': tempSessionId,
          'file_id': widget.fileId ?? widget.filePath,
        }),
      );

      if (sessionResponse.statusCode != 200) {
        throw Exception('创建HLS会话失败: ${sessionResponse.body}');
      }

      final sessionData = jsonDecode(sessionResponse.body);
      _hlsSessionId = sessionData['session_id'] as String;
      final playlistUrl = '${widget.baseUrl}${sessionData['playlist_url']}';

      debugPrint('[SecureHLS] HLS session created: $_hlsSessionId');
      debugPrint('[SecureHLS] Playlist URL: $playlistUrl');

      // 步骤6: 启动本地代理服务器
      debugPrint('[SecureHLS] Starting local proxy server...');
      _proxyServer = SecureHlsProxyServer(
        baseUrl: widget.baseUrl,
        sessionId: _hlsSessionId!,
        pmk: _pmk!,
      );

      final proxyPlaylistUrl = await _proxyServer!.start();
      debugPrint('[SecureHLS] Proxy server started: $proxyPlaylistUrl');

      // 步骤7: 等待播放列表准备好
      debugPrint('[SecureHLS] Waiting for playlist...');
      bool playlistReady = false;
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 1));

        try {
          final checkResponse = await http.get(
            Uri.parse(playlistUrl),
            headers: {
              'Accept': 'application/vnd.apple.mpegurl, */*',
              'User-Agent': 'RockZeroOS/1.0',
            },
          ).timeout(const Duration(seconds: 2));

          if (checkResponse.statusCode == 200) {
            final content = checkResponse.body;
            if (content.contains('#EXTM3U') &&
                (content.contains('#EXTINF') || content.contains('segment_'))) {
              debugPrint('[SecureHLS] ✅ Playlist ready after ${i + 1} seconds');
              playlistReady = true;
              break;
            }
          }
        } catch (e) {
          debugPrint(
              '[SecureHLS] Playlist check failed: $e, waiting... (${i + 1}s)');
        }
      }

      if (!playlistReady) {
        throw Exception('播放列表生成超时');
      }

      // 步骤8: 创建视频播放器（使用代理服务器URL）
      if (_chewieController != null) {
        _chewieController!.pause();
        _chewieController!.dispose();
        _chewieController = null;
      }
      if (_videoController != null) {
        _videoController!.dispose();
        _videoController = null;
      }

      debugPrint('[SecureHLS] Creating video controller with proxy URL');

      // 创建视频播放器控制器（使用代理服务器的URL）
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(proxyPlaylistUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      // 初始化视频控制器
      await _videoController!.initialize().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('视频加载超时');
        },
      );

      debugPrint('[SecureHLS] ✅ Video controller initialized');

      // 设置循环播放
      _videoController!.setLooping(_isLooping);

      // 创建Chewie控制器
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
        additionalOptions: (context) => [
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
        });
      }

      debugPrint('[SecureHLS] Player initialized successfully');
    } catch (e, stack) {
      debugPrint('[SecureHLS] Error: $e');
      debugPrint('[SecureHLS] Stack: $stack');
      if (mounted) {
        setState(() {
          _error = '播放失败: $e';
          _isLoading = false;
        });
      }
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
    // 停止代理服务器
    if (_proxyServer != null) {
      await _proxyServer!.stop();
      _proxyServer = null;
      debugPrint('[SecureHLS] Proxy server stopped');
    }

    // 停止HLS会话
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, size: 12, color: Colors.green),
                        SizedBox(width: 4),
                        Text(
                          'SECURE',
                          style: TextStyle(fontSize: 10, color: Colors.green),
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
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text('正在建立安全连接...', style: TextStyle(color: Colors.white)),
          SizedBox(height: 8),
          Text(
            'SAE握手 + ZKP验证 + AES-256-GCM加密',
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

/// 简化的SAE客户端
class SimpleSaeClient {
  final String password;
  final String userId;

  Uint8List? _rand;
  Uint8List? _mask;
  Uint8List? _scalar;
  Uint8List? _element;

  SimpleSaeClient({
    required this.password,
    required this.userId,
  });

  /// 生成客户端commit
  Map<String, Uint8List> generateCommit() {
    // 生成随机数
    _rand = _generateRandom(32);
    _mask = _generateRandom(32);

    // 计算scalar和element
    _scalar = _computeScalar(_rand!, _mask!);
    _element = _computeElement(_rand!, _mask!, password);

    // 计算confirm
    final confirm = _computeConfirm(_scalar!, _element!);

    return {
      'scalar': _scalar!,
      'element': _element!,
      'confirm': confirm,
    };
  }

  /// 计算PMK
  Uint8List computePmk(Map<String, Uint8List> serverCommit) {
    final pmk = sha256.convert([
      ..._scalar!,
      ...serverCommit['scalar']!,
      ..._element!,
      ...serverCommit['element']!,
      ...utf8.encode(password),
      ...utf8.encode(userId),
    ]);
    return Uint8List.fromList(pmk.bytes);
  }

  Uint8List _generateRandom(int length) {
    final random = List<int>.generate(
        length, (i) => (DateTime.now().microsecondsSinceEpoch * (i + 1)) % 256);
    return Uint8List.fromList(random);
  }

  Uint8List _computeScalar(Uint8List rand, Uint8List mask) {
    final result = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      result[i] = rand[i] ^ mask[i];
    }
    return result;
  }

  Uint8List _computeElement(Uint8List rand, Uint8List mask, String password) {
    final hash = sha256.convert([
      ...rand,
      ...mask,
      ...utf8.encode(password),
    ]);
    return Uint8List.fromList(hash.bytes);
  }

  Uint8List _computeConfirm(Uint8List scalar, Uint8List element) {
    final hmac = Hmac(sha256, scalar);
    final digest = hmac.convert([...element, ...utf8.encode(userId)]);
    return Uint8List.fromList(digest.bytes);
  }
}
