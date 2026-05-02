import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:rockzero/services/sae_handshake_service.dart';
import 'package:thirds/blake3.dart' as blake3;

class _AuthSession {
  final String accessToken;
  final String userId;

  const _AuthSession({
    required this.accessToken,
    required this.userId,
  });
}

Future<Map<String, Object?>> runSecureHlsPlaylistOnlyDiag({
  required String baseUrl,
  required String username,
  required String email,
  required String password,
  required String filePath,
  int holdSeconds = 10,
}) async {
  final normalizedFilePath = File(filePath).absolute.path;
  final file = File(normalizedFilePath);
  if (!file.existsSync()) {
    throw StateError('Smoke file does not exist: $normalizedFilePath');
  }

  final auth = await _registerOrLogin(
    baseUrl: baseUrl,
    username: username,
    email: email,
    password: password,
  );

  final saeSecret = _computeSaeSecret(password);
  final handshakeService = SaeHandshakeService(
    baseUrl: baseUrl,
    jwtToken: auth.accessToken,
  );

  stdout.writeln('Starting SAE handshake for $normalizedFilePath');
  final (sessionId, _) = await handshakeService.performHandshake(
    filePath: normalizedFilePath,
    password: saeSecret,
    userId: auth.userId,
    directMode: false,
  );

  final playlistUrl = '$baseUrl/api/v1/secure-hls/$sessionId/playlist.m3u8';

  stdout.writeln('Requesting playlist only: $playlistUrl');
  final playlistResponse = await http
      .get(Uri.parse(playlistUrl))
      .timeout(const Duration(seconds: 30));

  if (playlistResponse.statusCode != 200) {
    throw StateError(
      'Playlist request failed (${playlistResponse.statusCode}): ${playlistResponse.body}',
    );
  }

  final body = playlistResponse.body;
  final hasSegmentRef = body.contains('segment_');

  if (holdSeconds > 0) {
    stdout.writeln(
      'Holding without segment/proof requests for $holdSeconds seconds to observe backend liveness...',
    );
    await Future<void>.delayed(Duration(seconds: holdSeconds));
  }

  final healthBefore = await _checkHealth(baseUrl);
  final healthAfter = await _checkHealth(baseUrl);

  return {
    'success': true,
    'session_id': sessionId,
    'playlist_status': playlistResponse.statusCode,
    'playlist_length': body.length,
    'playlist_has_segment_reference': hasSegmentRef,
    'playlist_preview':
        body.substring(0, body.length > 512 ? 512 : body.length),
    'health_before': healthBefore,
    'health_after': healthAfter,
    'hold_seconds': holdSeconds,
  };
}

Future<void> main() async {
  final baseUrl =
      Platform.environment['ROCKZERO_BASE_URL'] ?? 'http://127.0.0.1:8080';
  final username = Platform.environment['ROCKZERO_SMOKE_USER'] ?? 'smoke_admin';
  final email =
      Platform.environment['ROCKZERO_SMOKE_EMAIL'] ?? 'smoke_admin@example.com';
  final password =
      Platform.environment['ROCKZERO_SMOKE_PASSWORD'] ?? 'SmokePass123';
  final rawFilePath = Platform.environment['ROCKZERO_SMOKE_FILE'];
  final holdSeconds = int.tryParse(
          Platform.environment['ROCKZERO_PLAYLIST_HOLD_SECONDS'] ?? '') ??
      10;

  if (rawFilePath == null || rawFilePath.trim().isEmpty) {
    stderr.writeln(
      'ROCKZERO_SMOKE_FILE is required and must point to a playable local media file.',
    );
    exitCode = 2;
    return;
  }

  try {
    final result = await runSecureHlsPlaylistOnlyDiag(
      baseUrl: baseUrl,
      username: username,
      email: email,
      password: password,
      filePath: rawFilePath,
      holdSeconds: holdSeconds,
    );
    stdout.writeln(jsonEncode(result));
  } catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  }
}

Future<_AuthSession> _registerOrLogin({
  required String baseUrl,
  required String username,
  required String email,
  required String password,
}) async {
  final client = http.Client();
  try {
    final loginUri = Uri.parse('$baseUrl/api/v1/auth/login');
    final registerUri = Uri.parse('$baseUrl/api/v1/auth/register');

    Future<_AuthSession> login() async {
      final response = await client.post(
        loginUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );
      if (response.statusCode != 200) {
        throw StateError(
          'Login failed (${response.statusCode}): ${response.body}',
        );
      }
      return _parseAuthResponse(response.body);
    }

    try {
      return await login();
    } catch (_) {
      final registerResponse = await client.post(
        registerUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
        }),
      );

      if (registerResponse.statusCode == 200) {
        return _parseAuthResponse(registerResponse.body);
      }

      return await login();
    }
  } finally {
    client.close();
  }
}

_AuthSession _parseAuthResponse(String body) {
  final payload = jsonDecode(body) as Map<String, dynamic>;
  final tokens = payload['tokens'] as Map<String, dynamic>?;
  final user = payload['user'] as Map<String, dynamic>?;
  final accessToken = tokens?['access_token'] as String?;
  final userId = user?['id'] as String?;

  if (accessToken == null || accessToken.isEmpty) {
    throw StateError('Auth response missing access_token: $body');
  }
  if (userId == null || userId.isEmpty) {
    throw StateError('Auth response missing user.id: $body');
  }

  return _AuthSession(accessToken: accessToken, userId: userId);
}

String _computeSaeSecret(String password) {
  final hash = blake3.blake3(utf8.encode(password), 32);
  return hash.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Future<bool> _checkHealth(String baseUrl) async {
  try {
    final response = await http
        .get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 5));
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}
