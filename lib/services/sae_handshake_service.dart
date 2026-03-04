import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:thirds/blake3.dart' as blake3;

import 'hkdf_blake3.dart';
import 'sae_client_curve25519.dart';

class SaeHandshakeService {
  final String baseUrl;
  final String jwtToken;

  static const Duration _requestTimeout = Duration(seconds: 20);

  SaeHandshakeService({
    required this.baseUrl,
    required this.jwtToken,
  });

  Future<(String, Uint8List)> performHandshake({
    required String filePath,
    required String password,
    required String userId,
    bool directMode = false,
  }) async {
    try {
      final deviceIdSelf = _generateClientDeviceId(userId);
      final deviceIdPeer = _generateServerDeviceId();
      final passwordBytes = Uint8List.fromList(utf8.encode(password));

      final saeClient = SaeClientCurve25519(
        password: passwordBytes,
        deviceIdSelf: deviceIdSelf,
        deviceIdPeer: deviceIdPeer,
      );

      // Step 1: Initialize
      final initResponse = await _initSaeHandshake(filePath);
      final tempSessionId = initResponse['temp_session_id'] as String;

      // Step 2: Commit
      final clientCommit = saeClient.generateCommit();
      final serverCommitResponse = await _sendClientCommit(
        tempSessionId: tempSessionId,
        clientCommit: clientCommit,
      );
      final serverCommit =
          serverCommitResponse['server_commit'] as Map<String, dynamic>;
      saeClient.processCommit(serverCommit);

      // Step 3: Confirm
      final clientConfirm = saeClient.generateConfirm();
      final serverConfirmResponse = await _sendClientConfirm(
        tempSessionId: tempSessionId,
        clientConfirm: clientConfirm,
      );
      final serverConfirm =
          serverConfirmResponse['server_confirm'] as Map<String, dynamic>;
      saeClient.verifyConfirm(serverConfirm);

      // Step 4: Create session (server-side ZKP registration)
      final sessionResponse = await _createHlsSession(
        tempSessionId: tempSessionId,
        filePath: filePath,
        directMode: directMode,
      );

      final sessionId = sessionResponse['session_id'] as String;
      final pmk = saeClient.getPmk();

      // Step 5: Verify key
      final serverKeyVerification =
          sessionResponse['key_verification'] as String?;
      if (serverKeyVerification != null) {
        final clientKeyVerification = _computeKeyVerification(sessionId, pmk);
        if (clientKeyVerification != serverKeyVerification) {
          throw Exception('Key verification failed');
        }
      }

      return (sessionId, pmk);
    } catch (e) {
      if (e.toString().contains('timeout')) {
        throw Exception('连接超时，请检查网络');
      }
      rethrow;
    }
  }

  String _computeKeyVerification(String sessionId, Uint8List pmk) {
    final hkdf = HkdfBlake3.withSessionSalt(sessionId, pmk);
    final encryptionKey =
        hkdf.expand(Uint8List.fromList(utf8.encode('hls-master-key')), 32);
    final input =
        Uint8List.fromList([...encryptionKey, ...utf8.encode(sessionId)]);
    final hash = blake3.blake3(input, 32);
    return hash
        .sublist(0, 16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<Map<String, dynamic>> _initSaeHandshake(String filePath) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/secure-hls/sae/init'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwtToken',
          },
          body: jsonEncode({'file_path': filePath}),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception('SAE init failed: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _sendClientCommit({
    required String tempSessionId,
    required Map<String, dynamic> clientCommit,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/secure-hls/sae/commit'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwtToken',
          },
          body: jsonEncode({
            'temp_session_id': tempSessionId,
            'client_commit': clientCommit,
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception('SAE commit failed: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _sendClientConfirm({
    required String tempSessionId,
    required Map<String, dynamic> clientConfirm,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/secure-hls/sae/confirm'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwtToken',
          },
          body: jsonEncode({
            'temp_session_id': tempSessionId,
            'client_confirm': clientConfirm,
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception('SAE confirm failed: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _createHlsSession({
    required String tempSessionId,
    required String filePath,
    bool directMode = false,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/secure-hls/session/create'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwtToken',
          },
          body: jsonEncode({
            'temp_session_id': tempSessionId,
            'file_path': filePath,
            'direct_mode': directMode,
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception('Create session failed: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Uint8List _generateServerDeviceId() {
    return Uint8List.fromList(
        blake3.blake3(utf8.encode('rockzero-server-device-id'), 32));
  }

  Uint8List _generateClientDeviceId(String userId) {
    return Uint8List.fromList(blake3.blake3(utf8.encode(userId), 32));
  }
}
