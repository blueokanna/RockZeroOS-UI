import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:thirds/blake3.dart' as blake3;

import 'bulletproofs_ffi.dart';
import 'sae_client_curve25519.dart';
import 'secure_hls_proxy.dart';

class SecureHlsPlayer {
  final String baseUrl;
  final String jwtToken;

  Uint8List? _pmk;
  String? _sessionId;
  String? _filePath;

  HlsEncryptor? _encryptor;
  SecureHlsProxyServer? _proxy;
  BulletproofsService? _bulletproofsService;

  String? _proxyPlaylistUrl;

  SecureHlsPlayer({
    required this.baseUrl,
    required this.jwtToken,
  });

  Future<void> initializeSaeHandshake(
    String userId,
    String password, {
    String? fileId,
    String? filePath,
  }) async {
    if (fileId == null && filePath == null) {
      throw ArgumentError('Either fileId or filePath must be provided');
    }

    debugPrint('[SecureHLS] Starting SAE handshake for user: $userId');

    _bulletproofsService = BulletproofsService(
      baseUrl: baseUrl,
      jwtToken: jwtToken,
    );
    await _bulletproofsService!.initialize();

    final deviceIdSelf = Uint8List.fromList(
      blake3.blake3(utf8.encode(userId), 32),
    );
    final deviceIdPeer = Uint8List.fromList(
      blake3.blake3(utf8.encode('rockzero-server-device-id'), 32),
    );

    debugPrint(
        '[SecureHLS] Client device ID: ${_bytesToHex(deviceIdSelf.sublist(0, 8))}...');

    final saeClient = SaeClientCurve25519(
      password: Uint8List.fromList(utf8.encode(password)),
      deviceIdSelf: deviceIdSelf,
      deviceIdPeer: deviceIdPeer,
    );

    final clientCommit = saeClient.generateCommit();

    debugPrint('[SecureHLS] Step 1: Initializing SAE handshake...');
    final initResponse = await _httpPost(
      '$baseUrl/api/v1/secure-hls/sae/init',
      body: {
        'file_id': fileId,
        'file_path': filePath,
      },
    );

    final tempSessionId = initResponse['temp_session_id'] as String;
    _filePath = initResponse['file_path'] as String?;
    debugPrint('[SecureHLS] Temp session: $tempSessionId');

    debugPrint('[SecureHLS] Step 2: Sending client commit...');
    final commitResponse = await _httpPost(
      '$baseUrl/api/v1/secure-hls/sae/commit',
      body: {
        'temp_session_id': tempSessionId,
        'client_commit': clientCommit,
      },
    );

    final serverCommit =
        commitResponse['server_commit'] as Map<String, dynamic>;
    saeClient.processCommit(serverCommit);

    debugPrint('[SecureHLS] Step 3: Sending client confirm...');
    final clientConfirm = saeClient.generateConfirm();
    final confirmResponse = await _httpPost(
      '$baseUrl/api/v1/secure-hls/sae/confirm',
      body: {
        'temp_session_id': tempSessionId,
        'client_confirm': clientConfirm,
      },
    );

    final serverConfirm =
        confirmResponse['server_confirm'] as Map<String, dynamic>;
    saeClient.verifyConfirm(serverConfirm);

    _pmk = saeClient.getPmk();
    debugPrint('[SecureHLS] SAE handshake completed');
    debugPrint(
        '[SecureHLS] PMK (first 8 bytes): ${_bytesToHex(_pmk!.sublist(0, 8))}');

    debugPrint('[SecureHLS] Step 4: Creating HLS session...');
    final sessionResponse = await _httpPost(
      '$baseUrl/api/v1/secure-hls/session/create',
      body: {
        'temp_session_id': tempSessionId,
        'file_id': fileId,
        'file_path': filePath,
      },
    );

    _sessionId = sessionResponse['session_id'] as String;
    debugPrint('[SecureHLS] HLS session created: $_sessionId');

    _encryptor = HlsEncryptor(sessionId: _sessionId!, pmk: _pmk!);

    _proxy = SecureHlsProxyServer(
      baseUrl: baseUrl,
      sessionId: _sessionId!,
      pmk: _pmk!,
      jwtToken: jwtToken,
    );

    _proxyPlaylistUrl = await _proxy!.start();
    debugPrint('[SecureHLS] Proxy started: $_proxyPlaylistUrl');
  }

  Future<String> getProxyPlaylistUrl() async {
    if (_proxyPlaylistUrl == null) {
      throw StateError('SAE handshake not completed');
    }
    return _proxyPlaylistUrl!;
  }

  Future<VideoStreamProof?> createSegmentProof(
    int segmentIndex,
    Uint8List content,
  ) async {
    if (_bulletproofsService == null || _sessionId == null) {
      debugPrint('[SecureHLS] Cannot create proof: service not initialized');
      return null;
    }

    return _bulletproofsService!.createVideoStreamProof(
      sessionId: _sessionId!,
      segmentIndex: segmentIndex,
      content: content,
    );
  }

  Future<void> stop() async {
    await _proxy?.stop();
    _proxy = null;

    if (_sessionId != null) {
      try {
        await _httpPost(
          '$baseUrl/api/v1/secure-hls/$_sessionId/stop',
          body: {},
        );
        debugPrint('[SecureHLS] Session stopped on server');
      } catch (e) {
        debugPrint('[SecureHLS] Failed to stop session on server: $e');
      }
    }

    _sessionId = null;
    _pmk = null;
    _encryptor = null;
    _bulletproofsService = null;
    _filePath = null;
    _proxyPlaylistUrl = null;

    debugPrint('[SecureHLS] Player stopped and cleaned up');
  }

  Future<Map<String, dynamic>> _httpPost(
    String url, {
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse(url);
    final request = await HttpClient().postUrl(uri);

    request.headers.contentType = ContentType.json;
    if (jwtToken.isNotEmpty) {
      request.headers.add('Authorization', 'Bearer $jwtToken');
    }

    request.write(jsonEncode(body));
    final response = await request.close();

    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $responseBody');
    }

    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String? get sessionId => _sessionId;
  Uint8List? get pmk => _pmk;
  String? get filePath => _filePath;
  bool get isInitialized => _sessionId != null && _pmk != null;
  HlsEncryptor? get encryptor => _encryptor;
  SecureHlsProxyServer? get proxy => _proxy;
}
