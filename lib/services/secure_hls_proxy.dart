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
  static const int _maxCacheSize = 10;

  // Pending requests to avoid duplicate fetches
  final Map<String, Completer<Uint8List>> _pendingRequests = {};

  // Derived encryption key (cached)
  Uint8List? _encryptionKey;

  SecureHlsProxyServer({
    required this.baseUrl,
    required this.sessionId,
    required this.pmk,
    this.jwtToken = '',
    this.bulletproofsService,
    this.onSegmentLoaded,
  }) {
    // Pre-derive the encryption key
    _encryptionKey = _deriveKey(pmk, 'hls-master-key');
    debugPrint('[SecureHLS Proxy] Encryption key derived');
    debugPrint(
        '[SecureHLS Proxy] PMK: ${pmk.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}...');
    debugPrint(
        '[SecureHLS Proxy] Key: ${_encryptionKey!.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}...');
  }

  Future<String> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;

      debugPrint('[SecureHLS Proxy] Started on http://127.0.0.1:$_port');
      debugPrint('[SecureHLS Proxy] Session: $sessionId');

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
    _pendingRequests.clear();
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
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Internal Server Error');
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handlePlaylistRequest(HttpRequest request) async {
    try {
      final playlistUrl = '$baseUrl/api/v1/secure-hls/$sessionId/playlist.m3u8';

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
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
      client.close();
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
    final segmentName = path.substring(1);

    try {
      debugPrint('[SecureHLS Proxy] Fetching segment: $segmentName');

      // Check cache first
      if (_segmentCache.containsKey(segmentName)) {
        debugPrint('[SecureHLS Proxy] Cache hit for $segmentName');
        final cachedData = _segmentCache[segmentName]!;
        _serveSegment(request, cachedData, segmentName);
        return;
      }

      // Check if there's already a pending request for this segment
      if (_pendingRequests.containsKey(segmentName)) {
        debugPrint(
            '[SecureHLS Proxy] Waiting for pending request: $segmentName');
        try {
          final data = await _pendingRequests[segmentName]!.future;
          _serveSegment(request, data, segmentName);
        } catch (e) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          request.response.write('Failed to fetch segment');
          await request.response.close();
        }
        return;
      }

      // Create a new pending request
      final completer = Completer<Uint8List>();
      _pendingRequests[segmentName] = completer;

      try {
        final decryptedData = await _fetchAndDecryptSegmentWithRetry(
          segmentName,
          maxRetries: 3,
        );

        _cacheSegment(segmentName, decryptedData);
        completer.complete(decryptedData);
        _serveSegment(request, decryptedData, segmentName);
      } catch (e) {
        completer.completeError(e);
        debugPrint('[SecureHLS Proxy] Failed to fetch segment: $e');
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write('Failed to fetch segment: $e');
        await request.response.close();
      } finally {
        _pendingRequests.remove(segmentName);
      }
    } catch (e, stack) {
      debugPrint('[SecureHLS Proxy] Segment error: $e');
      debugPrint('[SecureHLS Proxy] Stack: $stack');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Error: $e');
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<Uint8List> _fetchAndDecryptSegmentWithRetry(
    String segmentName, {
    int maxRetries = 3,
  }) async {
    Exception? lastError;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final secureParams = _generateSecureParams(segmentName);
        return await _fetchAndDecryptSegment(segmentName, secureParams)
            .timeout(const Duration(seconds: 60));
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint(
            '[SecureHLS Proxy] Attempt $attempt failed for $segmentName: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }

    throw lastError ??
        Exception('Failed to fetch segment after $maxRetries attempts');
  }

  Future<Uint8List> _fetchAndDecryptSegment(
    String segmentName,
    Map<String, String> secureParams,
  ) async {
    final segmentUrl =
        Uri.parse('$baseUrl/api/v1/secure-hls/$sessionId/$segmentName')
            .replace(queryParameters: secureParams);

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 60);

    try {
      final backendRequest = await client.postUrl(segmentUrl);
      backendRequest.headers.contentType = ContentType.json;
      if (jwtToken.isNotEmpty) {
        backendRequest.headers.add('Authorization', 'Bearer $jwtToken');
      }
      backendRequest.write(jsonEncode({}));

      final backendResponse = await backendRequest.close();

      if (backendResponse.statusCode == 200) {
        final encryptedData = await backendResponse.fold<List<int>>(
          [],
          (previous, element) => previous..addAll(element),
        );

        debugPrint(
            '[SecureHLS Proxy] Received ${encryptedData.length} bytes for $segmentName');

        // Minimum valid size: 12 (nonce) + 16 (tag) + some data
        if (encryptedData.length < 100) {
          throw Exception(
              'Invalid segment: only ${encryptedData.length} bytes');
        }

        return _decryptSegment(Uint8List.fromList(encryptedData));
      } else {
        final errorBody = await backendResponse.transform(utf8.decoder).join();
        throw Exception(
            'Server error ${backendResponse.statusCode}: $errorBody');
      }
    } finally {
      client.close();
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
    _segmentCounter++;

    debugPrint(
        '[SecureHLS Proxy] ✅ Served $segmentName (${data.length} bytes)');
  }

  void _cacheSegment(String segmentName, Uint8List data) {
    if (data.length < 100) {
      debugPrint('[SecureHLS Proxy] Not caching invalid segment $segmentName');
      return;
    }

    if (_segmentCache.length >= _maxCacheSize) {
      final oldestKey = _segmentCache.keys.first;
      _segmentCache.remove(oldestKey);
    }
    _segmentCache[segmentName] = data;
  }

  Uint8List _decryptSegment(Uint8List encryptedData) {
    if (encryptedData.length < 29) {
      throw Exception(
          'Encrypted data too short: ${encryptedData.length} bytes');
    }

    final nonce = encryptedData.sublist(0, 12);
    final ciphertextWithTag = encryptedData.sublist(12);

    debugPrint(
        '[SecureHLS Proxy] Decrypting: nonce=${nonce.length}B, data=${ciphertextWithTag.length}B');

    try {
      final decrypted = _aesGcmDecrypt(
        ciphertextWithTag: ciphertextWithTag,
        key: _encryptionKey!,
        nonce: nonce,
      );

      debugPrint('[SecureHLS Proxy] ✅ Decrypted ${decrypted.length} bytes');
      return decrypted;
    } catch (e) {
      debugPrint('[SecureHLS Proxy] ❌ Decryption failed: $e');
      rethrow;
    }
  }

  Uint8List _aesGcmDecrypt({
    required Uint8List ciphertextWithTag,
    required Uint8List key,
    required Uint8List nonce,
  }) {
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes, got ${key.length}');
    }
    if (nonce.length != 12) {
      throw ArgumentError('Nonce must be 12 bytes, got ${nonce.length}');
    }
    if (ciphertextWithTag.length < 16) {
      throw ArgumentError('Ciphertext too short');
    }

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(key),
      128,
      nonce,
      Uint8List(0),
    );

    cipher.init(false, params);
    return cipher.process(ciphertextWithTag);
  }

  /// HKDF-Blake3 key derivation - matches server implementation exactly
  Uint8List _deriveKey(Uint8List ikm, String info) {
    final infoBytes = Uint8List.fromList(utf8.encode(info));
    final salt = Uint8List(32); // Zero salt

    // Extract: PRK = hash(salt + ikm)
    final prkInput = Uint8List.fromList([...salt, ...ikm]);
    final prk = Uint8List.fromList(blake3.blake3(prkInput, 32));

    // Expand: hash(prk + t + info + counter)
    final output = <int>[];
    var t = Uint8List(0);
    var counter = 1;

    while (output.length < 32) {
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
