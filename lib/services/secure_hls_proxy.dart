import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:pointycastle/export.dart';

import 'bulletproofs_ffi.dart';

/// Secure HLS Proxy Server
///
/// Features:
/// - Local proxy server that intercepts HLS requests
/// - Decrypts video segments using SAE-derived PMK
/// - Generates Bulletproofs ZKP proof for each video segment
/// - Replay attack protection (timestamp + nonce + signature)
/// - Callback for segment load statistics
class SecureHlsProxyServer {
  HttpServer? _server;
  int? _port;
  final String baseUrl;
  final String sessionId;
  final Uint8List pmk;
  final String jwtToken;
  final BulletproofsService? bulletproofsService;
  final void Function(int bytes, bool decrypted)? onSegmentLoaded;
  final Random _random = Random.secure();
  int _segmentCounter = 0;

  // Cache for verified segments
  final Map<String, Uint8List> _segmentCache = {};
  static const int _maxCacheSize =
      20; // Increased cache size for smoother playback

  SecureHlsProxyServer({
    required this.baseUrl,
    required this.sessionId,
    required this.pmk,
    this.jwtToken = '',
    this.bulletproofsService,
    this.onSegmentLoaded,
  });

  /// Start the proxy server
  Future<String> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;

      debugPrint('[SecureHLS Proxy] Started on http://127.0.0.1:$_port');
      debugPrint('[SecureHLS Proxy] Session: $sessionId');
      debugPrint(
          '[SecureHLS Proxy] Security: SAE + AES-256-GCM + Bulletproofs ZKP');

      _server!.listen(_handleRequest);

      return 'http://127.0.0.1:$_port/playlist.m3u8';
    } catch (e) {
      debugPrint('[SecureHLS Proxy] Failed to start: $e');
      rethrow;
    }
  }

  /// Stop the proxy server
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
    _segmentCounter = 0;
    _segmentCache.clear();
    debugPrint('[SecureHLS Proxy] Stopped');
  }

  /// Generate secure request parameters (replay attack protection)
  Map<String, String> _generateSecureParams(String segmentName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nonce = _generateNonce();
    final signature = _computeRequestSignature(timestamp, nonce, segmentName);

    return {
      'ts': timestamp.toString(),
      'nonce': nonce,
      'sig': signature,
    };
  }

  /// Generate random nonce
  String _generateNonce() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Encode(bytes);
  }

  /// Compute request signature
  /// signature = HMAC-SHA256(session_id:timestamp:nonce:segment_name, pmk)
  String _computeRequestSignature(
    int timestamp,
    String nonce,
    String segmentName,
  ) {
    final message = '$sessionId:$timestamp:$nonce:$segmentName';
    final hmac = hashlib.HMAC(hashlib.sha256).by(pmk);
    final digest = hmac.convert(utf8.encode(message));
    return digest.hex();
  }

  /// Handle incoming requests
  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      debugPrint('[SecureHLS Proxy] ${request.method} $path');

      if (path == '/playlist.m3u8') {
        await _handlePlaylistRequest(request);
      } else if (path.endsWith('.ts')) {
        await _handleSegmentRequest(request, path);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not Found');
        await request.response.close();
      }
    } catch (e, stack) {
      debugPrint('[SecureHLS Proxy] Error: $e');
      debugPrint('[SecureHLS Proxy] Stack: $stack');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Internal Server Error');
      await request.response.close();
    }
  }

  /// Handle playlist requests
  Future<void> _handlePlaylistRequest(HttpRequest request) async {
    try {
      final playlistUrl = '$baseUrl/api/v1/secure-hls/$sessionId/playlist.m3u8';

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(playlistUrl));
      if (jwtToken.isNotEmpty) {
        req.headers.add('Authorization', 'Bearer $jwtToken');
      }
      final response = await req.close();

      if (response.statusCode == 200) {
        final content = await response.transform(utf8.decoder).join();
        final modifiedContent = _modifyPlaylist(content);

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
        request.response.headers
            .add('Cache-Control', 'no-cache, no-store, must-revalidate');
        request.response.write(modifiedContent);

        debugPrint('[SecureHLS Proxy] Playlist served successfully');
      } else {
        debugPrint(
            '[SecureHLS Proxy] Playlist fetch failed: ${response.statusCode}');
        request.response.statusCode = response.statusCode;
        request.response.write('Failed to fetch playlist');
      }
    } catch (e) {
      debugPrint('[SecureHLS Proxy] Playlist error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Error: $e');
    } finally {
      await request.response.close();
    }
  }

  /// Modify playlist to point segment URLs to local proxy
  String _modifyPlaylist(String content) {
    return content.replaceAllMapped(
      RegExp(r'(segment_\d+\.ts)'),
      (match) => 'http://127.0.0.1:$_port/${match.group(1)}',
    );
  }

  /// Handle video segment requests
  Future<void> _handleSegmentRequest(HttpRequest request, String path) async {
    try {
      final segmentName = path.substring(1);
      final segmentIndex = _segmentCounter++;

      debugPrint(
          '[SecureHLS Proxy] Fetching segment: $segmentName (index: $segmentIndex)');

      // Check cache
      if (_segmentCache.containsKey(segmentName)) {
        debugPrint('[SecureHLS Proxy] Cache hit for $segmentName');
        final cachedData = _segmentCache[segmentName]!;
        _serveSegment(request, cachedData, segmentName);
        return;
      }

      // Generate secure request parameters
      final secureParams = _generateSecureParams(segmentName);

      // Create Bulletproofs ZKP proof
      VideoStreamProof? zkpProof;
      if (bulletproofsService != null) {
        try {
          zkpProof = await bulletproofsService!.createVideoStreamProof(
            sessionId: sessionId,
            segmentIndex: segmentIndex,
            content: Uint8List.fromList(utf8.encode(segmentName)),
          );
          if (zkpProof != null) {
            debugPrint(
                '[SecureHLS Proxy] ✅ ZKP proof created for segment $segmentIndex');
          }
        } catch (e) {
          debugPrint('[SecureHLS Proxy] ⚠️ ZKP proof creation failed: $e');
        }
      }

      // Build request URL (using GET request + query parameters)
      final segmentUrl =
          Uri.parse('$baseUrl/api/v1/secure-hls/$sessionId/$segmentName')
              .replace(queryParameters: secureParams);

      final client = HttpClient();
      final backendRequest = await client.postUrl(segmentUrl);
      backendRequest.headers.contentType = ContentType.json;
      if (jwtToken.isNotEmpty) {
        backendRequest.headers.add('Authorization', 'Bearer $jwtToken');
      }

      // Send request body (containing ZKP proof)
      final requestBody = <String, dynamic>{};
      if (zkpProof != null) {
        requestBody['zkp_proof'] = zkpProof.toJson();
      }
      backendRequest.write(jsonEncode(requestBody));

      final backendResponse = await backendRequest.close();

      if (backendResponse.statusCode == 200) {
        // Read encrypted data
        final encryptedData = await backendResponse.fold<List<int>>(
          [],
          (previous, element) => previous..addAll(element),
        );

        debugPrint(
            '[SecureHLS Proxy] Received ${encryptedData.length} bytes encrypted data');

        // Decrypt video segment
        final decryptedData =
            _decryptSegment(Uint8List.fromList(encryptedData));

        // Cache decrypted data
        _cacheSegment(segmentName, decryptedData);

        // Return decrypted video segment
        _serveSegment(request, decryptedData, segmentName);
      } else {
        final errorBody = await backendResponse.transform(utf8.decoder).join();
        debugPrint(
            '[SecureHLS Proxy] Backend error: ${backendResponse.statusCode} - $errorBody');
        request.response.statusCode = backendResponse.statusCode;
        request.response.write('Backend error: $errorBody');
        await request.response.close();
      }
    } catch (e, stack) {
      debugPrint('[SecureHLS Proxy] Segment error: $e');
      debugPrint('[SecureHLS Proxy] Stack: $stack');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Error: $e');
      await request.response.close();
    }
  }

  /// Serve video segment
  void _serveSegment(HttpRequest request, Uint8List data, String segmentName) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType('video', 'mp2t');
    request.response.headers.contentLength = data.length;
    request.response.headers.add('Cache-Control', 'no-cache');
    request.response.add(data);
    request.response.close();

    // Notify callback
    onSegmentLoaded?.call(data.length, true);

    debugPrint(
        '[SecureHLS Proxy] ✅ Segment served: $segmentName (${data.length} bytes)');
  }

  /// Cache video segment
  void _cacheSegment(String segmentName, Uint8List data) {
    // Limit cache size
    if (_segmentCache.length >= _maxCacheSize) {
      final oldestKey = _segmentCache.keys.first;
      _segmentCache.remove(oldestKey);
    }
    _segmentCache[segmentName] = data;
  }

  /// Decrypt video segment
  ///
  /// Format: [12-byte Nonce][Ciphertext + 16-byte Tag]
  Uint8List _decryptSegment(Uint8List encryptedData) {
    if (encryptedData.length < 28) {
      throw Exception(
          'Invalid encrypted data: too short (${encryptedData.length} bytes)');
    }

    try {
      // Extract nonce and ciphertext
      final nonce = encryptedData.sublist(0, 12);
      final ciphertextWithTag = encryptedData.sublist(12);

      // Derive decryption key
      final decryptionKey = _deriveKey(pmk, 'hls-master-key');

      debugPrint(
          '[SecureHLS Proxy] Decrypting: nonce=${nonce.length}B, ciphertext=${ciphertextWithTag.length}B');

      // AES-256-GCM decryption
      return _aesGcmDecrypt(
        ciphertextWithTag: ciphertextWithTag,
        key: decryptionKey,
        nonce: nonce,
      );
    } catch (e, stack) {
      debugPrint('[SecureHLS Proxy] Decryption error: $e');
      debugPrint('[SecureHLS Proxy] Stack: $stack');
      rethrow;
    }
  }

  /// AES-256-GCM decryption
  Uint8List _aesGcmDecrypt({
    required Uint8List ciphertextWithTag,
    required Uint8List key,
    required Uint8List nonce,
  }) {
    if (key.length != 32) {
      throw ArgumentError('AES-256 requires 32-byte key, got ${key.length}');
    }
    if (nonce.length != 12) {
      throw ArgumentError('GCM requires 12-byte nonce, got ${nonce.length}');
    }
    if (ciphertextWithTag.length < 16) {
      throw ArgumentError('Ciphertext too short, must include 16-byte tag');
    }

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(key),
      128, // Tag length (bits)
      nonce,
      Uint8List(0), // AAD
    );

    cipher.init(false, params);

    try {
      return cipher.process(ciphertextWithTag);
    } catch (e) {
      throw Exception(
          'GCM decryption failed: Authentication tag verification failed');
    }
  }

  /// Derive key (HKDF-like)
  Uint8List _deriveKey(Uint8List key, String info) {
    final infoBytes = Uint8List.fromList(utf8.encode(info));
    final salt = Uint8List(32);

    // Extract
    final prk = _hmacSha3_256(salt, key);

    // Expand
    final output = <int>[];
    var t = Uint8List(0);
    var counter = 1;

    while (output.length < 32) {
      final hmacInput = Uint8List.fromList([...t, ...infoBytes, counter]);
      t = _hmacSha3_256(prk, hmacInput);
      output.addAll(t);
      counter++;
    }

    return Uint8List.fromList(output.sublist(0, 32));
  }

  /// HMAC-SHA3-256
  Uint8List _hmacSha3_256(Uint8List key, Uint8List message) {
    final hmac = hashlib.HMAC(hashlib.sha3_256).by(key);
    final digest = hmac.convert(message);
    return Uint8List.fromList(digest.bytes);
  }
}
