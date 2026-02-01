import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:thirds/blake3.dart' as blake3;

import 'sae_client_curve25519.dart';
import 'secure_hls_proxy.dart';

class SaeHandshakeService {
  final String baseUrl;
  final String jwtToken;

  SaeHandshakeService({
    required this.baseUrl,
    required this.jwtToken,
  });

  /// Performs SAE handshake and returns (sessionId, pmk)
  /// Throws exception if handshake fails or key verification fails
  Future<(String, Uint8List)> performHandshake({
    required String filePath,
    required String password,
    required String userId,
  }) async {
    try {
      // Generate device IDs matching Rust implementation exactly
      final deviceIdSelf = _generateClientDeviceId(userId);
      final deviceIdPeer = _generateServerDeviceId();

      // Create SAE client with password bytes
      final passwordBytes = Uint8List.fromList(utf8.encode(password));

      final saeClient = SaeClientCurve25519(
        password: passwordBytes,
        deviceIdSelf: deviceIdSelf,
        deviceIdPeer: deviceIdPeer,
      );

      final clientCommit = saeClient.generateCommit();

      // Step 1: Initialize SAE handshake
      final initResponse = await _initSaeHandshake(filePath);
      final tempSessionId = initResponse['temp_session_id'] as String;

      // Step 2: Send client commit and receive server commit
      final serverCommitResponse = await _sendClientCommit(
        tempSessionId: tempSessionId,
        clientCommit: clientCommit,
      );

      final serverCommit =
          serverCommitResponse['server_commit'] as Map<String, dynamic>;
      saeClient.processCommit(serverCommit);

      // Step 3: Generate and send client confirm
      final clientConfirm = saeClient.generateConfirm();

      // Step 4: Send client confirm and receive server confirm
      final serverConfirmResponse = await _sendClientConfirm(
        tempSessionId: tempSessionId,
        clientConfirm: clientConfirm,
      );

      final serverConfirm =
          serverConfirmResponse['server_confirm'] as Map<String, dynamic>;
      saeClient.verifyConfirm(serverConfirm);

      // Step 5: Create HLS session
      final sessionResponse = await _createHlsSession(
        tempSessionId: tempSessionId,
        filePath: filePath,
      );

      final sessionId = sessionResponse['session_id'] as String;
      final pmk = saeClient.getPmk();

      // Step 6: Verify key derivation matches server
      final serverKeyVerification =
          sessionResponse['key_verification'] as String?;
      if (serverKeyVerification != null) {
        final clientKeyVerification = _computeKeyVerification(sessionId, pmk);
        if (clientKeyVerification != serverKeyVerification) {
          debugPrint('[SAE] Key verification mismatch!');
          debugPrint('[SAE] Server: $serverKeyVerification');
          debugPrint('[SAE] Client: $clientKeyVerification');
          throw Exception(
              'Key derivation mismatch - encryption keys do not match');
        }
        debugPrint('[SAE] Key verification successful');
      }

      return (sessionId, pmk);
    } catch (e, stack) {
      debugPrint('[SAE] Error: $e');
      debugPrint('[SAE] Stack: $stack');
      rethrow;
    }
  }

  /// Compute key verification hash to match server
  String _computeKeyVerification(String sessionId, Uint8List pmk) {
    // Derive encryption key using same HKDF as proxy
    final hkdf = HkdfBlake3.withSessionSalt(sessionId, pmk);
    final info = Uint8List.fromList(utf8.encode('hls-master-key'));
    final encryptionKey = hkdf.expand(info, 32);

    // Compute verification hash: blake3(encryption_key + session_id)
    final input = Uint8List.fromList([
      ...encryptionKey,
      ...utf8.encode(sessionId),
    ]);
    final hash = blake3.blake3(input, 32);

    // Return first 16 bytes as hex
    return hash
        .sublist(0, 16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<Map<String, dynamic>> _initSaeHandshake(String filePath) async {
    final url = Uri.parse('$baseUrl/api/v1/secure-hls/sae/init');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({'file_path': filePath}),
    );

    if (response.statusCode != 200) {
      final body = response.body;
      throw Exception('SAE init failed: ${response.statusCode} - $body');
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
      final body = response.body;
      throw Exception('SAE commit failed: ${response.statusCode} - $body');
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
      final body = response.body;
      throw Exception('SAE confirm failed: ${response.statusCode} - $body');
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
      final body = response.body;
      throw Exception('Create session failed: ${response.statusCode} - $body');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Generate server device ID: blake3("rockzero-server-device-id")
  Uint8List _generateServerDeviceId() {
    const serverIdString = 'rockzero-server-device-id';
    final hash = blake3.blake3(utf8.encode(serverIdString), 32);
    return Uint8List.fromList(hash);
  }

  /// Generate client device ID: blake3(user_id)
  Uint8List _generateClientDeviceId(String userId) {
    final hash = blake3.blake3(utf8.encode(userId), 32);
    return Uint8List.fromList(hash);
  }
}
