import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:thirds/blake3.dart' as blake3;
import 'package:video_player/video_player.dart';

import 'bulletproofs_ffi.dart';
import 'sae_client_curve25519.dart';
import 'secure_hls_proxy.dart';

/// 安全 HLS 播放器
///
/// 实现完整的安全视频播放流程:
/// 1. SAE 握手: WPA3-SAE 密钥交换，建立共享密钥 (PMK)
/// 2. 会话创建: 使用 PMK 创建加密 HLS 会话
/// 3. 本地代理: 启动本地代理服务器拦截 HLS 请求
/// 4. 视频解密: 使用 AES-256-GCM 解密视频段
/// 5. ZKP 证明: 为每个视频段生成 Bulletproofs 证明（可选）
class SecureHlsPlayer {
  final String baseUrl;
  final String jwtToken;

  Uint8List? _pmk;
  String? _sessionId;
  String? _filePath;

  HlsEncryptor? _encryptor;
  SecureHlsProxyServer? _proxy;
  BulletproofsService? _bulletproofsService;

  VideoPlayerController? _controller;

  SecureHlsPlayer({
    required this.baseUrl,
    required this.jwtToken,
  });

  /// 初始化 SAE 握手并创建 HLS 会话
  Future<void> initializeSaeHandshake(
    String userId,
    String password, {
    String? fileId,
    String? filePath,
  }) async {
    if (fileId == null && filePath == null) {
      throw ArgumentError('Either fileId or filePath must be provided');
    }

    debugPrint('[SecureHLS] Starting SAE handshake for user: $userId');

    // 初始化 Bulletproofs 服务
    _bulletproofsService = BulletproofsService(
      baseUrl: baseUrl,
      jwtToken: jwtToken,
    );
    await _bulletproofsService!.initialize();

    // 生成设备 ID（使用 BLAKE3）
    final deviceIdSelf = Uint8List.fromList(
      blake3.blake3(utf8.encode(userId), 32),
    );
    final deviceIdPeer = Uint8List.fromList(
      blake3.blake3(utf8.encode('rockzero-server-device-id'), 32),
    );

    debugPrint(
        '[SecureHLS] Client device ID: ${_bytesToHex(deviceIdSelf.sublist(0, 8))}...');

    // 创建 SAE 客户端
    final saeClient = SaeClientCurve25519(
      password: Uint8List.fromList(utf8.encode(password)),
      deviceIdSelf: deviceIdSelf,
      deviceIdPeer: deviceIdPeer,
    );

    // 生成客户端 commit
    final clientCommit = saeClient.generateCommit();

    // 步骤 1: 初始化 SAE 握手
    debugPrint('[SecureHLS] Step 1: Initializing SAE handshake...');
    final initResponse = await _httpPost(
      '$baseUrl/api/v1/secure-hls/sae/init',
      body: {
        'file_id': fileId,
        'file_path': filePath,
      },
    );

    final tempSessionId = initResponse['temp_session_id'] as String;
    _filePath = initResponse['file_path'] as String?;
    debugPrint('[SecureHLS] Temp session: $tempSessionId');

    // 步骤 2: 发送客户端 commit
    debugPrint('[SecureHLS] Step 2: Sending client commit...');
    final commitResponse = await _httpPost(
      '$baseUrl/api/v1/secure-hls/sae/commit',
      body: {
        'temp_session_id': tempSessionId,
        'client_commit': clientCommit,
      },
    );

    final serverCommit =
        commitResponse['server_commit'] as Map<String, dynamic>;
    saeClient.processCommit(serverCommit);

    // 步骤 3: 发送客户端 confirm
    debugPrint('[SecureHLS] Step 3: Sending client confirm...');
    final clientConfirm = saeClient.generateConfirm();
    final confirmResponse = await _httpPost(
      '$baseUrl/api/v1/secure-hls/sae/confirm',
      body: {
        'temp_session_id': tempSessionId,
        'client_confirm': clientConfirm,
      },
    );

    final serverConfirm =
        confirmResponse['server_confirm'] as Map<String, dynamic>;
    saeClient.verifyConfirm(serverConfirm);

    // 获取 PMK
    _pmk = saeClient.getPmk();
    debugPrint('[SecureHLS] ✅ SAE handshake completed');
    debugPrint(
        '[SecureHLS] PMK (first 8 bytes): ${_bytesToHex(_pmk!.sublist(0, 8))}');

    // 步骤 4: 创建 HLS 会话
    debugPrint('[SecureHLS] Step 4: Creating HLS session...');
    final sessionResponse = await _httpPost(
      '$baseUrl/api/v1/secure-hls/session/create',
      body: {
        'temp_session_id': tempSessionId,
        'file_id': fileId,
        'file_path': filePath,
      },
    );

    _sessionId = sessionResponse['session_id'] as String;
    debugPrint('[SecureHLS] ✅ HLS session created: $_sessionId');

    // 初始化加密器（使用 session_id 派生密钥）
    _encryptor = HlsEncryptor(sessionId: _sessionId!, pmk: _pmk!);
  }

  /// 为视频段创建 ZKP 证明
  Future<VideoStreamProof?> createSegmentProof(
    int segmentIndex,
    Uint8List content,
  ) async {
    if (_bulletproofsService == null || _sessionId == null) {
      debugPrint('[SecureHLS] Cannot create proof: service not initialized');
      return null;
    }

    return _bulletproofsService!.createVideoStreamProof(
      sessionId: _sessionId!,
      segmentIndex: segmentIndex,
      content: content,
    );
  }

  /// 开始视频播放
  Future<VideoPlayerController> play() async {
    if (_sessionId == null || _pmk == null) {
      throw StateError('SAE handshake not completed');
    }

    if (_encryptor == null) {
      throw StateError('Encryptor not initialized');
    }

    // 创建本地代理服务器
    _proxy ??= SecureHlsProxyServer(
      baseUrl: baseUrl,
      sessionId: _sessionId!,
      pmk: _pmk!,
      jwtToken: jwtToken,
    );

    // 启动代理并获取本地播放列表 URL
    final proxyPlaylistUrl = await _proxy!.start();

    // 创建视频播放器
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(proxyPlaylistUrl),
      httpHeaders: const {},
    );

    await _controller!.initialize();

    debugPrint('[SecureHLS] ✅ Video player initialized');
    debugPrint('[SecureHLS] Proxy URL: $proxyPlaylistUrl');

    return _controller!;
  }

  /// 停止播放并清理资源
  Future<void> stop() async {
    // 停止本地代理
    await _proxy?.stop();
    _proxy = null;

    // 释放视频播放器
    await _controller?.dispose();
    _controller = null;

    // 通知服务器停止会话
    if (_sessionId != null) {
      try {
        await _httpPost(
          '$baseUrl/api/v1/secure-hls/$_sessionId/stop',
          body: {},
        );
        debugPrint('[SecureHLS] Session stopped on server');
      } catch (e) {
        debugPrint('[SecureHLS] Failed to stop session on server: $e');
      }
    }

    // 清除状态
    _sessionId = null;
    _pmk = null;
    _encryptor = null;
    _bulletproofsService = null;
    _filePath = null;

    debugPrint('[SecureHLS] ✅ Player stopped and cleaned up');
  }

  /// HTTP POST 请求
  Future<Map<String, dynamic>> _httpPost(
    String url, {
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse(url);
    final request = await HttpClient().postUrl(uri);

    request.headers.contentType = ContentType.json;
    if (jwtToken.isNotEmpty) {
      request.headers.add('Authorization', 'Bearer $jwtToken');
    }

    request.write(jsonEncode(body));
    final response = await request.close();

    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $responseBody');
    }

    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  /// 字节转十六进制字符串
  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // Getters
  VideoPlayerController? get controller => _controller;
  String? get sessionId => _sessionId;
  Uint8List? get pmk => _pmk;
  String? get filePath => _filePath;
  bool get isInitialized => _sessionId != null && _pmk != null;
  HlsEncryptor? get encryptor => _encryptor;
}
