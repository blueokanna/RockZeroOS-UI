import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:thirds/blake3.dart' as blake3;

import 'sae_client_curve25519.dart';

/// SAE 握手服务
///
/// 负责与后端进行完整的 SAE 握手流程
class SaeHandshakeService {
  final String baseUrl;
  final String jwtToken;

  SaeHandshakeService({
    required this.baseUrl,
    required this.jwtToken,
  });

  /// 执行完整的 SAE 握手
  ///
  /// 返回：(sessionId, pmk)
  /// 
  /// 参数：
  /// - filePath: 视频文件路径
  /// - password: 共享密码（密码哈希）
  /// - userId: 用户ID（用于生成客户端设备ID）
  Future<(String, Uint8List)> performHandshake({
    required String filePath,
    required String password,
    required String userId,
  }) async {
    try {
      debugPrint('[SAE Handshake] Starting for file: $filePath');

      // 1. 创建 SAE 客户端
      // 设备ID与 Rust 端保持一致：使用 Blake3 哈希
      // server_id = blake3::hash(b"rockzero-server-device-id")
      // client_id = blake3::hash(user_id.as_bytes())
      final deviceIdSelf = _generateClientDeviceId(userId);
      final deviceIdPeer = _generateServerDeviceId();

      debugPrint('[SAE Handshake] Client device ID (Blake3): ${base64Encode(deviceIdSelf)}');
      debugPrint('[SAE Handshake] Server device ID (Blake3): ${base64Encode(deviceIdPeer)}');

      final saeClient = SaeClientCurve25519(
        password: Uint8List.fromList(utf8.encode(password)),
        deviceIdSelf: deviceIdSelf,
        deviceIdPeer: deviceIdPeer,
      );

      // 2. 生成客户端 Commit
      final clientCommit = saeClient.generateCommit();
      debugPrint('[SAE Handshake] Generated client commit');
      debugPrint(
          '[SAE Handshake] Client commit scalar length: ${(clientCommit['scalar'] as String).length}');
      debugPrint(
          '[SAE Handshake] Client commit element length: ${(clientCommit['element'] as String).length}');

      // 3. 初始化 SAE 握手（发送到后端）
      final initResponse = await _initSaeHandshake(filePath);
      final tempSessionId = initResponse['temp_session_id'] as String;
      debugPrint('[SAE Handshake] Initialized, temp session: $tempSessionId');

      // 4. 发送客户端 commit 并接收服务器 commit
      final serverCommitResponse = await _sendClientCommit(
        tempSessionId: tempSessionId,
        clientCommit: clientCommit,
      );
      debugPrint('[SAE Handshake] Received server commit');

      // 5. 处理服务器的 Commit
      final serverCommit =
          serverCommitResponse['server_commit'] as Map<String, dynamic>;
      saeClient.processCommit(serverCommit);
      debugPrint('[SAE Handshake] Processed server commit');

      // 6. 生成客户端 Confirm（现在可以生成真正的 confirm 了）
      final clientConfirm = saeClient.generateConfirm();
      debugPrint('[SAE Handshake] Generated client confirm');

      // 7. 发送客户端 confirm 并接收服务器 confirm
      final serverConfirmResponse = await _sendClientConfirm(
        tempSessionId: tempSessionId,
        clientConfirm: clientConfirm,
      );
      debugPrint('[SAE Handshake] Received server confirm');

      // 8. 验证服务器的 Confirm
      final serverConfirm =
          serverConfirmResponse['server_confirm'] as Map<String, dynamic>;
      saeClient.verifyConfirm(serverConfirm);
      debugPrint('[SAE Handshake] Verified server confirm');

      // 9. 创建 HLS 会话
      final sessionResponse = await _createHlsSession(
        tempSessionId: tempSessionId,
        filePath: filePath,
      );

      final sessionId = sessionResponse['session_id'] as String;
      debugPrint('[SAE Handshake] Created HLS session: $sessionId');

      // 10. 获取 PMK
      final pmk = saeClient.getPmk();
      debugPrint('[SAE Handshake] Got PMK (${pmk.length} bytes)');

      return (sessionId, pmk);
    } catch (e, stack) {
      debugPrint('[SAE Handshake] Error: $e');
      debugPrint('[SAE Handshake] Stack: $stack');
      rethrow;
    }
  }

  /// 步骤 1: 初始化 SAE 握手
  Future<Map<String, dynamic>> _initSaeHandshake(String filePath) async {
    final url = Uri.parse('$baseUrl/api/v1/secure-hls/sae/init');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({
        'file_path': filePath,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'SAE init failed: ${response.statusCode} - ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// 步骤 2: 发送客户端 Commit
  Future<Map<String, dynamic>> _sendClientCommit({
    required String tempSessionId,
    required Map<String, dynamic> clientCommit,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/secure-hls/sae/commit');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({
        'temp_session_id': tempSessionId,
        'client_commit': clientCommit,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'SAE commit failed: ${response.statusCode} - ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// 步骤 3: 发送客户端 Confirm
  Future<Map<String, dynamic>> _sendClientConfirm({
    required String tempSessionId,
    required Map<String, dynamic> clientConfirm,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/secure-hls/sae/confirm');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({
        'temp_session_id': tempSessionId,
        'client_confirm': clientConfirm,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'SAE confirm failed: ${response.statusCode} - ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// 步骤 4: 创建 HLS 会话
  Future<Map<String, dynamic>> _createHlsSession({
    required String tempSessionId,
    required String filePath,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/secure-hls/session/create');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({
        'temp_session_id': tempSessionId,
        'file_path': filePath,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Create session failed: ${response.statusCode} - ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// 生成服务器设备ID（32字节）
  /// 
  /// 与 Rust 端保持一致：blake3::hash(b"rockzero-server-device-id")
  Uint8List _generateServerDeviceId() {
    const serverIdString = 'rockzero-server-device-id';
    final hash = blake3.blake3(utf8.encode(serverIdString), 32);
    return Uint8List.fromList(hash);
  }

  /// 生成客户端设备ID（32字节）
  /// 
  /// 与 Rust 端保持一致：blake3::hash(user_id.as_bytes())
  Uint8List _generateClientDeviceId(String userId) {
    final hash = blake3.blake3(utf8.encode(userId), 32);
    return Uint8List.fromList(hash);
  }
}
