import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:thirds/blake3.dart' as blake3;

import 'bulletproofs_ffi.dart';

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

  final Map<String, Uint8List> _segmentCache = {};
  static const int _maxCacheSize = 20;

  SecureHlsProxyServer({
    required this.baseUrl,
    required this.sessionId,
    required this.pmk,
    this.jwtToken = '',
    this.bulletproofsService,
    this.onSegmentLoaded,
  });

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

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
    _segmentCounter = 0;
    _segmentCache.clear();
    debugPrint('[SecureHLS Proxy] Stopped');
  }

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

  String _generateNonce() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Encode(bytes);
  }

  String _computeRequestSignature(
    int timestamp,
    String nonce,
    String segmentName,
  ) {
    final message = '$sessionId:$timestamp:$nonce:$segmentName';
    final input = Uint8List.fromList([...pmk, ...utf8.encode(message)]);
    final hash = blake3.blake3(input, 32);
    return _bytesToHex(Uint8List.fromList(hash));
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

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

  String _modifyPlaylist(String content) {
    return content.replaceAllMapped(
      RegExp(r'(segment_\d+\.ts)'),
      (match) => 'http://127.0.0.1:$_port/${match.group(1)}',
    );
  }

  Future<void> _handleSegmentRequest(HttpRequest request, String path) async {
    try {
      final segmentName = path.substring(1);
      final segmentIndex = _segmentCounter++;

      debugPrint(
          '[SecureHLS Proxy] Fetching segment: $segmentName (index: $segmentIndex)');

      if (_segmentCache.containsKey(segmentName)) {
        debugPrint('[SecureHLS Proxy] Cache hit for $segmentName');
        final cachedData = _segmentCache[segmentName]!;
        _serveSegment(request, cachedData, segmentName);
        return;
      }

      final secureParams = _generateSecureParams(segmentName);

      VideoStreamProof? zkpProof;
      if (bulletproofsService != null) {
        try {
          zkpProof = await bulletproofsService!
              .createVideoStreamProof(
                sessionId: sessionId,
                segmentIndex: segmentIndex,
                content: Uint8List.fromList(utf8.encode(segmentName)),
              )
              .timeout(const Duration(seconds: 2));
          if (zkpProof != null) {
            debugPrint(
                '[SecureHLS Proxy] ✅ ZKP proof created for segment $segmentIndex');
          }
        } catch (e) {
          debugPrint('[SecureHLS Proxy] ⚠️ ZKP proof creation failed: $e');
        }
      }

      Uint8List? decryptedData;
      int retryCount = 0;
      const maxRetries = 2;

      while (decryptedData == null && retryCount <= maxRetries) {
        try {
          decryptedData = await _fetchAndDecryptSegment(
            segmentName,
            secureParams,
            zkpProof,
          ).timeout(const Duration(seconds: 30));
        } catch (e) {
          retryCount++;
          debugPrint(
              '[SecureHLS Proxy] Segment fetch failed (attempt $retryCount): $e');
          if (retryCount <= maxRetries) {
            await Future.delayed(Duration(milliseconds: 200 * retryCount));
          }
        }
      }

      if (decryptedData != null) {
        _cacheSegment(segmentName, decryptedData);
        _serveSegment(request, decryptedData, segmentName);
      } else {
        debugPrint(
            '[SecureHLS Proxy] Failed to fetch segment after $maxRetries retries');
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write('Failed to fetch segment');
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

  Future<Uint8List> _fetchAndDecryptSegment(
    String segmentName,
    Map<String, String> secureParams,
    VideoStreamProof? zkpProof,
  ) async {
    final segmentUrl =
        Uri.parse('$baseUrl/api/v1/secure-hls/$sessionId/$segmentName')
            .replace(queryParameters: secureParams);

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    final backendRequest = await client.postUrl(segmentUrl);
    backendRequest.headers.contentType = ContentType.json;
    if (jwtToken.isNotEmpty) {
      backendRequest.headers.add('Authorization', 'Bearer $jwtToken');
    }

    final requestBody = <String, dynamic>{};
    if (zkpProof != null) {
      requestBody['zkp_proof'] = zkpProof.toJson();
    }
    backendRequest.write(jsonEncode(requestBody));

    final backendResponse = await backendRequest.close();

    if (backendResponse.statusCode == 200) {
      final encryptedData = await backendResponse.fold<List<int>>(
        [],
        (previous, element) => previous..addAll(element),
      );

      debugPrint(
          '[SecureHLS Proxy] Received ${encryptedData.length} bytes encrypted data for $segmentName');

      // Validate minimum size: 12 (nonce) + 16 (tag) + at least some data
      if (encryptedData.length < 1024) {
        throw Exception(
            'Received invalid segment data: only ${encryptedData.length} bytes (expected at least 1KB)');
      }

      return _decryptSegment(Uint8List.fromList(encryptedData));
    } else {
      final errorBody = await backendResponse.transform(utf8.decoder).join();
      throw Exception(
          'Backend error: ${backendResponse.statusCode} - $errorBody');
    }
  }

  void _serveSegment(HttpRequest request, Uint8List data, String segmentName) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType('video', 'mp2t');
    request.response.headers.contentLength = data.length;
    request.response.headers.add('Cache-Control', 'no-cache');
    request.response.add(data);
    request.response.close();

    onSegmentLoaded?.call(data.length, true);

    debugPrint(
        '[SecureHLS Proxy] ✅ Segment served: $segmentName (${data.length} bytes)');
  }

  void _cacheSegment(String segmentName, Uint8List data) {
    // Only cache valid segments (at least 1KB)
    if (data.length < 1024) {
      debugPrint(
          '[SecureHLS Proxy] ⚠️ Not caching invalid segment $segmentName (${data.length} bytes)');
      return;
    }

    if (_segmentCache.length >= _maxCacheSize) {
      final oldestKey = _segmentCache.keys.first;
      _segmentCache.remove(oldestKey);
      debugPrint('[SecureHLS Proxy] Evicted cached segment: $oldestKey');
    }
    _segmentCache[segmentName] = data;
    debugPrint(
        '[SecureHLS Proxy] Cached segment $segmentName (${data.length} bytes)');
  }

  Uint8List _decryptSegment(Uint8List encryptedData) {
    // Minimum size: 12 (nonce) + 16 (GCM tag) + at least 1 byte of data
    if (encryptedData.length < 29) {
      throw Exception(
          'Invalid encrypted data: too short (${encryptedData.length} bytes, need at least 29)');
    }

    try {
      final nonce = encryptedData.sublist(0, 12);
      final ciphertextWithTag = encryptedData.sublist(12);

      final decryptionKey = _deriveKey(pmk, 'hls-master-key');

      debugPrint(
          '[SecureHLS Proxy] Decrypting: nonce=${nonce.length}B, ciphertext=${ciphertextWithTag.length}B, key=${decryptionKey.length}B');
      debugPrint(
          '[SecureHLS Proxy] PMK first 8 bytes: ${pmk.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
      debugPrint(
          '[SecureHLS Proxy] Derived key first 8 bytes: ${decryptionKey.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');

      final decrypted = _aesGcmDecrypt(
        ciphertextWithTag: ciphertextWithTag,
        key: decryptionKey,
        nonce: nonce,
      );

      debugPrint(
          '[SecureHLS Proxy] ✅ Decryption successful: ${decrypted.length} bytes');

      return decrypted;
    } catch (e, stack) {
      debugPrint('[SecureHLS Proxy] ❌ Decryption error: $e');
      debugPrint('[SecureHLS Proxy] Stack: $stack');
      rethrow;
    }
  }

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
      128,
      nonce,
      Uint8List(0),
    );

    cipher.init(false, params);

    try {
      return cipher.process(ciphertextWithTag);
    } catch (e) {
      throw Exception(
          'GCM decryption failed: Authentication tag verification failed');
    }
  }

  /// HKDF-Blake3 key derivation - matches server-side implementation exactly
  /// Server uses: PRK = hash(salt + ikm), then expand with hash(prk + t + info + counter)
  Uint8List _deriveKey(Uint8List ikm, String info) {
    final infoBytes = Uint8List.fromList(utf8.encode(info));
    final salt = Uint8List(32); // Zero salt

    // Extract phase: PRK = hash(salt + ikm)
    final prkInput = Uint8List.fromList([...salt, ...ikm]);
    final prk = Uint8List.fromList(blake3.blake3(prkInput, 32));

    // Expand phase: hash(prk + t + info + counter)
    final output = <int>[];
    var t = Uint8List(0);
    var counter = 1;

    while (output.length < 32) {
      // Server does: prk + t + info + counter
      final expandInput = Uint8List.fromList([
        ...prk,
        ...t,
        ...infoBytes,
        counter,
      ]);
      final hash = blake3.blake3(expandInput, 32);
      t = Uint8List.fromList(hash);
      output.addAll(t);
      counter++;
    }

    return Uint8List.fromList(output.sublist(0, 32));
  }
}
