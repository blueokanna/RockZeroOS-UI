import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:thirds/blake3.dart' as blake3;

import 'hkdf_blake3.dart';
import 'sae_client_curve25519.dart';

enum SaeStage {
  init,
  commit,
  confirm,
  createSession,
}

class SaeHandshakeException implements Exception {
  final SaeStage stage;
  final int statusCode;
  final String message;

  const SaeHandshakeException({
    required this.stage,
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() =>
      'SaeHandshakeException(stage: $stage, status: $statusCode, message: $message)';
}

class SaeHandshakeService {
  final String baseUrl;
  final String jwtToken;
  static const int _requiredSaeGroup = 19;

  static const Duration _requestTimeout = Duration(seconds: 20);

  SaeHandshakeService({
    required this.baseUrl,
    required this.jwtToken,
  });

  bool _isSuccessStatus(int statusCode) =>
      statusCode >= 200 && statusCode < 300;

  String _extractBackendMessage(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) {
        final msg = parsed['message'];
        final err = parsed['error'];
        if (msg is String && msg.isNotEmpty) return msg;
        if (err is String && err.isNotEmpty) return err;
      }
    } catch (_) {}
    return body;
  }

  Future<(String, Uint8List)> performHandshake({
    String? filePath,
    String? fileId,
    required String password,
    required String userId,
    bool directMode = false,
  }) async {
    try {
      if ((filePath == null || filePath.isEmpty) &&
          (fileId == null || fileId.isEmpty)) {
        throw Exception('Either filePath or fileId must be provided');
      }

      final deviceIdSelf = _generateClientDeviceId(userId);
      final deviceIdPeer = _generateServerDeviceId();
      final passwordBytes = Uint8List.fromList(utf8.encode(password));

      final saeClient = SaeClientCurve25519(
        password: passwordBytes,
        deviceIdSelf: deviceIdSelf,
        deviceIdPeer: deviceIdPeer,
      );

      // Step 1: Initialize
      final initResponse = await _initSaeHandshake(
        filePath: filePath,
        fileId: fileId,
      );
      final tempSessionId = initResponse['temp_session_id'] as String;
      final antiCloggingToken =
          initResponse['anti_clogging_token'] as String? ?? '';

      if (antiCloggingToken.isEmpty) {
        throw Exception('SAE anti-clogging token missing from init response');
      }

      final selectedGroup = initResponse['selected_group'];
      if (selectedGroup is! int || selectedGroup != _requiredSaeGroup) {
        throw Exception(
          'SAE selected_group invalid: expected $_requiredSaeGroup, got $selectedGroup',
        );
      }

      final supportedGroups = initResponse['supported_groups'];
      if (supportedGroups is List) {
        final hasRequired = supportedGroups.any((g) => g == _requiredSaeGroup);
        if (!hasRequired) {
          throw Exception(
            'SAE supported_groups does not include required group $_requiredSaeGroup',
          );
        }
      } else {
        throw Exception('SAE supported_groups missing or invalid');
      }

      // Step 2: Commit
      final clientCommit = saeClient.generateCommit();
      final serverCommitResponse = await _sendClientCommit(
        tempSessionId: tempSessionId,
        clientCommit: clientCommit,
        antiCloggingToken: antiCloggingToken,
      );
      final serverCommit =
          serverCommitResponse['server_commit'] as Map<String, dynamic>;
      saeClient.processCommit(serverCommit);

      // Step 3: Confirm
      final clientConfirm = saeClient.generateConfirm();
      final serverConfirmResponse = await _sendClientConfirm(
        tempSessionId: tempSessionId,
        clientConfirm: clientConfirm,
        antiCloggingToken: antiCloggingToken,
      );
      final serverConfirm =
          serverConfirmResponse['server_confirm'] as Map<String, dynamic>;
      saeClient.verifyConfirm(serverConfirm);

      // Step 4: Create session (server-side ZKP registration)
      final sessionResponse = await _createHlsSession(
        tempSessionId: tempSessionId,
        filePath: filePath,
        fileId: fileId,
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

  Future<Map<String, dynamic>> _initSaeHandshake({
    String? filePath,
    String? fileId,
  }) async {
    final payload = <String, dynamic>{};
    if (fileId != null && fileId.isNotEmpty) {
      payload['file_id'] = fileId;
    } else if (filePath != null && filePath.isNotEmpty) {
      payload['file_path'] = filePath;
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/secure-hls/sae/init'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwtToken',
          },
          body: jsonEncode(payload),
        )
        .timeout(_requestTimeout);

    if (!_isSuccessStatus(response.statusCode)) {
      throw SaeHandshakeException(
        stage: SaeStage.init,
        statusCode: response.statusCode,
        message: _extractBackendMessage(response.body),
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _sendClientCommit({
    required String tempSessionId,
    required Map<String, dynamic> clientCommit,
    required String antiCloggingToken,
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
            'anti_clogging_token': antiCloggingToken,
          }),
        )
        .timeout(_requestTimeout);

    if (!_isSuccessStatus(response.statusCode)) {
      throw SaeHandshakeException(
        stage: SaeStage.commit,
        statusCode: response.statusCode,
        message: _extractBackendMessage(response.body),
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _sendClientConfirm({
    required String tempSessionId,
    required Map<String, dynamic> clientConfirm,
    required String antiCloggingToken,
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
            'anti_clogging_token': antiCloggingToken,
          }),
        )
        .timeout(_requestTimeout);

    if (!_isSuccessStatus(response.statusCode)) {
      throw SaeHandshakeException(
        stage: SaeStage.confirm,
        statusCode: response.statusCode,
        message: _extractBackendMessage(response.body),
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _createHlsSession({
    required String tempSessionId,
    String? filePath,
    String? fileId,
    bool directMode = false,
  }) async {
    final payload = <String, dynamic>{
      'temp_session_id': tempSessionId,
      'direct_mode': directMode,
    };
    if (fileId != null && fileId.isNotEmpty) {
      payload['file_id'] = fileId;
    } else if (filePath != null && filePath.isNotEmpty) {
      payload['file_path'] = filePath;
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/secure-hls/session/create'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwtToken',
          },
          body: jsonEncode(payload),
        )
        .timeout(_requestTimeout);

    if (!_isSuccessStatus(response.statusCode)) {
      throw SaeHandshakeException(
        stage: SaeStage.createSession,
        statusCode: response.statusCode,
        message: _extractBackendMessage(response.body),
      );
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
