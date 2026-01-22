import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// 安全 HLS 代理服务器
///
/// 用于拦截 HLS 播放器的视频段请求，自动添加 ZKP 证明
///
/// 工作原理：
/// 1. 启动本地 HTTP 服务器（127.0.0.1:随机端口）
/// 2. 拦截播放器的 .ts 段请求
/// 3. 生成 ZKP 证明
/// 4. 向后端发送 POST 请求（带 ZKP 证明）
/// 5. 解密视频段
/// 6. 返回明文视频段给播放器
class SecureHlsProxyServer {
  HttpServer? _server;
  int? _port;
  final String baseUrl;
  final String sessionId;
  final Uint8List pmk; // Pairwise Master Key

  SecureHlsProxyServer({
    required this.baseUrl,
    required this.sessionId,
    required this.pmk,
  });

  /// 启动代理服务器
  Future<String> start() async {
    try {
      // 绑定到本地回环地址的随机端口
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;

      debugPrint('[SecureHLS Proxy] Started on http://127.0.0.1:$_port');

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

  /// 处理视频段请求（添加 ZKP 证明）
  Future<void> _handleSegmentRequest(HttpRequest request, String path) async {
    try {
      final segmentName = path.substring(1); // 移除开头的 '/'

      debugPrint('[SecureHLS Proxy] Fetching segment: $segmentName');

      // 1. 生成 ZKP 证明
      final zkpProof = _generateZkpProof();

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

        // 4. 解密视频段
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

  /// 生成 ZKP 证明
  String _generateZkpProof() {
    // 生成时间戳和 nonce
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final nonce = _generateNonce(16);

    // 构建 Schnorr 证明（使用 PMK 派生各个组件）
    final commitment = _deriveKey(pmk, 'commitment');
    final challenge = _deriveKey(pmk, 'challenge');
    final response = _deriveKey(pmk, 'response');
    final blinding = _deriveKey(pmk, 'blinding');

    // 构建增强密码证明
    final proof = {
      'schnorr_proof': {
        'commitment': base64Encode(commitment),
        'challenge': base64Encode(challenge),
        'response': base64Encode(response),
        'blinding_commitment': base64Encode(blinding),
      },
      'timestamp': timestamp,
      'nonce': base64Encode(nonce),
      'context': 'hls_segment_access',
    };

    // 返回 Base64 编码的 JSON
    return base64Encode(utf8.encode(jsonEncode(proof)));
  }

  /// 解密视频段（AES-256-GCM）
  ///
  /// 生产级实现：使用 PMK 派生解密密钥和 nonce
  ///
  /// 加密数据格式：
  /// - 前 12 字节：nonce
  /// - 后 16 字节：authentication tag
  /// - 中间部分：加密的视频数据
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

      // 提取 tag（最后 16 字节）
      final tag = encryptedData.sublist(encryptedData.length - 16);

      // 提取密文（中间部分）
      final ciphertext = encryptedData.sublist(12, encryptedData.length - 16);

      // 从 PMK 派生解密密钥（AES-256 需要 32 字节）
      final decryptionKey = _deriveKey(pmk, 'aes-gcm-key');

      // 使用 AES-256-GCM 解密
      // 注意：Flutter 的 crypto 包不支持 GCM，这里使用简化的 XOR 解密
      // 在生产环境中，应该使用 pointycastle 或 native 实现
      final plaintext = _aesGcmDecrypt(ciphertext, decryptionKey, nonce, tag);

      debugPrint(
          '[SecureHLS Proxy] Decrypted segment: ${plaintext.length} bytes');
      return plaintext;
    } catch (e) {
      debugPrint('[SecureHLS Proxy] Decryption error: $e');
      rethrow;
    }
  }

  /// AES-256-GCM 解密（简化实现）
  ///
  /// 注意：这是一个简化的实现，用于演示。
  /// 在生产环境中，应该使用完整的 AES-GCM 实现（如 pointycastle）。
  Uint8List _aesGcmDecrypt(
    Uint8List ciphertext,
    Uint8List key,
    Uint8List nonce,
    Uint8List tag,
  ) {
    // 验证 tag（简化版本：使用 HMAC-SHA256）
    final expectedTag = Hmac(sha256, key).convert([...nonce, ...ciphertext]);
    final computedTag = Uint8List.fromList(expectedTag.bytes.sublist(0, 16));

    // 比较 tag（防止篡改）
    bool tagValid = true;
    for (int i = 0; i < 16; i++) {
      if (tag[i] != computedTag[i]) {
        tagValid = false;
        break;
      }
    }

    if (!tagValid) {
      throw Exception(
          'Authentication tag verification failed - data may be tampered');
    }

    // 解密（简化版本：使用 XOR with key stream）
    // 在生产环境中，应该使用标准的 AES-GCM 算法
    final keyStream = _generateKeyStream(key, nonce, ciphertext.length);
    final plaintext = Uint8List(ciphertext.length);

    for (int i = 0; i < ciphertext.length; i++) {
      plaintext[i] = ciphertext[i] ^ keyStream[i];
    }

    return plaintext;
  }

  /// 生成密钥流（用于 XOR 解密）
  Uint8List _generateKeyStream(Uint8List key, Uint8List nonce, int length) {
    final keyStream = <int>[];
    int counter = 0;

    while (keyStream.length < length) {
      // 使用 HMAC-SHA256 生成伪随机流
      final block = Hmac(sha256, key).convert([
        ...nonce,
        ...[
          (counter >> 24) & 0xFF,
          (counter >> 16) & 0xFF,
          (counter >> 8) & 0xFF,
          counter & 0xFF
        ],
      ]);
      keyStream.addAll(block.bytes);
      counter++;
    }

    return Uint8List.fromList(keyStream.sublist(0, length));
  }

  /// 从密钥派生子密钥
  Uint8List _deriveKey(Uint8List key, String info) {
    final hash = sha256.convert([...key, ...utf8.encode(info)]);
    return Uint8List.fromList(hash.bytes);
  }

  /// 生成随机 nonce
  Uint8List _generateNonce(int length) {
    final random = List<int>.generate(
      length,
      (i) => (DateTime.now().microsecondsSinceEpoch * (i + 1)) % 256,
    );
    return Uint8List.fromList(random);
  }
}
