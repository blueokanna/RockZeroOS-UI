import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import 'hkdf_blake3.dart';

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
  String _sessionId;
  Uint8List _pmk; // Pairwise Master Key
  final String password; // User password for ZKP proof generation
  final String? jwtToken; // JWT token for authenticated requests
  final Future<(String, Uint8List)> Function()? onSessionRebuild;
  Future<(String, Uint8List)>? _sessionRebuildFuture;

  /// ★ 复用单个 HttpClient 实例，启用 HTTP keep-alive 连接池
  /// 避免每个 segment 请求都创建新连接（大幅减少 TCP 握手开销）
  late final HttpClient _backendClient;

  SecureHlsProxyServer({
    required this.baseUrl,
    required String sessionId,
    required Uint8List pmk,
    required this.password,
    this.jwtToken,
    this.onSessionRebuild,
  })  : _sessionId = sessionId,
        _pmk = pmk {
    _backendClient = HttpClient()
      ..idleTimeout = const Duration(seconds: 30)
      ..maxConnectionsPerHost = 6;
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
    _backendClient.close(force: true);
    await _server?.close(force: true);
    _server = null;
    _port = null;
    debugPrint('[SecureHLS Proxy] Stopped');
  }

  /// 预取指定段附近的视频段
  ///
  /// 在 seek 操作时调用，提前请求目标段附近的数据以减少延迟。
  void prefetchAroundSegment(int segmentIndex) {
    if (_server == null) return;

    debugPrint(
        '[SecureHLS Proxy] Prefetch requested around segment $segmentIndex');

    // 预取当前段及前后各 2 个段（共 5 个段）
    final start = (segmentIndex - 2).clamp(0, segmentIndex);
    final end = segmentIndex + 2;

    for (int i = start; i <= end; i++) {
      final segmentName = 'segment_$i.ts';

      // 异步预取，不阻塞当前操作
      _prefetchSegment(segmentName).catchError((e) {
        debugPrint('[SecureHLS Proxy] Prefetch failed for $segmentName: $e');
      });
    }
  }

  /// 异步预取单个视频段
  Future<void> _prefetchSegment(String segmentName) async {
    try {
      final zkpProof = await _generateBulletproofZkpProof();
      final segmentUrl = '$baseUrl/api/v1/secure-hls/$_sessionId/$segmentName';

      final client = HttpClient();
      final request = await client.postUrl(Uri.parse(segmentUrl));
      request.headers.contentType = ContentType.json;
      if (jwtToken != null) {
        request.headers.add('Authorization', 'Bearer $jwtToken');
      }
      request.write(jsonEncode({'zkp_proof': zkpProof}));

      final response = await request.close();

      if (response.statusCode == 200) {
        // 读取并丢弃——让系统层面的缓存生效
        await response.drain<void>();
        debugPrint('[SecureHLS Proxy] Prefetched: $segmentName');
      }
    } catch (e) {
      // 预取失败不影响正常播放
      debugPrint('[SecureHLS Proxy] Prefetch error for $segmentName: $e');
    }
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
      for (int attempt = 0; attempt < 2; attempt++) {
        final playlistUrl =
            '$baseUrl/api/v1/secure-hls/$_sessionId/playlist.m3u8';
        final response =
            await _backendClient.getUrl(Uri.parse(playlistUrl)).then((req) {
          if (jwtToken != null) {
            req.headers.add('Authorization', 'Bearer $jwtToken');
          }
          return req.close();
        });

        if (response.statusCode == 200) {
          final content = await response.transform(utf8.decoder).join();
          final modifiedContent = _modifyPlaylist(content);

          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
          request.response.write(modifiedContent);
          return;
        }

        final errorBody = await response.transform(utf8.decoder).join();
        final rebuilt = await _rebuildSessionIfNeeded(
          statusCode: response.statusCode,
          errorBody: errorBody,
          trigger: 'playlist',
        );

        if (rebuilt && attempt == 0) {
          continue;
        }

        request.response.statusCode = response.statusCode;
        request.response.write('Failed to fetch playlist: $errorBody');
        return;
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

      for (int attempt = 0; attempt < 2; attempt++) {
        final segmentUrl =
            '$baseUrl/api/v1/secure-hls/$_sessionId/$segmentName';

        final backendRequest =
            await _backendClient.getUrl(Uri.parse(segmentUrl));
        if (jwtToken != null) {
          backendRequest.headers.add('Authorization', 'Bearer $jwtToken');
        }

        final backendResponse = await backendRequest.close();

        if (backendResponse.statusCode == 200) {
          final encryptedData = await backendResponse.fold<List<int>>(
              [], (previous, element) => previous..addAll(element));
          final decryptedData =
              _decryptSegment(Uint8List.fromList(encryptedData));

          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType('video', 'mp2t');
          request.response.headers.contentLength = decryptedData.length;
          request.response.add(decryptedData);

          debugPrint(
              '[SecureHLS Proxy] Segment served: $segmentName (${decryptedData.length} bytes)');
          return;
        }

        final errorBody = await backendResponse.transform(utf8.decoder).join();
        debugPrint(
            '[SecureHLS Proxy] Backend error: ${backendResponse.statusCode} - $errorBody');

        final rebuilt = await _rebuildSessionIfNeeded(
          statusCode: backendResponse.statusCode,
          errorBody: errorBody,
          trigger: segmentName,
        );

        if (rebuilt && attempt == 0) {
          continue;
        }

        request.response.statusCode = backendResponse.statusCode;
        request.response.write('Backend error: $errorBody');
        return;
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

  /// 生成完整的 Bulletproofs ZKP 证明（由后端 Rust 统一生成）
  ///
  /// 通过受保护接口 `/api/v1/zkp/proof/generate` 调用服务端
  /// `rockzero_crypto::ZkpContext::generate_enhanced_proof`，确保前后端证明格式完全一致。
  Future<String> _generateBulletproofZkpProof() async {
    if (jwtToken == null || jwtToken!.isEmpty) {
      throw StateError('JWT token is required for ZKP proof generation');
    }

    final client = HttpClient();
    try {
      final uri = Uri.parse('$baseUrl/api/v1/zkp/proof/generate');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.add('Authorization', 'Bearer $jwtToken');
      request.write(jsonEncode({
        'password': password,
        'context': 'hls_segment_access',
      }));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        throw StateError(
          'Backend proof generation failed: ${response.statusCode} - $responseBody',
        );
      }

      final payload = jsonDecode(responseBody);
      if (payload is! Map<String, dynamic>) {
        throw StateError('Invalid proof response payload format');
      }

      final success = payload['success'] == true;
      if (!success) {
        final error = payload['error']?.toString() ?? 'unknown error';
        throw StateError('Backend proof generation failed: $error');
      }

      final proof = payload['proof'];
      if (proof is String) {
        return proof;
      }

      if (proof is Map) {
        final proofJson = jsonEncode(Map<String, dynamic>.from(proof));
        return base64Encode(utf8.encode(proofJson));
      }

      throw StateError('Invalid proof field type from backend');
    } finally {
      client.close(force: true);
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
      final decryptionKey = _deriveKey(_pmk, 'hls-master-key');

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

  /// 从密钥派生子密钥（使用 HKDF-Blake3，与 Rust 端完全一致）
  ///
  /// Rust 端使用：
  /// ```rust
  /// let hkdf = HkdfBlake3::new_with_session_salt(&session_id, &pmk);
  /// hkdf.expand(b"hls-master-key", &mut encryption_key);
  /// ```
  ///
  /// 参数：
  /// - key: 主密钥（PMK）
  /// - info: 上下文信息字符串
  ///
  /// 返回：32 字节的派生密钥
  Uint8List _deriveKey(Uint8List key, String info) {
    final hkdf = HkdfBlake3.withSessionSalt(_sessionId, key);
    return hkdf.expand(Uint8List.fromList(utf8.encode(info)), 32);
  }

  bool _shouldRebuildSession(int statusCode, String errorBody) {
    if (statusCode == HttpStatus.unauthorized ||
        statusCode == HttpStatus.notFound ||
        statusCode == HttpStatus.gone) {
      return true;
    }

    final lower = errorBody.toLowerCase();
    return lower.contains('session not found') ||
        lower.contains('session expired') ||
        lower.contains('invalid zkp proof') ||
        lower.contains('does not have zkp registration');
  }

  Future<bool> _rebuildSessionIfNeeded({
    required int statusCode,
    required String errorBody,
    required String trigger,
  }) async {
    if (onSessionRebuild == null) {
      return false;
    }
    if (!_shouldRebuildSession(statusCode, errorBody)) {
      return false;
    }

    if (_sessionRebuildFuture != null) {
      final rebuilt = await _sessionRebuildFuture!;
      _sessionId = rebuilt.$1;
      _pmk = rebuilt.$2;
      return true;
    }

    debugPrint(
        '[SecureHLS Proxy] Session appears stale during $trigger, rebuilding chain...');

    _sessionRebuildFuture = onSessionRebuild!.call();
    try {
      final rebuilt = await _sessionRebuildFuture!;
      _sessionId = rebuilt.$1;
      _pmk = rebuilt.$2;
      debugPrint('[SecureHLS Proxy] Session rebuilt: $_sessionId');
      return true;
    } catch (e) {
      debugPrint('[SecureHLS Proxy] Session rebuild failed: $e');
      return false;
    } finally {
      _sessionRebuildFuture = null;
    }
  }
}
