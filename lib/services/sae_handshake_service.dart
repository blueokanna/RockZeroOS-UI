import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'sae_client.dart';

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
  Future<(String, Uint8List)> performHandshake({
    required String filePath,
    required String password,
  }) async {
    try {
      debugPrint('[SAE Handshake] Starting for file: $filePath');

      // 1. 创建 SAE 客户端
      final deviceIdSelf = _generateDeviceId('client');
      final deviceIdPeer = _generateDeviceId('server');

      final saeClient = SaeClient(
        password: Uint8List.fromList(utf8.encode(password)),
        deviceIdSelf: deviceIdSelf,
        deviceIdPeer: deviceIdPeer,
      );

      // 2. 生成客户端 Commit
      final clientCommit = saeClient.generateCommit();
      debugPrint('[SAE Handshake] Generated client commit');

      // 3. 初始化 SAE 握手（发送到后端）
      final initResponse = await _initSaeHandshake(filePath);
      final tempSessionId = initResponse['temp_session_id'] as String;
      debugPrint('[SAE Handshake] Initialized, temp session: $tempSessionId');

      // 4. 完成 SAE 握手（发送 commit 和 confirm）
      final serverCommit = await _completeSaeHandshake(
        tempSessionId: tempSessionId,
        clientCommit: clientCommit,
      );
      debugPrint('[SAE Handshake] Received server commit');

      // 5. 处理服务器的 Commit
      saeClient.processCommit(serverCommit['server_commit']);
      debugPrint('[SAE Handshake] Processed server commit');

      // 6. 验证服务器的 Confirm
      saeClient.verifyConfirm(serverCommit['server_confirm']);
      debugPrint('[SAE Handshake] Verified server confirm');

      // 8. 创建 HLS 会话
      final sessionResponse = await _createHlsSession(
        tempSessionId: tempSessionId,
        filePath: filePath,
      );

      final sessionId = sessionResponse['session_id'] as String;
      debugPrint('[SAE Handshake] Created HLS session: $sessionId');

      // 9. 获取 PMK
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

  /// 步骤 2: 完成 SAE 握手
  Future<Map<String, dynamic>> _completeSaeHandshake({
    required String tempSessionId,
    required Map<String, dynamic> clientCommit,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/secure-hls/sae/complete');

    // 生成客户端 Confirm（临时，用于发送）
    final clientConfirm = {
      'send_confirm': 1,
      'confirm': 'placeholder', // 后端会忽略这个值
    };

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({
        'temp_session_id': tempSessionId,
        'client_commit': clientCommit,
        'client_confirm': clientConfirm,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'SAE complete failed: ${response.statusCode} - ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// 步骤 3: 创建 HLS 会话
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

  /// 生成设备 ID（32 字节）
  Uint8List _generateDeviceId(String prefix) {
    final bytes = Uint8List(32);
    final prefixBytes = utf8.encode(prefix);

    // 填充前缀
    for (int i = 0; i < prefixBytes.length && i < 32; i++) {
      bytes[i] = prefixBytes[i];
    }

    // 填充剩余部分（使用固定值，生产环境应该使用设备唯一标识）
    for (int i = prefixBytes.length; i < 32; i++) {
      bytes[i] = i;
    }

    return bytes;
  }
}
