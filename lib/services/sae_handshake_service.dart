import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:thirds/blake3.dart' as blake3;

import 'sae_client_curve25519.dart';

class SaeHandshakeService {
  final String baseUrl;
  final String jwtToken;

  SaeHandshakeService({
    required this.baseUrl,
    required this.jwtToken,
  });

  Future<(String, Uint8List)> performHandshake({
    required String filePath,
    required String password,
    required String userId,
  }) async {
    try {
      debugPrint('[SAE Handshake] Starting for file: $filePath');
      debugPrint('[SAE Handshake] User ID: $userId');
      debugPrint('[SAE Handshake] Password length: ${password.length}');
      debugPrint(
          '[SAE Handshake] Password (first 16 chars): ${password.substring(0, 16.clamp(0, password.length))}...');

      // Generate device IDs matching Rust implementation exactly
      final deviceIdSelf = _generateClientDeviceId(userId);
      final deviceIdPeer = _generateServerDeviceId();

      debugPrint(
          '[SAE Handshake] Client device ID (first 8 bytes): ${_bytesToHex(deviceIdSelf.sublist(0, 8))}');
      debugPrint(
          '[SAE Handshake] Server device ID (first 8 bytes): ${_bytesToHex(deviceIdPeer.sublist(0, 8))}');

      // Create SAE client with password bytes
      // 注意：password 已经是 blake3(原始密码) 的十六进制字符串
      final passwordBytes = Uint8List.fromList(utf8.encode(password));
      debugPrint(
          '[SAE Handshake] Password bytes length: ${passwordBytes.length}');
      debugPrint(
          '[SAE Handshake] Password bytes (first 16): ${_bytesToHex(passwordBytes.sublist(0, 16.clamp(0, passwordBytes.length)))}');

      final saeClient = SaeClientCurve25519(
        password: passwordBytes,
        deviceIdSelf: deviceIdSelf,
        deviceIdPeer: deviceIdPeer,
      );

      final clientCommit = saeClient.generateCommit();
      debugPrint('[SAE Handshake] Generated client commit');

      // Step 1: Initialize SAE handshake
      final initResponse = await _initSaeHandshake(filePath);
      final tempSessionId = initResponse['temp_session_id'] as String;
      debugPrint('[SAE Handshake] Initialized, temp session: $tempSessionId');

      // Step 2: Send client commit and receive server commit
      final serverCommitResponse = await _sendClientCommit(
        tempSessionId: tempSessionId,
        clientCommit: clientCommit,
      );
      debugPrint('[SAE Handshake] Received server commit');

      final serverCommit =
          serverCommitResponse['server_commit'] as Map<String, dynamic>;
      saeClient.processCommit(serverCommit);
      debugPrint('[SAE Handshake] Processed server commit');

      // Step 3: Generate and send client confirm
      final clientConfirm = saeClient.generateConfirm();
      debugPrint('[SAE Handshake] Generated client confirm');

      // Step 4: Send client confirm and receive server confirm
      final serverConfirmResponse = await _sendClientConfirm(
        tempSessionId: tempSessionId,
        clientConfirm: clientConfirm,
      );
      debugPrint('[SAE Handshake] Received server confirm');

      final serverConfirm =
          serverConfirmResponse['server_confirm'] as Map<String, dynamic>;
      saeClient.verifyConfirm(serverConfirm);
      debugPrint(
          '[SAE Handshake] Verified server confirm - SAE authenticated!');

      // Step 5: Create HLS session
      final sessionResponse = await _createHlsSession(
        tempSessionId: tempSessionId,
        filePath: filePath,
      );

      final sessionId = sessionResponse['session_id'] as String;
      debugPrint('[SAE Handshake] ✅ SAE Handshake Complete!');
      debugPrint('[SAE Handshake] Session ID: $sessionId');

      // Get the derived PMK
      final pmk = saeClient.getPmk();
      debugPrint(
          '[SAE Handshake] PMK (first 8 bytes): ${_bytesToHex(pmk.sublist(0, 8))}');

      return (sessionId, pmk);
    } catch (e, stack) {
      debugPrint('[SAE Handshake] Error: $e');
      debugPrint('[SAE Handshake] Stack: $stack');
      rethrow;
    }
  }

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

  /// Generate server device ID matching Rust implementation:
  /// `let server_id = blake3::hash(b"rockzero-server-device-id").into();`
  Uint8List _generateServerDeviceId() {
    const serverIdString = 'rockzero-server-device-id';
    final hash = blake3.blake3(utf8.encode(serverIdString), 32);
    return Uint8List.fromList(hash);
  }

  /// Generate client device ID matching Rust implementation:
  /// `let client_id = blake3::hash(user_id.as_bytes()).into();`
  Uint8List _generateClientDeviceId(String userId) {
    final hash = blake3.blake3(utf8.encode(userId), 32);
    return Uint8List.fromList(hash);
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
