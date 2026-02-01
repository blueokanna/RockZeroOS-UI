import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:thirds/blake3.dart' as blake3;

/// AES-256-GCM 加密/解密工具类
class AesGcmCrypto {
  /// AES-256-GCM 解密
  static Uint8List decrypt({
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
      throw ArgumentError('Ciphertext too short (must include 16-byte tag)');
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
}

/// HKDF-Blake3 密钥派生 - 与 Rust session.rs 完全一致
class HkdfBlake3 {
  final Uint8List _prk;

  HkdfBlake3._(this._prk);

  factory HkdfBlake3.withSessionSalt(String sessionId, Uint8List ikm) {
    // Step 1: salt = blake3("hls-session-salt:" + session_id)
    final saltInput = 'hls-session-salt:$sessionId';
    final saltInputBytes = Uint8List.fromList(utf8.encode(saltInput));
    final salt = Uint8List.fromList(blake3.blake3(saltInputBytes, 32));

    // Step 2: prk = blake3(salt + ikm)
    final prkInput = Uint8List(32 + ikm.length);
    prkInput.setRange(0, 32, salt);
    prkInput.setRange(32, 32 + ikm.length, ikm);
    final prk = Uint8List.fromList(blake3.blake3(prkInput, 32));

    return HkdfBlake3._(prk);
  }

  /// Expand PRK - 与 Rust session.rs 完全一致
  Uint8List expand(Uint8List info, int length) {
    final output = Uint8List(length);
    var t = Uint8List(0);
    var counter = 1;
    var offset = 0;

    while (offset < length) {
      // input = PRK + T(i-1) + info + counter
      final inputLen = 32 + t.length + info.length + 1;
      final input = Uint8List(inputLen);
      var pos = 0;

      input.setRange(pos, pos + 32, _prk);
      pos += 32;

      input.setRange(pos, pos + t.length, t);
      pos += t.length;

      input.setRange(pos, pos + info.length, info);
      pos += info.length;

      input[pos] = counter;

      final hash = blake3.blake3(input, 32);
      t = Uint8List.fromList(hash);

      final copyLen = (length - offset).clamp(0, 32);
      output.setRange(offset, offset + copyLen, t);
      offset += copyLen;
      counter++;
    }

    return output;
  }
}

/// HLS 加密器
class HlsEncryptor {
  final Uint8List _encryptionKey;
  final String sessionId;
  final Uint8List pmk;

  HlsEncryptor._({
    required this.sessionId,
    required this.pmk,
    required Uint8List encryptionKey,
  }) : _encryptionKey = encryptionKey;

  factory HlsEncryptor({
    required String sessionId,
    required Uint8List pmk,
  }) {
    if (pmk.length != 32) {
      throw ArgumentError('PMK must be 32 bytes, got ${pmk.length}');
    }

    final hkdf = HkdfBlake3.withSessionSalt(sessionId, pmk);
    final info = Uint8List.fromList(utf8.encode('hls-master-key'));
    final encryptionKey = hkdf.expand(info, 32);

    return HlsEncryptor._(
      sessionId: sessionId,
      pmk: pmk,
      encryptionKey: encryptionKey,
    );
  }

  Uint8List get encryptionKey => Uint8List.fromList(_encryptionKey);

  /// 解密视频段 - 格式: [12字节nonce][密文+16字节tag]
  Uint8List decryptSegment(Uint8List encryptedData) {
    if (encryptedData.length < 29) {
      throw ArgumentError('Data too short: ${encryptedData.length} bytes');
    }

    final nonce = encryptedData.sublist(0, 12);
    final ciphertextWithTag = encryptedData.sublist(12);

    try {
      return AesGcmCrypto.decrypt(
        ciphertextWithTag: ciphertextWithTag,
        key: _encryptionKey,
        nonce: nonce,
      );
    } catch (e) {
      debugPrint('[Encryptor] Decrypt failed: $e');
      rethrow;
    }
  }
}

/// 安全 HLS 代理服务器
class SecureHlsProxyServer {
  HttpServer? _server;
  int? _port;
  final String baseUrl;
  final String sessionId;
  final Uint8List pmk;
  final String jwtToken;
  final void Function(int bytes, bool decrypted)? onSegmentLoaded;
  final Random _random = Random.secure();

  final Map<String, Uint8List> _segmentCache = {};
  static const int _maxCacheSize = 30;
  final Map<String, Completer<Uint8List>> _pendingRequests = {};
  final Set<String> _prefetchQueue = {};
  bool _isPrefetching = false;

  late final HlsEncryptor _encryptor;
  bool _initialized = false;

  SecureHlsProxyServer({
    required this.baseUrl,
    required this.sessionId,
    required this.pmk,
    this.jwtToken = '',
    this.onSegmentLoaded,
  });

  void _initialize() {
    if (_initialized) return;
    _encryptor = HlsEncryptor(sessionId: sessionId, pmk: pmk);
    _initialized = true;
    debugPrint('[Proxy] Initialized for session: $sessionId');
  }

  Future<String> start() async {
    _initialize();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    debugPrint('[Proxy] Started on http://127.0.0.1:$_port');
    _server!.listen(_handleRequest);
    return 'http://127.0.0.1:$_port/playlist.m3u8';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
    _segmentCache.clear();
    _pendingRequests.clear();
    _prefetchQueue.clear();
    _isPrefetching = false;
    _initialized = false;
    debugPrint('[Proxy] Stopped');
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Map<String, String> _generateSecureParams(String segmentName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nonce =
        base64Encode(List<int>.generate(16, (_) => _random.nextInt(256)));
    final message = '$sessionId:$timestamp:$nonce:$segmentName';
    final input = Uint8List.fromList([...pmk, ...utf8.encode(message)]);
    final hash = blake3.blake3(input, 32);
    final signature = _bytesToHex(Uint8List.fromList(hash));
    return {'ts': timestamp.toString(), 'nonce': nonce, 'sig': signature};
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      debugPrint('[Proxy] ${request.method} $path');

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
      debugPrint('[Proxy] Error: $e\n$stack');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Error: $e');
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handlePlaylistRequest(HttpRequest request) async {
    HttpClient? client;
    try {
      final playlistUrl = '$baseUrl/api/v1/secure-hls/$sessionId/playlist.m3u8';
      client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
      final req = await client.getUrl(Uri.parse(playlistUrl));
      if (jwtToken.isNotEmpty) {
        req.headers.add('Authorization', 'Bearer $jwtToken');
      }
      final response = await req.close();

      if (response.statusCode == 200) {
        final content = await response.transform(utf8.decoder).join();
        final modifiedContent = content.replaceAllMapped(
          RegExp(r'(segment_\d+\.ts)'),
          (match) => 'http://127.0.0.1:$_port/${match.group(1)}',
        );
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
        request.response.headers.add('Cache-Control', 'no-cache');
        request.response.write(modifiedContent);
        debugPrint('[Proxy] Playlist served');
      } else {
        final errorBody = await response.transform(utf8.decoder).join();
        debugPrint(
            '[Proxy] Playlist failed: ${response.statusCode} - $errorBody');
        request.response.statusCode = response.statusCode;
        request.response.write('Failed: $errorBody');
      }
    } catch (e) {
      debugPrint('[Proxy] Playlist error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Error: $e');
    } finally {
      client?.close();
      await request.response.close();
    }
  }

  Future<void> _handleSegmentRequest(HttpRequest request, String path) async {
    final segmentName = path.substring(1);
    try {
      // Check cache
      if (_segmentCache.containsKey(segmentName)) {
        debugPrint('[Proxy] Cache hit: $segmentName');
        _serveSegment(request, _segmentCache[segmentName]!, segmentName);
        return;
      }

      // Check pending
      if (_pendingRequests.containsKey(segmentName)) {
        debugPrint('[Proxy] Waiting for pending: $segmentName');
        try {
          final data = await _pendingRequests[segmentName]!.future;
          _serveSegment(request, data, segmentName);
        } catch (e) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          request.response.write('Failed');
          await request.response.close();
        }
        return;
      }

      final completer = Completer<Uint8List>();
      _pendingRequests[segmentName] = completer;

      try {
        final decryptedData = await _fetchAndDecryptSegment(segmentName);
        _cacheSegment(segmentName, decryptedData);
        completer.complete(decryptedData);
        _serveSegment(request, decryptedData, segmentName);
      } catch (e) {
        completer.completeError(e);
        debugPrint('[Proxy] Segment failed: $e');
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write('Failed: $e');
        await request.response.close();
      } finally {
        _pendingRequests.remove(segmentName);
      }
    } catch (e, stack) {
      debugPrint('[Proxy] Segment error: $e\n$stack');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Error: $e');
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<Uint8List> _fetchAndDecryptSegment(String segmentName) async {
    Exception? lastError;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final params = _generateSecureParams(segmentName);
        final segmentUrl =
            Uri.parse('$baseUrl/api/v1/secure-hls/$sessionId/$segmentName')
                .replace(queryParameters: params);

        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 60);
        try {
          final req = await client.postUrl(segmentUrl);
          req.headers.contentType = ContentType.json;
          if (jwtToken.isNotEmpty) {
            req.headers.add('Authorization', 'Bearer $jwtToken');
          }
          req.write(jsonEncode({}));

          final response = await req.close();
          if (response.statusCode == 200) {
            final encryptedData = await response.fold<List<int>>(
              [],
              (prev, chunk) => prev..addAll(chunk),
            );
            debugPrint(
                '[Proxy] Received ${encryptedData.length} bytes for $segmentName');

            if (encryptedData.length < 100) {
              throw Exception('Invalid segment: ${encryptedData.length} bytes');
            }

            return _encryptor.decryptSegment(Uint8List.fromList(encryptedData));
          } else {
            final errorBody = await response.transform(utf8.decoder).join();
            throw Exception('Server ${response.statusCode}: $errorBody');
          }
        } finally {
          client.close();
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('[Proxy] Attempt $attempt failed: $e');
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
        }
      }
    }
    throw lastError ?? Exception('Failed after 3 attempts');
  }

  void _serveSegment(HttpRequest request, Uint8List data, String segmentName) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType('video', 'mp2t');
    request.response.headers.contentLength = data.length;
    request.response.headers.add('Cache-Control', 'no-cache');
    request.response.add(data);
    request.response.close();
    onSegmentLoaded?.call(data.length, true);
    debugPrint('[Proxy] ✅ Served $segmentName (${data.length} bytes)');
    _triggerPrefetch(segmentName);
  }

  void _triggerPrefetch(String currentSegment) {
    final match = RegExp(r'segment_(\d+)\.ts').firstMatch(currentSegment);
    if (match == null) return;
    final currentIndex = int.tryParse(match.group(1) ?? '');
    if (currentIndex == null) return;

    for (int i = 1; i <= 3; i++) {
      final nextSegment = 'segment_${currentIndex + i}.ts';
      if (!_segmentCache.containsKey(nextSegment) &&
          !_pendingRequests.containsKey(nextSegment) &&
          !_prefetchQueue.contains(nextSegment)) {
        _prefetchQueue.add(nextSegment);
      }
    }
    _processPrefetchQueue();
  }

  Future<void> _processPrefetchQueue() async {
    if (_isPrefetching || _prefetchQueue.isEmpty) return;
    _isPrefetching = true;
    try {
      while (_prefetchQueue.isNotEmpty) {
        final segmentName = _prefetchQueue.first;
        _prefetchQueue.remove(segmentName);
        if (_segmentCache.containsKey(segmentName) ||
            _pendingRequests.containsKey(segmentName)) {
          continue;
        }
        try {
          final data = await _fetchAndDecryptSegment(segmentName);
          _cacheSegment(segmentName, data);
          debugPrint('[Proxy] Prefetched $segmentName');
        } catch (e) {
          debugPrint('[Proxy] Prefetch failed: $segmentName - $e');
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      _isPrefetching = false;
    }
  }

  void _cacheSegment(String segmentName, Uint8List data) {
    if (data.length < 100) return;
    if (_segmentCache.length >= _maxCacheSize) {
      _segmentCache.remove(_segmentCache.keys.first);
    }
    _segmentCache[segmentName] = data;
  }
}
