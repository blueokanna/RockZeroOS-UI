import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:thirds/blake3.dart' as blake3;
import 'package:video_player/video_player.dart';

import 'sae_client.dart';
import 'secure_hls_proxy.dart';

class SecureHlsPlayer {
  final String baseUrl;
  final String jwtToken;
  static const int _requiredSaeGroup = 19;

  Uint8List? _pmk;
  String? _sessionId;
  String? _password;

  SecureHlsProxyServer? _proxy;
  VideoPlayerController? _controller;

  SecureHlsPlayer({
    required this.baseUrl,
    required this.jwtToken,
  });

  bool _isSuccessStatus(int statusCode) =>
      statusCode >= 200 && statusCode < 300;

  Future<void> initializeSaeHandshake(
    String userId,
    String password,
    String fileId,
  ) async {
    _password = password;

    final normalizedClientId =
        Uint8List.fromList(blake3.blake3(utf8.encode(userId), 32));
    final normalizedServerId = Uint8List.fromList(
      blake3.blake3(utf8.encode('rockzero-server-device-id'), 32),
    );

    final saeClient = SaeClient(
      password: Uint8List.fromList(utf8.encode(password)),
      deviceIdSelf: normalizedClientId,
      deviceIdPeer: normalizedServerId,
    );

    final clientCommit = saeClient.generateCommit();

    final initResponse = await http.post(
      Uri.parse('$baseUrl/api/v1/secure-hls/sae/init'),
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'user_id': userId, 'file_id': fileId}),
    );

    if (!_isSuccessStatus(initResponse.statusCode)) {
      throw Exception('SAE init failed: ${initResponse.body}');
    }

    final initData = jsonDecode(initResponse.body) as Map<String, dynamic>;
    final tempSessionId = initData['temp_session_id'];
    final antiCloggingToken = initData['anti_clogging_token'];
    final selectedGroup = initData['selected_group'];
    final supportedGroups = initData['supported_groups'];

    if (antiCloggingToken == null ||
        antiCloggingToken is! String ||
        antiCloggingToken.isEmpty) {
      throw Exception('SAE anti-clogging token is missing');
    }
    if (selectedGroup is! int || selectedGroup != _requiredSaeGroup) {
      throw Exception(
          'SAE selected_group invalid: expected $_requiredSaeGroup, got $selectedGroup');
    }
    if (supportedGroups is! List ||
        !supportedGroups.any((g) => g == _requiredSaeGroup)) {
      throw Exception(
          'SAE supported_groups does not include required group $_requiredSaeGroup');
    }

    final commitResponse = await http.post(
      Uri.parse('$baseUrl/api/v1/secure-hls/sae/commit'),
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'temp_session_id': tempSessionId,
        'client_commit': clientCommit,
        'anti_clogging_token': antiCloggingToken,
      }),
    );

    if (!_isSuccessStatus(commitResponse.statusCode)) {
      throw Exception('SAE commit failed: ${commitResponse.body}');
    }

    final commitData = jsonDecode(commitResponse.body) as Map<String, dynamic>;
    final serverCommit = commitData['server_commit'] as Map<String, dynamic>;
    saeClient.processCommit(serverCommit);

    final clientConfirm = saeClient.generateConfirm();
    final confirmResponse = await http.post(
      Uri.parse('$baseUrl/api/v1/secure-hls/sae/confirm'),
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'temp_session_id': tempSessionId,
        'client_confirm': clientConfirm,
        'anti_clogging_token': antiCloggingToken,
      }),
    );

    if (!_isSuccessStatus(confirmResponse.statusCode)) {
      throw Exception('SAE confirm failed: ${confirmResponse.body}');
    }

    final confirmData =
        jsonDecode(confirmResponse.body) as Map<String, dynamic>;
    final serverConfirm = confirmData['server_confirm'] as Map<String, dynamic>;
    saeClient.verifyConfirm(serverConfirm);
    _pmk = saeClient.getPmk();

    final sessionResponse = await http.post(
      Uri.parse('$baseUrl/api/v1/secure-hls/session/create'),
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'temp_session_id': tempSessionId, 'file_id': fileId}),
    );

    if (!_isSuccessStatus(sessionResponse.statusCode)) {
      throw Exception('Session create failed: ${sessionResponse.body}');
    }

    final sessionData =
        jsonDecode(sessionResponse.body) as Map<String, dynamic>;
    _sessionId = sessionData['session_id']?.toString();
    if (_sessionId == null || _sessionId!.isEmpty) {
      throw Exception('Session id missing from secure-hls response');
    }
  }

  Future<VideoPlayerController> play() async {
    final playlistUrl = await getProxyPlaylistUrl();

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(playlistUrl),
      httpHeaders: const {},
    );

    await _controller!.initialize();
    return _controller!;
  }

  Future<String> getProxyPlaylistUrl() async {
    if (_sessionId == null || _pmk == null) {
      throw Exception('SAE handshake not completed');
    }
    if (_password == null) {
      throw Exception('Password not available for SAE session continuity');
    }

    _proxy ??= SecureHlsProxyServer(
      baseUrl: baseUrl,
      sessionId: _sessionId!,
      pmk: _pmk!,
      password: _password!,
      jwtToken: jwtToken,
    );

    return _proxy!.start();
  }

  String getDirectPlaylistUrl() {
    if (_sessionId == null) {
      throw Exception('SAE handshake not completed');
    }
    return '$baseUrl/api/v1/secure-hls/$_sessionId/playlist.m3u8';
  }

  Future<void> stop() async {
    final sid = _sessionId;
    if (sid != null) {
      try {
        await http.post(
          Uri.parse('$baseUrl/api/v1/secure-hls/$sid/stop'),
          headers: {
            if (jwtToken.isNotEmpty) 'Authorization': 'Bearer $jwtToken',
          },
        ).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }

    await _proxy?.stop();
    _proxy = null;
    await _controller?.dispose();
    _controller = null;
    _sessionId = null;
    _pmk = null;
    _password = null;
  }

  VideoPlayerController? get controller => _controller;
  SecureHlsProxyServer? get proxy => _proxy;
  String? get sessionId => _sessionId;
  Uint8List? get pmk => _pmk;
}
