import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:thirds/blake3.dart' as blake3;
import 'package:video_player/video_player.dart';

import 'bulletproofs_ffi.dart';
import 'sae_client_curve25519.dart';
import 'secure_hls_proxy.dart';

/// Secure HLS Player
///
/// Implements complete secure video playback flow:
/// 1. SAE Handshake: WPA3-SAE key exchange, establish shared key (PMK)
/// 2. Session Creation: Create encrypted HLS session using PMK
/// 3. Local Proxy: Start local proxy server to intercept HLS requests
/// 4. Video Decryption: Decrypt video segments using AES-256-GCM
/// 5. ZKP Proof: Generate Bulletproofs proof for each video segment
class SecureHlsPlayer {
  final String baseUrl;
  final String jwtToken;

  Uint8List? _pmk;
  String? _sessionId;
  String? _filePath;

  HlsEncryptor? _encryptor;
  SecureHlsProxyServer? _proxy;
  BulletproofsService? _bulletproofsService;

  VideoPlayerController? _controller;

  SecureHlsPlayer({
    required this.baseUrl,
    required this.jwtToken,
  });

  /// Initialize SAE handshake and create HLS session
  ///
  /// [userId] - User ID
  /// [password] - User password (for SAE handshake)
  /// [fileId] - File ID (optional, use either fileId or filePath)
  /// [filePath] - File path (optional, use either fileId or filePath)
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

    // Initialize Bulletproofs service
    _bulletproofsService = BulletproofsService(
      baseUrl: baseUrl,
      jwtToken: jwtToken,
    );
    await _bulletproofsService!.initialize();

    // Generate device ID (using BLAKE3)
    final deviceIdSelf = Uint8List.fromList(
      blake3.blake3(utf8.encode(userId), 32),
    );
    final deviceIdPeer = Uint8List.fromList(
      blake3.blake3(utf8.encode('rockzero-server-device-id'), 32),
    );

    debugPrint(
        '[SecureHLS] Client device ID: ${_bytesToHex(deviceIdSelf.sublist(0, 8))}...');

    // Create SAE client
    final saeClient = SaeClientCurve25519(
      password: Uint8List.fromList(utf8.encode(password)),
      deviceIdSelf: deviceIdSelf,
      deviceIdPeer: deviceIdPeer,
    );

    // Generate client commit
    final clientCommit = saeClient.generateCommit();

    // Step 1: Initialize SAE handshake
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

    // Step 2: Send client commit
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

    // Step 3: Send client confirm
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

    // Get PMK
    _pmk = saeClient.getPmk();
    debugPrint('[SecureHLS] ✅ SAE handshake completed');
    debugPrint('[SecureHLS] PMK: ${_bytesToHex(_pmk!.sublist(0, 8))}...');

    // Step 4: Create HLS session
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
    debugPrint('[SecureHLS] ✅ HLS session created: $_sessionId');

    // Initialize encryptor
    _encryptor = HlsEncryptor(pmk: _pmk!);
  }

  /// Create ZKP proof for video segment
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

  /// Start video playback
  Future<VideoPlayerController> play() async {
    if (_sessionId == null || _pmk == null) {
      throw StateError('SAE handshake not completed');
    }

    if (_encryptor == null) {
      throw StateError('Encryptor not initialized');
    }

    // Create local proxy server
    _proxy ??= SecureHlsProxyServer(
      baseUrl: baseUrl,
      sessionId: _sessionId!,
      pmk: _pmk!,
      jwtToken: jwtToken,
      bulletproofsService: _bulletproofsService,
    );

    // Start proxy and get local playlist URL
    final proxyPlaylistUrl = await _proxy!.start();

    // Create video player
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(proxyPlaylistUrl),
      httpHeaders: const {},
    );

    await _controller!.initialize();

    debugPrint('[SecureHLS] ✅ Video player initialized');
    debugPrint('[SecureHLS] Proxy URL: $proxyPlaylistUrl');

    return _controller!;
  }

  /// Stop playback and cleanup resources
  Future<void> stop() async {
    // Stop local proxy
    await _proxy?.stop();
    _proxy = null;

    // Release video player
    await _controller?.dispose();
    _controller = null;

    // Notify server to stop session
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

    // Clear state
    _sessionId = null;
    _pmk = null;
    _encryptor = null;
    _bulletproofsService = null;
    _filePath = null;

    debugPrint('[SecureHLS] ✅ Player stopped and cleaned up');
  }

  /// HTTP POST request
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

  /// Bytes to hex string
  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // Getters
  VideoPlayerController? get controller => _controller;
  String? get sessionId => _sessionId;
  Uint8List? get pmk => _pmk;
  String? get filePath => _filePath;
  bool get isInitialized => _sessionId != null && _pmk != null;
}

/// HLS Encryptor
///
/// Decrypts video segments using AES-256-GCM
class HlsEncryptor {
  final Uint8List pmk;
  late Uint8List _encryptionKey;

  HlsEncryptor({required this.pmk}) {
    _encryptionKey = _deriveKey(pmk, 'hls-master-key');
  }

  /// Decrypt video segment
  Uint8List decryptSegment(Uint8List encryptedData) {
    if (encryptedData.length < 28) {
      throw ArgumentError('Encrypted data too short for AES-256-GCM');
    }

    final nonce = encryptedData.sublist(0, 12);
    final ciphertextWithTag = encryptedData.sublist(12);

    return _aesGcmDecrypt(_encryptionKey, nonce, ciphertextWithTag);
  }

  /// Derive key using HKDF-Blake3
  ///
  /// Uses Blake3 hash with key prefix for HKDF-like key derivation
  /// This matches the server-side HKDF-Blake3 implementation
  Uint8List _deriveKey(Uint8List key, String info) {
    final infoBytes = Uint8List.fromList(utf8.encode(info));
    final salt = Uint8List(32);

    // Extract: PRK = Blake3(salt || key)
    final prk = _blake3WithKey(salt, key);

    // Expand: output = Blake3(PRK || T(i-1) || info || counter)
    final output = <int>[];
    var t = Uint8List(0);
    var counter = 1;

    while (output.length < 32) {
      final hmacInput = Uint8List.fromList([...t, ...infoBytes, counter]);
      t = _blake3WithKey(prk, hmacInput);
      output.addAll(t);
      counter++;
    }

    return Uint8List.fromList(output.sublist(0, 32));
  }

  /// Blake3 hash with key prefix (simulates keyed hash)
  Uint8List _blake3WithKey(Uint8List key, Uint8List message) {
    // Ensure key is 32 bytes
    Uint8List normalizedKey;
    if (key.length == 32) {
      normalizedKey = key;
    } else if (key.length < 32) {
      normalizedKey = Uint8List(32);
      normalizedKey.setRange(0, key.length, key);
    } else {
      final hash = blake3.blake3(key, 32);
      normalizedKey = Uint8List.fromList(hash);
    }

    // Concatenate key and message, then hash
    final input = Uint8List.fromList([...normalizedKey, ...message]);
    final hash = blake3.blake3(input, 32);
    return Uint8List.fromList(hash);
  }

  /// AES-256-GCM decryption
  Uint8List _aesGcmDecrypt(
    Uint8List key,
    Uint8List nonce,
    Uint8List ciphertextWithTag,
  ) {
    final gcm = pc.GCMBlockCipher(pc.AESEngine());

    final params = pc.AEADParameters(
      pc.KeyParameter(key),
      128, // Tag length (bits)
      nonce,
      Uint8List(0), // AAD
    );

    gcm.init(false, params);

    try {
      return gcm.process(ciphertextWithTag);
    } catch (e) {
      throw Exception('AES-256-GCM decryption failed: $e');
    }
  }
}
