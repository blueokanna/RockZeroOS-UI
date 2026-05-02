import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:rockzero/services/sae_handshake_service.dart';
import 'package:rockzero/services/secure_hls_proxy.dart';
import 'package:thirds/blake3.dart' as blake3;

class _AuthSession {
  final String accessToken;
  final String userId;

  const _AuthSession({
    required this.accessToken,
    required this.userId,
  });
}

Future<Map<String, Object>> runSecureHlsSmoke({
  required String baseUrl,
  required String username,
  required String email,
  required String password,
  required String filePath,
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
  final (sessionId, pmk) = await handshakeService.performHandshake(
    filePath: normalizedFilePath,
    password: saeSecret,
    userId: auth.userId,
    directMode: false,
  );
  stdout.writeln('Secure HLS session created: $sessionId');

  final proxyServer = SecureHlsProxyServer(
    baseUrl: baseUrl,
    sessionId: sessionId,
    pmk: pmk,
    password: saeSecret,
    jwtToken: auth.accessToken,
  );

  final proxyPlaylistUrl = await proxyServer.start();
  stdout.writeln('Proxy playlist URL: $proxyPlaylistUrl');

  try {
    final playlistBody = await _waitForPlayablePlaylist(proxyPlaylistUrl);
    final segmentUrl = _extractFirstSegmentUrl(playlistBody);
    if (segmentUrl == null) {
      throw StateError(
          'Playlist became ready but did not contain a segment URL.');
    }

    stdout.writeln('Fetching first decrypted segment: $segmentUrl');
    final segmentBytes = await _waitForSegment(segmentUrl);
    final syncByte = segmentBytes.first;
    if (syncByte != 0x47) {
      throw StateError(
        'First segment is not valid MPEG-TS after proxy decryption. Expected sync byte 0x47, got 0x${syncByte.toRadixString(16).padLeft(2, '0')}.',
      );
    }

    return {
      'success': true,
      'session_id': sessionId,
      'playlist_has_segments': true,
      'first_segment_bytes': segmentBytes.length,
      'first_sync_byte': syncByte,
    };
  } finally {
    await proxyServer.stop();
  }
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

  if (rawFilePath == null || rawFilePath.trim().isEmpty) {
    stderr.writeln(
      'ROCKZERO_SMOKE_FILE is required and must point to a playable local media file.',
    );
    exitCode = 2;
    return;
  }

  try {
    final result = await runSecureHlsSmoke(
      baseUrl: baseUrl,
      username: username,
      email: email,
      password: password,
      filePath: rawFilePath,
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

Future<String> _waitForPlayablePlaylist(String proxyPlaylistUrl) async {
  final client = http.Client();
  try {
    final uri = Uri.parse(proxyPlaylistUrl);
    for (var attempt = 0; attempt < 60; attempt++) {
      final response = await client.get(uri);
      if (response.statusCode == 200 && response.body.contains('segment_')) {
        return response.body;
      }

      await Future<void>.delayed(const Duration(seconds: 1));
    }
  } finally {
    client.close();
  }

  throw TimeoutException(
      'Timed out waiting for playlist segments to become ready.');
}

String? _extractFirstSegmentUrl(String playlistBody) {
  final match = RegExp(r'http://127\.0\.0\.1:\d+/segment_\d+\.ts')
      .firstMatch(playlistBody);
  return match?.group(0);
}

Future<List<int>> _waitForSegment(String segmentUrl) async {
  final client = http.Client();
  try {
    final uri = Uri.parse(segmentUrl);
    for (var attempt = 0; attempt < 30; attempt++) {
      final response = await client.get(uri);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }

      await Future<void>.delayed(const Duration(seconds: 1));
    }
  } finally {
    client.close();
  }

  throw TimeoutException(
      'Timed out waiting for first segment to be decrypted.');
}
