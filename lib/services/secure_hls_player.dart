import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:thirds/blake3.dart' as blake3;
import 'package:video_player/video_player.dart';

import 'hkdf_blake3.dart';
import 'zkp/hls_bulletproof_auth.dart';
import 'sae_client.dart';
import 'secure_hls_proxy.dart';

class SecureHlsPlayer {
  final String baseUrl;
  final String jwtToken;
  static const int _requiredSaeGroup = 19;

  Uint8List? _pmk; // Pairwise Master Key
  String? _sessionId;
  String? _password;

  PasswordRegistration? _zkpRegistration;

  late final HlsBulletproofAuth _bulletproofAuth;

  HlsEncryptor? _encryptor;
  SecureHlsProxyServer? _proxy;

  VideoPlayerController? _controller;

  SecureHlsPlayer({
    required this.baseUrl,
    required this.jwtToken,
  }) {
    _bulletproofAuth = HlsBulletproofAuth();
  }

  bool _isSuccessStatus(int statusCode) =>
      statusCode >= 200 && statusCode < 300;

  Future<void> initializeSaeHandshake(
    String userId,
    String password, {
    String? fileId,
    String? filePath,
  }) async {
    if ((fileId == null || fileId.isEmpty) &&
        (filePath == null || filePath.isEmpty)) {
      throw Exception('Either fileId or filePath must be provided');
    }

    debugPrint('[SecureHLS] Starting SAE handshake for user: $userId');

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
      body: jsonEncode({
        'user_id': userId,
        if (fileId != null && fileId.isNotEmpty) 'file_id': fileId,
        if (filePath != null && filePath.isNotEmpty) 'file_path': filePath,
      }),
    );

    if (!_isSuccessStatus(initResponse.statusCode)) {
      throw Exception('SAE init failed: ${initResponse.body}');
    }

    final initData = jsonDecode(initResponse.body);
    final tempSessionId = initData['temp_session_id'];
    final antiCloggingToken = initData['anti_clogging_token'];

    if (antiCloggingToken == null ||
        (antiCloggingToken is String && antiCloggingToken.isEmpty)) {
      throw Exception('SAE anti-clogging token is missing');
    }

    final selectedGroup = initData['selected_group'];
    if (selectedGroup is! int || selectedGroup != _requiredSaeGroup) {
      throw Exception(
        'SAE selected_group invalid: expected $_requiredSaeGroup, got $selectedGroup',
      );
    }

    final supportedGroups = initData['supported_groups'];
    if (supportedGroups is! List ||
        !supportedGroups.any((g) => g == _requiredSaeGroup)) {
      throw Exception(
        'SAE supported_groups does not include required group $_requiredSaeGroup',
      );
    }

    debugPrint('[SecureHLS] Got temp session: $tempSessionId');

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

    final commitData = jsonDecode(commitResponse.body);
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

    final confirmData = jsonDecode(confirmResponse.body);

    final serverConfirm = confirmData['server_confirm'] as Map<String, dynamic>;
    saeClient.verifyConfirm(serverConfirm);

    _pmk = saeClient.getPmk();
    debugPrint('[SecureHLS] SAE handshake completed, PMK obtained');

    final sessionResponse = await http.post(
      Uri.parse('$baseUrl/api/v1/secure-hls/session/create'),
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'temp_session_id': tempSessionId,
        if (fileId != null && fileId.isNotEmpty) 'file_id': fileId,
        if (filePath != null && filePath.isNotEmpty) 'file_path': filePath,
      }),
    );

    if (!_isSuccessStatus(sessionResponse.statusCode)) {
      throw Exception('Session create failed: ${sessionResponse.body}');
    }

    final sessionData = jsonDecode(sessionResponse.body);
    _sessionId = sessionData['session_id'];
    final zkpEnabled = sessionData['zkp_enabled'] ?? false;
    final directMode = sessionData['direct_mode'] ?? false;

    debugPrint('[SecureHLS] HLS session created: $_sessionId '
        '(ZKP: $zkpEnabled, direct: $directMode)');

    _encryptor = HlsEncryptor(
      pmk: _pmk!,
      sessionId: _sessionId!,
      password: password,
      zkpRegistration: _zkpRegistration,
      bulletproofAuth: _bulletproofAuth,
    );
  }

  Future<VideoPlayerController> play() async {
    if (_sessionId == null || _pmk == null) {
      throw Exception('SAE handshake not completed');
    }

    if (_encryptor == null) {
      throw Exception('Encryptor not initialized');
    }

    if (_password == null) {
      throw Exception('Password not available for ZKP proof generation');
    }

    _proxy ??= SecureHlsProxyServer(
      baseUrl: baseUrl,
      sessionId: _sessionId!,
      pmk: _pmk!,
      password: _password!,
      jwtToken: jwtToken,
    );

    final proxyPlaylistUrl = await _proxy!.start();

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(proxyPlaylistUrl),
      httpHeaders: const {},
    );

    await _controller!.initialize();

    debugPrint('[SecureHLS] Video player initialized via local proxy');

    return _controller!;
  }

  Future<VideoPlayerController> playDirect() async {
    if (_sessionId == null) {
      throw Exception(
          'SAE handshake not completed. Call initializeSaeHandshake() first.');
    }

    final playlistUrl = '$baseUrl/api/v1/secure-hls/$_sessionId/playlist.m3u8';
    debugPrint('[SecureHLS] Direct play mode: $playlistUrl');

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(playlistUrl),
      httpHeaders: const {},
    );

    await _controller!.initialize();
    debugPrint('[SecureHLS] Video player initialized (direct mode, no proxy)');

    return _controller!;
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
    _zkpRegistration = null;
    _encryptor = null;
  }

  VideoPlayerController? get controller => _controller;

  SecureHlsProxyServer? get proxy => _proxy;

  Future<String> getProxyPlaylistUrl() async {
    if (_sessionId == null || _pmk == null) {
      throw Exception('SAE handshake not completed');
    }

    if (_password == null) {
      throw Exception('Password not available for ZKP proof generation');
    }

    _proxy ??= SecureHlsProxyServer(
      baseUrl: baseUrl,
      sessionId: _sessionId!,
      pmk: _pmk!,
      password: _password!,
      jwtToken: jwtToken,
    );

    return await _proxy!.start();
  }

  String getDirectPlaylistUrl() {
    if (_sessionId == null) {
      throw Exception('SAE handshake not completed');
    }
    return '$baseUrl/api/v1/secure-hls/$_sessionId/playlist.m3u8';
  }

  String? get sessionId => _sessionId;

  Uint8List? get pmk => _pmk;

  PasswordRegistration? get zkpRegistration => _zkpRegistration;
}

class HlsEncryptor {
  final Uint8List pmk;
  final String sessionId;
  final String password;
  final PasswordRegistration? zkpRegistration;
  final HlsBulletproofAuth bulletproofAuth;
  late Uint8List _encryptionKey;

  HlsEncryptor({
    required this.pmk,
    required this.sessionId,
    required this.password,
    required this.zkpRegistration,
    required this.bulletproofAuth,
  }) {
    _encryptionKey = _deriveKey(pmk, 'hls-master-key');
  }

  String generateZkpProof() {
    if (zkpRegistration == null) {
      throw StateError(
        'ZKP registration data is required for Bulletproofs authentication',
      );
    }

    if (!bulletproofAuth.isInitialized) {
      if (!bulletproofAuth.initializeAuto()) {
        throw StateError(
          'Failed to initialize Bulletproofs FFI. '
          'Ensure the native library is available.',
        );
      }
    }

    debugPrint('[HlsEncryptor] Generating full Bulletproofs ZKP proof...');

    final proofBase64 = bulletproofAuth.generateProof(
      password,
      zkpRegistration!,
      context: 'hls_segment_access',
    );

    debugPrint('[HlsEncryptor] Bulletproofs ZKP proof generated');

    return proofBase64;
  }

  Future<Uint8List> decryptSegment(Uint8List encryptedData) async {
    if (encryptedData.length < 28) {
      throw Exception('Encrypted data too short for ChaCha20-Poly1305');
    }

    final nonce = encryptedData.sublist(0, 12);
    final ciphertext = encryptedData.sublist(12, encryptedData.length - 16);
    final macBytes = encryptedData.sublist(encryptedData.length - 16);

    final plaintext = await Chacha20.poly1305Aead().decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: Mac(macBytes)),
      secretKey: SecretKey(_encryptionKey),
    );

    return Uint8List.fromList(plaintext);
  }

  Uint8List _deriveKey(Uint8List key, String info) {
    final hkdf = HkdfBlake3.withSessionSalt(sessionId, key);
    return hkdf.expand(Uint8List.fromList(utf8.encode(info)), 32);
  }
}

class SecureHttpClient extends http.BaseClient {
  final String baseUrl;
  final String sessionId;
  final HlsEncryptor encryptor;
  final String jwtToken;
  final http.Client _inner = http.Client();

  SecureHttpClient({
    required this.baseUrl,
    required this.sessionId,
    required this.encryptor,
    required this.jwtToken,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();

    if (url.contains('.ts')) {
      debugPrint('[SecureHLS] Intercepting segment request: $url');

      final zkpProof = encryptor.generateZkpProof();

      final response = await http.post(
        request.url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
          ...request.headers,
        },
        body: jsonEncode({
          'zkp_proof': zkpProof,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('[SecureHLS] Segment request failed: ${response.body}');
        return http.StreamedResponse(
          Stream.value(Uint8List(0)),
          response.statusCode,
        );
      }

      final encryptedData = response.bodyBytes;
      final decryptedData = await encryptor.decryptSegment(encryptedData);

      debugPrint(
          '[SecureHLS] Segment decrypted: ${decryptedData.length} bytes');

      return http.StreamedResponse(
        Stream.value(decryptedData),
        200,
        headers: {'content-type': 'video/mp2t'},
      );
    }

    return _inner.send(request);
  }
}
