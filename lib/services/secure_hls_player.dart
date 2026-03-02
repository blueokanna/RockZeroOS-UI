import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' as pc;
import 'package:video_player/video_player.dart';

import 'zkp/hls_bulletproof_auth.dart';
import 'sae_client.dart';
import 'secure_hls_proxy.dart';

/// 安全 HLS 播放器
///
/// 使用 SAE 握手 + Bulletproofs ZKP 证明 + AES-256-GCM 加密
///
/// ## 安全架构
/// 1. SAE 握手：与服务器建立共享密钥 (PMK)
/// 2. Bulletproofs ZKP：证明用户知道密码，不泄露密码
/// 3. AES-256-GCM：使用 PMK 派生的密钥加密视频段
///
/// ## 使用流程
/// 1. 调用 initializeSaeHandshake() 完成 SAE 握手
/// 2. 调用 play() 开始播放视频
/// 3. 每个视频段请求都会自动生成 ZKP 证明
class SecureHlsPlayer {
  final String baseUrl;
  final String jwtToken;

  // SAE 握手相关
  Uint8List? _pmk; // Pairwise Master Key
  String? _sessionId;
  String? _password; // 保存密码用于 ZKP 证明生成

  // ZKP 注册数据（从服务器获取）
  PasswordRegistration? _zkpRegistration;

  // Bulletproofs 认证上下文
  late final HlsBulletproofAuth _bulletproofAuth;

  // 加密器
  HlsEncryptor? _encryptor;
  SecureHlsProxyServer? _proxy;

  // 视频播放器
  VideoPlayerController? _controller;

  SecureHlsPlayer({
    required this.baseUrl,
    required this.jwtToken,
  }) {
    _bulletproofAuth = HlsBulletproofAuth();
  }

  /// Ensure we have ZKP registration data (from server or locally generated)
  Future<void> _ensureZkpRegistration(String userId) async {
    // Prefer server-provided registration
    await _fetchZkpRegistration(userId);

    // Fallback: generate locally if server did not return registration
    if (_zkpRegistration == null && _password != null) {
      // Initialize FFI once before registration
      _bulletproofAuth.initializeAuto();
      _zkpRegistration = _bulletproofAuth.registerPassword(_password!);
      debugPrint('[SecureHLS] Generated local ZKP registration');
    }

    if (_zkpRegistration == null) {
      throw Exception('ZKP registration not available; cannot generate proofs');
    }
  }

  /// 步骤 1: 初始化 SAE 握手
  ///
  /// 执行完整的 WPA3-SAE 握手，建立与服务器的共享密钥 (PMK)。
  /// 同时获取用户的 ZKP 注册数据用于后续的证明生成。
  Future<void> initializeSaeHandshake(
    String userId,
    String password,
    String fileId,
  ) async {
    debugPrint('[SecureHLS] Starting SAE handshake for user: $userId');

    // 保存密码用于 ZKP 证明生成
    _password = password;

    // 1. 创建 SAE 客户端
    final saeClient = SaeClient(
      password: Uint8List.fromList(utf8.encode(password)),
      deviceIdSelf: Uint8List.fromList(utf8.encode(userId)),
      deviceIdPeer: Uint8List.fromList(utf8.encode('rockzero-server')),
    );

    // 2. 生成客户端 commit（返回 Map）
    final clientCommit = saeClient.generateCommit();

    // 3. 初始化服务器 SAE 握手
    final initResponse = await http.post(
      Uri.parse('$baseUrl/api/v1/secure-hls/sae/init'),
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'user_id': userId,
        'file_id': fileId,
      }),
    );

    if (initResponse.statusCode != 200) {
      throw Exception('SAE init failed: ${initResponse.body}');
    }

    final initData = jsonDecode(initResponse.body);
    final tempSessionId = initData['temp_session_id'];

    debugPrint('[SecureHLS] Got temp session: $tempSessionId');

    // 4. 发送客户端 commit（clientCommit 已经是 Base64 编码）
    final commitResponse = await http.post(
      Uri.parse('$baseUrl/api/v1/secure-hls/sae/commit'),
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'temp_session_id': tempSessionId,
        'client_commit': clientCommit,
      }),
    );

    if (commitResponse.statusCode != 200) {
      throw Exception('SAE commit failed: ${commitResponse.body}');
    }

    final commitData = jsonDecode(commitResponse.body);
    final serverCommit = commitData['server_commit'] as Map<String, dynamic>;

    // 5. 处理服务器 commit
    saeClient.processCommit(serverCommit);

    // 6. 生成客户端 confirm
    final clientConfirm = saeClient.generateConfirm();

    // 7. 发送客户端 confirm
    final confirmResponse = await http.post(
      Uri.parse('$baseUrl/api/v1/secure-hls/sae/confirm'),
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'temp_session_id': tempSessionId,
        'client_confirm': clientConfirm,
      }),
    );

    if (confirmResponse.statusCode != 200) {
      throw Exception('SAE confirm failed: ${confirmResponse.body}');
    }

    final confirmData = jsonDecode(confirmResponse.body);

    // 8. 验证服务器 confirm
    final serverConfirm = confirmData['server_confirm'] as Map<String, dynamic>;
    saeClient.verifyConfirm(serverConfirm);

    // 9. 获取 PMK
    _pmk = saeClient.getPmk();
    debugPrint('[SecureHLS] SAE handshake completed, PMK obtained');

    // 10. 创建 HLS 会话
    final sessionResponse = await http.post(
      Uri.parse('$baseUrl/api/v1/secure-hls/session/create'),
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'temp_session_id': tempSessionId,
        'file_id': fileId,
      }),
    );

    if (sessionResponse.statusCode != 200) {
      throw Exception('Session create failed: ${sessionResponse.body}');
    }

    final sessionData = jsonDecode(sessionResponse.body);
    _sessionId = sessionData['session_id'];
    final zkpEnabled = sessionData['zkp_enabled'] ?? false;

    debugPrint(
        '[SecureHLS] HLS session created: $_sessionId (ZKP enabled: $zkpEnabled)');

    // 10. 获取或生成 ZKP 注册数据（完整 Bulletproofs）
    await _ensureZkpRegistration(userId);

    // 11. 初始化加密器
    _encryptor = HlsEncryptor(
      pmk: _pmk!,
      password: password,
      zkpRegistration: _zkpRegistration,
      bulletproofAuth: _bulletproofAuth,
    );
  }

  /// 获取用户的 ZKP 注册数据
  Future<void> _fetchZkpRegistration(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/users/$userId/zkp-registration'),
        headers: {
          'Authorization': 'Bearer $jwtToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _zkpRegistration = PasswordRegistration.fromJson(data);
        debugPrint('[SecureHLS] Fetched ZKP registration from server');
      } else {
        debugPrint('[SecureHLS] No ZKP registration on server, using local');
        if (_password != null) {
          _zkpRegistration = _bulletproofAuth.registerPassword(_password!);
        }
      }
    } catch (e) {
      debugPrint('[SecureHLS] Failed to fetch ZKP registration: $e');
      if (_password != null) {
        _zkpRegistration = _bulletproofAuth.registerPassword(_password!);
      }
    }
  }

  /// 步骤 2: 播放视频
  ///
  /// 注意：Flutter video_player 不支持自定义 HTTP 客户端，
  /// 需要使用本地代理服务器模式来拦截和解密视频段。
  /// 请参考 SecureHlsProxyServer 类的实现。
  Future<VideoPlayerController> play() async {
    if (_sessionId == null || _pmk == null) {
      throw Exception('SAE handshake not completed');
    }

    if (_encryptor == null) {
      throw Exception('Encryptor not initialized');
    }

    if (_password == null) {
      throw Exception('Password not available for ZKP proof generation');
    }

    // 启动本地代理以在每个分片请求中附加 Bulletproofs ZKP 证明
    _proxy ??= SecureHlsProxyServer(
      baseUrl: baseUrl,
      sessionId: _sessionId!,
      pmk: _pmk!,
      password: _password!,
      zkpRegistration: _zkpRegistration,
      jwtToken: jwtToken, // 传递 JWT token 给代理
    );

    final proxyPlaylistUrl = await _proxy!.start();

    // 使用代理返回的播放列表 URL 初始化播放器
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(proxyPlaylistUrl),
      httpHeaders: const {},
    );

    await _controller!.initialize();

    debugPrint('[SecureHLS] Video player initialized via local proxy');

    return _controller!;
  }

  /// 直接播放模式（无代理、无加密、无 ZKP）
  ///
  /// 视频段通过 GET 请求直接获取，不经过本地代理。
  /// 安全性由 session_id（随机 UUID）保证。
  /// 适合 ARM 等低性能设备，避免每段的 ZKP 证明和加解密开销。
  ///
  /// 流程：
  /// 1. 播放器直接 GET playlist.m3u8（session 鉴权）
  /// 2. 播放器直接 GET segment_N.ts（session 鉴权）
  /// 3. 服务器返回明文视频段
  /// 4. 支持随点随播（ffmpeg VOD 分片 + HLS ENDLIST）
  Future<VideoPlayerController> playDirect() async {
    if (_sessionId == null) {
      throw Exception(
          'SAE handshake not completed. Call initializeSaeHandshake() first.');
    }

    // 直接使用服务器的播放列表 URL（不需要本地代理）
    final playlistUrl = '$baseUrl/api/v1/secure-hls/$_sessionId/playlist.m3u8';
    debugPrint('[SecureHLS] Direct play mode: $playlistUrl');

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(playlistUrl),
      httpHeaders: const {},
    );

    await _controller!.initialize();
    debugPrint('[SecureHLS] Video player initialized (direct mode, no proxy)');

    return _controller!;
  }

  /// 停止播放
  Future<void> stop() async {
    await _proxy?.stop();
    _proxy = null;
    await _controller?.dispose();
    _controller = null;
    _sessionId = null;
    _pmk = null;
    _password = null;
    _zkpRegistration = null;
    _encryptor = null;
  }

  /// 获取播放器控制器
  VideoPlayerController? get controller => _controller;

  /// 获取代理服务器实例（用于段预取等）
  SecureHlsProxyServer? get proxy => _proxy;

  /// 获取代理播放列表 URL
  ///
  /// 启动本地代理服务器（如果未启动），返回代理播放列表 URL。
  /// 供 media_kit 或其他播放器使用。
  Future<String> getProxyPlaylistUrl() async {
    if (_sessionId == null || _pmk == null) {
      throw Exception('SAE handshake not completed');
    }

    if (_password == null) {
      throw Exception('Password not available for ZKP proof generation');
    }

    _proxy ??= SecureHlsProxyServer(
      baseUrl: baseUrl,
      sessionId: _sessionId!,
      pmk: _pmk!,
      password: _password!,
      zkpRegistration: _zkpRegistration,
      jwtToken: jwtToken,
    );

    return await _proxy!.start();
  }

  /// 获取直接播放列表 URL（无代理模式）
  ///
  /// 返回服务器的播放列表 URL，播放器直接通过 GET 请求获取视频段。
  /// 无需本地代理、ZKP 证明或段加解密，适合 ARM 等低性能设备。
  /// 支持随点随播（ffmpeg VOD 分片）。
  String getDirectPlaylistUrl() {
    if (_sessionId == null) {
      throw Exception('SAE handshake not completed');
    }
    return '$baseUrl/api/v1/secure-hls/$_sessionId/playlist.m3u8';
  }

  /// 获取会话 ID
  String? get sessionId => _sessionId;

  /// 获取 PMK
  Uint8List? get pmk => _pmk;

  /// 获取 ZKP 注册数据
  PasswordRegistration? get zkpRegistration => _zkpRegistration;
}

/// HLS 加密器
///
/// 负责：
/// 1. 生成 Bulletproofs ZKP 证明
/// 2. 解密视频段（AES-256-GCM）
class HlsEncryptor {
  final Uint8List pmk;
  final String password;
  final PasswordRegistration? zkpRegistration;
  final HlsBulletproofAuth bulletproofAuth;
  late Uint8List _encryptionKey;

  HlsEncryptor({
    required this.pmk,
    required this.password,
    required this.zkpRegistration,
    required this.bulletproofAuth,
  }) {
    // 从 PMK 派生加密密钥（使用 HKDF-SHA3-256）
    _encryptionKey = _deriveKey(pmk, 'hls-master-key');
  }

  /// 生成 Bulletproofs ZKP 证明
  ///
  /// 生成完整的零知识证明，证明用户知道密码。
  /// 证明包含：
  /// - Schnorr 证明：证明知道密码和 blinding factor
  /// - Bulletproofs 范围证明：证明密码熵值 >= 28 bits
  /// - 时间戳和 nonce：防止重放攻击
  String generateZkpProof() {
    if (zkpRegistration == null) {
      throw StateError(
        'ZKP registration data is required for Bulletproofs authentication',
      );
    }

    // 确保 FFI 已初始化
    if (!bulletproofAuth.isInitialized) {
      if (!bulletproofAuth.initializeAuto()) {
        throw StateError(
          'Failed to initialize Bulletproofs FFI. '
          'Ensure the native library is available.',
        );
      }
    }

    debugPrint('[HlsEncryptor] Generating full Bulletproofs ZKP proof...');

    // generateProof 直接返回 Base64 编码的证明字符串
    final proofBase64 = bulletproofAuth.generateProof(
      password,
      zkpRegistration!,
      context: 'hls_segment_access',
    );

    debugPrint('[HlsEncryptor] ✅ Bulletproofs ZKP proof generated');

    return proofBase64;
  }

  /// 解密视频段（AES-256-GCM）
  ///
  /// 格式：nonce (12 bytes) + ciphertext + tag (16 bytes)
  Uint8List decryptSegment(Uint8List encryptedData) {
    if (encryptedData.length < 28) {
      throw Exception('Encrypted data too short for AES-256-GCM');
    }

    // 提取 nonce（前 12 字节）
    final nonce = encryptedData.sublist(0, 12);
    // 剩余部分是 ciphertext + auth tag
    final ciphertextWithTag = encryptedData.sublist(12);

    // 使用 AES-256-GCM 解密
    return _aesGcmDecrypt(_encryptionKey, nonce, ciphertextWithTag);
  }

  /// 从密钥派生子密钥（HKDF-SHA3-256）
  Uint8List _deriveKey(Uint8List key, String info) {
    final hkdf = pc.HKDFKeyDerivator(pc.SHA3Digest(256));
    final infoBytes = Uint8List.fromList(utf8.encode(info));
    hkdf.init(pc.HkdfParameters(key, 32, null, infoBytes));

    final derivedKey = Uint8List(32);
    hkdf.deriveKey(null, 0, derivedKey, 0);
    return derivedKey;
  }

  /// AES-256-GCM 解密
  Uint8List _aesGcmDecrypt(
    Uint8List key,
    Uint8List nonce,
    Uint8List ciphertextWithTag,
  ) {
    final gcm = pc.GCMBlockCipher(pc.AESEngine());

    final params = pc.AEADParameters(
      pc.KeyParameter(key),
      128, // tag 长度（位）
      nonce,
      Uint8List(0), // AAD
    );

    gcm.init(false, params);

    try {
      return gcm.process(ciphertextWithTag);
    } catch (e) {
      throw Exception('AES-256-GCM decryption failed: $e');
    }
  }
}

/// 自定义 HTTP 客户端（拦截 TS 段请求）
///
/// 用于拦截视频段请求，自动添加 ZKP 证明。
/// 注意：Flutter video_player 不直接支持自定义 HTTP 客户端，
/// 生产环境请使用 SecureHlsProxyServer。
class SecureHttpClient extends http.BaseClient {
  final String baseUrl;
  final String sessionId;
  final HlsEncryptor encryptor;
  final String jwtToken;
  final http.Client _inner = http.Client();

  SecureHttpClient({
    required this.baseUrl,
    required this.sessionId,
    required this.encryptor,
    required this.jwtToken,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();

    // 拦截 TS 段请求
    if (url.contains('.ts')) {
      debugPrint('[SecureHLS] Intercepting segment request: $url');

      // 生成 Bulletproofs ZKP 证明
      final zkpProof = encryptor.generateZkpProof();

      // 发送 POST 请求（带 ZKP 证明）
      final response = await http.post(
        request.url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
          ...request.headers,
        },
        body: jsonEncode({
          'zkp_proof': zkpProof,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('[SecureHLS] Segment request failed: ${response.body}');
        return http.StreamedResponse(
          Stream.value(Uint8List(0)),
          response.statusCode,
        );
      }

      // 解密视频段
      final encryptedData = response.bodyBytes;
      final decryptedData = encryptor.decryptSegment(encryptedData);

      debugPrint(
          '[SecureHLS] Segment decrypted: ${decryptedData.length} bytes');

      return http.StreamedResponse(
        Stream.value(decryptedData),
        200,
        headers: {'content-type': 'video/mp2t'},
      );
    }

    // 其他请求直接转发
    return _inner.send(request);
  }
}
