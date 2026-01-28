import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:pointycastle/export.dart';

import 'zkp/hls_bulletproof_auth.dart';

/// 安全 HLS 代理服务器
///
/// 使用 Bulletproofs 零知识证明进行视频段访问认证
///
/// 工作原理：
/// 1. 启动本地 HTTP 服务器（127.0.0.1:随机端口）
/// 2. 拦截播放器的 .ts 段请求
/// 3. 生成 Bulletproofs ZKP 证明（证明密码知识）
/// 4. 向后端发送 POST 请求（带 ZKP 证明）
/// 5. 解密视频段（使用 AES-256-GCM）
/// 6. 返回明文视频段给播放器
class SecureHlsProxyServer {
  HttpServer? _server;
  int? _port;
  final String baseUrl;
  final String sessionId;
  final Uint8List pmk; // Pairwise Master Key
  final String password; // User password for ZKP proof generation
  final PasswordRegistration? zkpRegistration; // ZKP registration from server

  // Bulletproofs auth context
  late final HlsBulletproofAuth _bulletproofAuth;

  SecureHlsProxyServer({
    required this.baseUrl,
    required this.sessionId,
    required this.pmk,
    required this.password,
    this.zkpRegistration,
  }) {
    _bulletproofAuth = HlsBulletproofAuth();
  }

  /// 启动代理服务器
  Future<String> start() async {
    try {
      // 绑定到本地回环地址的随机端口
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;

      debugPrint('[SecureHLS Proxy] Started on http://127.0.0.1:$_port');
      debugPrint('[SecureHLS Proxy] Using Bulletproofs ZKP authentication');

      // 处理请求
      _server!.listen(_handleRequest);

      // 返回代理服务器的播放列表 URL
      return 'http://127.0.0.1:$_port/playlist.m3u8';
    } catch (e) {
      debugPrint('[SecureHLS Proxy] Failed to start: $e');
      rethrow;
    }
  }

  /// 停止代理服务器
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
    debugPrint('[SecureHLS Proxy] Stopped');
  }

  /// 处理 HTTP 请求
  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      debugPrint('[SecureHLS Proxy] Request: ${request.method} $path');

      if (path == '/playlist.m3u8') {
        // 转发播放列表请求
        await _handlePlaylistRequest(request);
      } else if (path.endsWith('.ts')) {
        // 拦截视频段请求，添加 ZKP 证明
        await _handleSegmentRequest(request, path);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not Found');
        await request.response.close();
      }
    } catch (e) {
      debugPrint('[SecureHLS Proxy] Error handling request: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Internal Server Error: $e');
      await request.response.close();
    }
  }

  /// 处理播放列表请求
  Future<void> _handlePlaylistRequest(HttpRequest request) async {
    try {
      // 从后端获取播放列表
      final playlistUrl = '$baseUrl/api/v1/secure-hls/$sessionId/playlist.m3u8';
      final response = await HttpClient()
          .getUrl(Uri.parse(playlistUrl))
          .then((req) => req.close());

      if (response.statusCode == 200) {
        // 读取播放列表内容
        final content = await response.transform(utf8.decoder).join();

        // 修改播放列表，将视频段 URL 替换为代理服务器的 URL
        final modifiedContent = _modifyPlaylist(content);

        // 返回修改后的播放列表
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
        request.response.write(modifiedContent);
      } else {
        request.response.statusCode = response.statusCode;
        request.response.write('Failed to fetch playlist');
      }
    } catch (e) {
      debugPrint('[SecureHLS Proxy] Playlist error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Error: $e');
    } finally {
      await request.response.close();
    }
  }

  /// 修改播放列表，替换视频段 URL
  String _modifyPlaylist(String content) {
    // 将 segment_N.ts 替换为代理服务器的 URL
    return content.replaceAllMapped(
      RegExp(r'(segment_\d+\.ts)'),
      (match) => 'http://127.0.0.1:$_port/${match.group(1)}',
    );
  }

  /// 处理视频段请求（使用 Bulletproofs ZKP 证明）
  Future<void> _handleSegmentRequest(HttpRequest request, String path) async {
    try {
      final segmentName = path.substring(1); // 移除开头的 '/'

      debugPrint('[SecureHLS Proxy] Fetching segment: $segmentName');

      // 1. 生成 Bulletproofs ZKP 证明
      final zkpProof = _generateBulletproofZkpProof();

      // 2. 向后端发送 POST 请求（带 ZKP 证明）
      final segmentUrl = '$baseUrl/api/v1/secure-hls/$sessionId/$segmentName';

      final client = HttpClient();
      final backendRequest = await client.postUrl(Uri.parse(segmentUrl));
      backendRequest.headers.contentType = ContentType.json;

      // 发送 JSON body（包含 ZKP 证明）
      final body = jsonEncode({'zkp_proof': zkpProof});
      backendRequest.write(body);

      final backendResponse = await backendRequest.close();

      if (backendResponse.statusCode == 200) {
        // 3. 读取加密的视频段
        final encryptedData = await backendResponse.fold<List<int>>(
            [], (previous, element) => previous..addAll(element));

        // 4. 解密视频段（使用 AES-256-GCM）
        final decryptedData =
            _decryptSegment(Uint8List.fromList(encryptedData));

        // 5. 返回明文视频段给播放器
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType('video', 'mp2t');
        request.response.headers.contentLength = decryptedData.length;
        request.response.add(decryptedData);

        debugPrint(
            '[SecureHLS Proxy] Segment served: $segmentName (${decryptedData.length} bytes)');
      } else {
        final errorBody = await backendResponse.transform(utf8.decoder).join();
        debugPrint(
            '[SecureHLS Proxy] Backend error: ${backendResponse.statusCode} - $errorBody');
        request.response.statusCode = backendResponse.statusCode;
        request.response.write('Backend error: $errorBody');
      }
    } catch (e, stack) {
      debugPrint('[SecureHLS Proxy] Segment error: $e');
      debugPrint('[SecureHLS Proxy] Stack: $stack');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Error: $e');
    } finally {
      await request.response.close();
    }
  }

  /// 生成完整的 Bulletproofs ZKP 证明
  ///
  /// 使用 Rust FFI 调用完整的 Bulletproofs 实现，
  /// 证明用户知道密码，而不泄露密码本身。
  ///
  /// 证明结构包含：
  /// - Schnorr 证明：证明知道密码和 blinding factor
  /// - Bulletproofs 范围证明：密码熵值 >= 28 bits（密码学证明）
  /// - 时间戳和 nonce：防止重放攻击
  /// - 上下文绑定：固定为 "hls_segment_access"
  String _generateBulletproofZkpProof() {
    if (zkpRegistration == null) {
      throw StateError(
        'ZKP registration data is required for authentication. '
        'Please ensure the user has completed registration.',
      );
    }

    // 确保 FFI 已初始化
    if (!_bulletproofAuth.isInitialized) {
      if (!_bulletproofAuth.initializeAuto()) {
        throw StateError(
          'Failed to initialize Bulletproofs FFI. '
          'Ensure the native library is available.',
        );
      }
    }

    try {
      debugPrint('[SecureHLS Proxy] Generating full Bulletproofs ZKP proof...');

      // 生成完整的 Bulletproofs 证明（Schnorr + 范围证明）
      final proofBase64 = _bulletproofAuth.generateProof(
        password,
        zkpRegistration!,
        context: 'hls_segment_access',
      );

      debugPrint('[SecureHLS Proxy] ✅ Full Bulletproofs ZKP proof generated');
      debugPrint(
          '[SecureHLS Proxy]   - Proof size: ${proofBase64.length} chars (base64)');

      return proofBase64;
    } catch (e) {
      debugPrint('[SecureHLS Proxy] Failed to generate Bulletproofs proof: $e');
      rethrow;
    }
  }

  /// 解密视频段（完整的 AES-256-GCM 实现）
  ///
  /// Rust端加密数据格式（使用 aes_gcm crate）：
  /// - 前 12 字节：nonce
  /// - 剩余部分：ciphertext + tag（tag自动附加在ciphertext末尾）
  Uint8List _decryptSegment(Uint8List encryptedData) {
    if (encryptedData.length < 28) {
      // 至少需要 12 字节 nonce + 16 字节 tag
      debugPrint(
          '[SecureHLS Proxy] Invalid encrypted data length: ${encryptedData.length}');
      throw Exception('Invalid encrypted data format');
    }

    try {
      // 提取 nonce（前 12 字节）
      final nonce = encryptedData.sublist(0, 12);

      // 剩余部分是 ciphertext + tag（tag 已经附加在 ciphertext 末尾）
      final ciphertextWithTag = encryptedData.sublist(12);

      // 从 PMK 派生解密密钥（AES-256 需要 32 字节）
      // 使用与 Rust 端完全一致的 info 参数："hls-master-key"
      final decryptionKey = _deriveKey(pmk, 'hls-master-key');

      // 使用完整的 AES-256-GCM 解密
      // pointycastle 的 GCM 实现会自动处理附加在末尾的 tag
      final plaintext = _aesGcmDecrypt(
        ciphertextWithTag: ciphertextWithTag,
        key: decryptionKey,
        nonce: nonce,
      );

      debugPrint(
          '[SecureHLS Proxy] Decrypted segment: ${plaintext.length} bytes');
      return plaintext;
    } catch (e, stack) {
      debugPrint('[SecureHLS Proxy] Decryption error: $e');
      debugPrint('[SecureHLS Proxy] Stack trace: $stack');
      rethrow;
    }
  }

  /// AES-256-GCM 解密（完整的生产级实现）
  ///
  /// 使用 pointycastle 库实现标准的 AES-GCM 解密
  ///
  /// 参数：
  /// - ciphertextWithTag: 加密的数据 + 认证标签（tag 附加在末尾）
  /// - key: 32 字节的 AES-256 密钥
  /// - nonce: 12 字节的 nonce（IV）
  ///
  /// 返回：解密后的明文数据
  ///
  /// 抛出：如果认证失败或解密失败
  ///
  /// 注意：Rust 的 aes_gcm crate 会自动将 16 字节的 tag 附加到 ciphertext 末尾
  Uint8List _aesGcmDecrypt({
    required Uint8List ciphertextWithTag,
    required Uint8List key,
    required Uint8List nonce,
  }) {
    try {
      // 验证参数长度
      if (key.length != 32) {
        throw ArgumentError(
            'AES-256 requires a 32-byte key, got ${key.length}');
      }
      if (nonce.length != 12) {
        throw ArgumentError(
            'GCM requires a 12-byte nonce, got ${nonce.length}');
      }
      if (ciphertextWithTag.length < 16) {
        throw ArgumentError(
            'Ciphertext too short, must include 16-byte tag, got ${ciphertextWithTag.length}');
      }

      // 创建 AES-GCM 解密器
      final cipher = GCMBlockCipher(AESEngine());

      // 设置参数
      // pointycastle 的 GCM 实现期望 ciphertext + tag 作为输入
      final params = AEADParameters(
        KeyParameter(key),
        128, // tag 长度（位）
        nonce,
        Uint8List(0), // 附加认证数据（AAD）为空
      );

      // 初始化解密器
      cipher.init(false, params); // false = 解密模式

      // 执行解密（输入是 ciphertext + tag）
      final plaintext = cipher.process(ciphertextWithTag);

      debugPrint('[SecureHLS Proxy] AES-GCM decryption successful');
      return plaintext;
    } on ArgumentError catch (e) {
      debugPrint('[SecureHLS Proxy] Invalid GCM parameters: $e');
      throw Exception('GCM decryption failed: Invalid parameters - $e');
    } catch (e) {
      // 认证失败或其他错误
      debugPrint('[SecureHLS Proxy] GCM decryption failed: $e');
      throw Exception(
          'GCM decryption failed: Authentication tag verification failed or corrupted data');
    }
  }

  /// 从密钥派生子密钥（使用 HKDF-SHA3-256）
  ///
  /// 生产级实现：使用 HKDF-SHA3-256 进行密钥派生，与 Rust 端完全一致
  ///
  /// Rust 端使用：
  /// ```rust
  /// let hk = Hkdf::<Sha3_256>::new(None, &pmk);
  /// hk.expand(b"hls-master-key", &mut encryption_key)
  /// ```
  ///
  /// 参数：
  /// - key: 主密钥（PMK）
  /// - info: 上下文信息字符串
  ///
  /// 返回：32 字节的派生密钥
  Uint8List _deriveKey(Uint8List key, String info) {
    // 使用 HKDF-SHA3-256 派生密钥（与 Rust 端一致）
    //
    // Rust hkdf crate 的 Hkdf::new(None, &pmk) 行为：
    // - salt = None 时，使用全零 salt（长度等于哈希输出长度，即 32 字节）
    // - Extract: PRK = HMAC-SHA3-256(salt, IKM)
    // - Expand: OKM = HMAC-SHA3-256(PRK, info || counter)

    final infoBytes = Uint8List.fromList(utf8.encode(info));

    // HKDF-Extract: PRK = HMAC-SHA3-256(salt, IKM)
    // salt = 全零 32 字节（与 Rust Hkdf::new(None, ...) 一致）
    final salt = Uint8List(32);
    final prk = _hmacSha3_256(salt, key);

    // HKDF-Expand: OKM = T(1) || T(2) || ...
    // T(0) = empty
    // T(i) = HMAC-SHA3-256(PRK, T(i-1) || info || i)
    final output = <int>[];
    var t = Uint8List(0);
    var counter = 1;

    while (output.length < 32) {
      final hmacInput = Uint8List.fromList([...t, ...infoBytes, counter]);
      t = _hmacSha3_256(prk, hmacInput);
      output.addAll(t);
      counter++;
    }

    return Uint8List.fromList(output.sublist(0, 32));
  }

  /// HMAC-SHA3-256
  Uint8List _hmacSha3_256(Uint8List key, Uint8List message) {
    final hmac = hashlib.HMAC(hashlib.sha3_256).by(key);
    final digest = hmac.convert(message);
    return Uint8List.fromList(digest.bytes);
  }
}
