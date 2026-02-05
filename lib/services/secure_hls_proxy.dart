import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:thirds/blake3.dart' as blake3;

class AesGcmCrypto {
  static Uint8List decrypt({
    required Uint8List ciphertextWithTag,
    required Uint8List key,
    required Uint8List nonce,
  }) {
    if (key.length != 32) throw ArgumentError('Invalid key length');
    if (nonce.length != 12) throw ArgumentError('Invalid nonce length');
    if (ciphertextWithTag.length < 16) throw ArgumentError('Data too short');

    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
        false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    return cipher.process(ciphertextWithTag);
  }
}

class HkdfBlake3 {
  final Uint8List _prk;
  HkdfBlake3._(this._prk);

  factory HkdfBlake3.withSessionSalt(String sessionId, Uint8List ikm) {
    final saltInput = 'hls-session-salt:$sessionId';
    final salt = Uint8List.fromList(blake3.blake3(utf8.encode(saltInput), 32));
    final prkInput = Uint8List(32 + ikm.length);
    prkInput.setRange(0, 32, salt);
    prkInput.setRange(32, 32 + ikm.length, ikm);
    return HkdfBlake3._(Uint8List.fromList(blake3.blake3(prkInput, 32)));
  }

  Uint8List expand(Uint8List info, int length) {
    if (length == 0) return Uint8List(0);
    final output = Uint8List(length);
    var t = Uint8List(0);
    var counter = 1;
    var offset = 0;
    while (offset < length) {
      final input = Uint8List(32 + t.length + info.length + 1);
      var pos = 0;
      input.setRange(pos, pos + 32, _prk);
      pos += 32;
      input.setRange(pos, pos + t.length, t);
      pos += t.length;
      input.setRange(pos, pos + info.length, info);
      pos += info.length;
      input[pos] = counter;
      t = Uint8List.fromList(blake3.blake3(input, 32));
      final copyLen = (length - offset).clamp(0, 32);
      output.setRange(offset, offset + copyLen, t);
      offset += copyLen;
      counter++;
    }
    return output;
  }
}

class HlsEncryptor {
  final Uint8List _encryptionKey;
  final String sessionId;
  final Uint8List pmk;

  HlsEncryptor._({
    required this.sessionId,
    required this.pmk,
    required Uint8List encryptionKey,
  }) : _encryptionKey = encryptionKey;

  factory HlsEncryptor({required String sessionId, required Uint8List pmk}) {
    if (pmk.length != 32) throw ArgumentError('Invalid PMK length');
    final hkdf = HkdfBlake3.withSessionSalt(sessionId, pmk);
    final encryptionKey =
        hkdf.expand(Uint8List.fromList(utf8.encode('hls-master-key')), 32);
    return HlsEncryptor._(
        sessionId: sessionId, pmk: pmk, encryptionKey: encryptionKey);
  }

  Uint8List get encryptionKey => Uint8List.fromList(_encryptionKey);

  Uint8List decryptSegment(Uint8List encryptedData) {
    if (encryptedData.length < 29) throw ArgumentError('Data too short');
    final nonce = encryptedData.sublist(0, 12);
    final ciphertextWithTag = encryptedData.sublist(12);
    return AesGcmCrypto.decrypt(
        ciphertextWithTag: ciphertextWithTag,
        key: _encryptionKey,
        nonce: nonce);
  }
}

class ProxyStreamStats {
  int _networkBytesReceived = 0;
  int _decryptedBytesTotal = 0;
  int _segmentsLoadedFromNetwork = 0;
  int _segmentsServedFromCache = 0;
  int _segmentsDecrypted = 0;
  int _failedRequests = 0;
  int _totalSegments = 0;
  DateTime? _startTime;

  void reset() {
    _networkBytesReceived = 0;
    _decryptedBytesTotal = 0;
    _segmentsLoadedFromNetwork = 0;
    _segmentsServedFromCache = 0;
    _segmentsDecrypted = 0;
    _failedRequests = 0;
    _startTime = DateTime.now();
  }

  void recordNetworkReceive(int bytes) => _networkBytesReceived += bytes;
  void recordDecryption(int bytes) {
    _decryptedBytesTotal += bytes;
    _segmentsDecrypted++;
  }

  void recordNetworkLoad() => _segmentsLoadedFromNetwork++;
  void recordCacheHit() => _segmentsServedFromCache++;
  void recordFailure() => _failedRequests++;
  void setTotalSegments(int total) => _totalSegments = total;

  int get networkBytesReceived => _networkBytesReceived;
  int get decryptedBytesTotal => _decryptedBytesTotal;
  int get segmentsLoadedFromNetwork => _segmentsLoadedFromNetwork;
  int get segmentsServedFromCache => _segmentsServedFromCache;
  int get segmentsDecrypted => _segmentsDecrypted;
  int get failedRequests => _failedRequests;
  int get totalSegments => _totalSegments;

  double get cacheHitRate {
    final total = _segmentsLoadedFromNetwork + _segmentsServedFromCache;
    return total == 0 ? 0 : _segmentsServedFromCache / total;
  }

  Duration get sessionDuration => _startTime == null
      ? Duration.zero
      : DateTime.now().difference(_startTime!);
}

class _SegmentCache {
  final Map<int, Uint8List> _cache = {};
  static const int _maxSize = 30;
  int _oldestIndex = 0;

  Uint8List? get(int index) => _cache[index];

  void put(int index, Uint8List data) {
    _cache[index] = data;
    while (_cache.length > _maxSize) {
      _cache.remove(_oldestIndex);
      _oldestIndex++;
    }
  }

  bool contains(int index) => _cache.containsKey(index);
  void updateOldest(int currentIndex) {
    _oldestIndex = (currentIndex - 2).clamp(0, currentIndex);
  }

  void clear() {
    _cache.clear();
    _oldestIndex = 0;
  }
}

class SecureHlsProxyServer {
  HttpServer? _server;
  int? _port;
  final String baseUrl;
  final String sessionId;
  final Uint8List pmk;
  final String jwtToken;
  final void Function(int bytes, bool decrypted)? onSegmentLoaded;

  final Random _random = Random.secure();
  final _SegmentCache _cache = _SegmentCache();
  final Map<int, Completer<Uint8List>> _pendingRequests = {};
  final Set<int> _prefetchQueue = {};

  late final HlsEncryptor _encryptor;
  bool _initialized = false;
  bool _stopped = false;
  String? _cachedPlaylist;
  int? _totalSegments;
  int _lastRequestedSegment = -1;

  final ProxyStreamStats stats = ProxyStreamStats();
  HttpClient? _httpClient;

  static const int _prefetchAhead = 5;
  bool _isPrefetching = false;

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
    _stopped = false;
    stats.reset();
    _cache.clear();
    _httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 60)
      ..badCertificateCallback = (_, __, ___) => true;
  }

  Future<String> start() async {
    _initialize();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen(_handleRequest, onError: (_) {});
    return 'http://127.0.0.1:$_port/playlist.m3u8';
  }

  Future<void> stop() async {
    _stopped = true;
    for (final c in _pendingRequests.values) {
      if (!c.isCompleted) {
        c.completeError(Exception('Stopped'));
      }
    }
    _pendingRequests.clear();
    _prefetchQueue.clear();
    _cache.clear();
    await _server?.close(force: true);
    _httpClient?.close(force: true);
    _server = null;
    _httpClient = null;
    _initialized = false;
    _cachedPlaylist = null;
  }

  String _bytesToHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Map<String, String> _generateSecureParams(String segmentName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nonce =
        base64Encode(List<int>.generate(16, (_) => _random.nextInt(256)));
    final message = '$sessionId:$timestamp:$nonce:$segmentName';
    final hash = blake3.blake3(
        Uint8List.fromList([...pmk, ...utf8.encode(message)]), 32);
    return {
      'ts': timestamp.toString(),
      'nonce': nonce,
      'sig': _bytesToHex(Uint8List.fromList(hash))
    };
  }

  int _parseSegmentIndex(String name) {
    final match = RegExp(r'segment_(\d+)\.ts').firstMatch(name);
    return match != null ? int.tryParse(match.group(1) ?? '') ?? -1 : -1;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (_stopped) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    request.response.headers.add('Access-Control-Allow-Origin', '*');
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    try {
      final path = request.uri.path;
      if (path.contains('playlist.m3u8')) {
        await _handlePlaylist(request);
      } else if (path.endsWith('.ts')) {
        await _handleSegment(request, path);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handlePlaylist(HttpRequest request) async {
    try {
      if (_cachedPlaylist != null) {
        _servePlaylist(request, _cachedPlaylist!);
        _startPrefetch(0);
        return;
      }

      final url = '$baseUrl/api/v1/secure-hls/$sessionId/playlist.m3u8';
      final client = _httpClient ?? HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      if (jwtToken.isNotEmpty) {
        req.headers.add('Authorization', 'Bearer $jwtToken');
      }
      final response = await req.close().timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final content = await response.transform(utf8.decoder).join();
        _totalSegments = RegExp(r'segment_\d+\.ts').allMatches(content).length;
        stats.setTotalSegments(_totalSegments ?? 0);
        _cachedPlaylist = content;
        _servePlaylist(request, content);
        _startPrefetch(0);
      } else {
        request.response.statusCode = response.statusCode;
        await request.response.close();
      }
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  void _servePlaylist(HttpRequest request, String content) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
    request.response.headers.add('Cache-Control', 'no-cache');
    request.response.write(content);
    request.response.close();
  }

  Future<void> _handleSegment(HttpRequest request, String path) async {
    final segmentName = path.startsWith('/') ? path.substring(1) : path;
    final index = _parseSegmentIndex(segmentName);
    if (index < 0) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    _lastRequestedSegment = index;
    _cache.updateOldest(index);

    try {
      final cached = _cache.get(index);
      if (cached != null) {
        stats.recordCacheHit();
        await _serveSegment(request, cached);
        _startPrefetch(index);
        return;
      }

      if (_pendingRequests.containsKey(index)) {
        try {
          final data = await _pendingRequests[index]!
              .future
              .timeout(const Duration(seconds: 120));
          await _serveSegment(request, data);
        } catch (_) {
          stats.recordFailure();
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
        }
        return;
      }

      final completer = Completer<Uint8List>();
      _pendingRequests[index] = completer;

      try {
        final data = await _fetchSegment(segmentName);
        _cache.put(index, data);
        completer.complete(data);
        await _serveSegment(request, data);
        _startPrefetch(index);
      } catch (_) {
        stats.recordFailure();
        if (!completer.isCompleted) {
          completer.completeError(Exception('Fetch failed'));
        }
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      } finally {
        _pendingRequests.remove(index);
      }
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<Uint8List> _fetchSegment(String segmentName) async {
    const maxRetries = 3;
    Exception? lastError;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (_stopped) throw Exception('Stopped');

      try {
        final params = _generateSecureParams(segmentName);
        final url =
            Uri.parse('$baseUrl/api/v1/secure-hls/$sessionId/$segmentName')
                .replace(queryParameters: params);

        final client = _httpClient ?? HttpClient();
        final req = await client.postUrl(url);
        req.headers.contentType = ContentType.json;
        if (jwtToken.isNotEmpty) {
          req.headers.add('Authorization', 'Bearer $jwtToken');
        }
        req.write('{}');

        final response =
            await req.close().timeout(const Duration(seconds: 120));

        if (response.statusCode == 200) {
          final encrypted =
              await response.fold<List<int>>([], (p, c) => p..addAll(c));
          if (encrypted.length < 100) throw Exception('Invalid segment');

          stats.recordNetworkReceive(encrypted.length);
          stats.recordNetworkLoad();

          final decrypted =
              _encryptor.decryptSegment(Uint8List.fromList(encrypted));
          stats.recordDecryption(decrypted.length);
          onSegmentLoaded?.call(decrypted.length, true);

          return decrypted;
        } else {
          throw Exception('Server error: ${response.statusCode}');
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception('Unknown error');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
        }
      }
    }

    throw lastError ?? Exception('Fetch failed');
  }

  Future<void> _serveSegment(HttpRequest request, Uint8List data) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType('video', 'mp2t');
    request.response.headers.contentLength = data.length;
    request.response.headers.add('Cache-Control', 'no-cache');
    request.response.add(data);
    await request.response.close();
  }

  void _startPrefetch(int currentIndex) {
    if (_isPrefetching || _stopped) return;

    for (int i = 1; i <= _prefetchAhead; i++) {
      final nextIndex = currentIndex + i;
      if (_totalSegments != null && nextIndex >= _totalSegments!) break;
      if (!_cache.contains(nextIndex) &&
          !_pendingRequests.containsKey(nextIndex)) {
        _prefetchQueue.add(nextIndex);
      }
    }

    _processPrefetchQueue();
  }

  Future<void> _processPrefetchQueue() async {
    if (_isPrefetching || _prefetchQueue.isEmpty || _stopped) return;
    _isPrefetching = true;

    try {
      while (_prefetchQueue.isNotEmpty && !_stopped) {
        final index = _prefetchQueue.first;
        _prefetchQueue.remove(index);

        if (_cache.contains(index) || _pendingRequests.containsKey(index)) {
          continue;
        }
        if (index < _lastRequestedSegment - 1) continue;

        try {
          final data = await _fetchSegment('segment_$index.ts');
          _cache.put(index, data);
        } catch (_) {}

        await Future.delayed(const Duration(milliseconds: 50));
      }
    } finally {
      _isPrefetching = false;
    }
  }

  int? get totalSegments => _totalSegments;
  int get currentSegmentIndex => _lastRequestedSegment;

  int getBufferedSegmentsAhead() {
    if (_lastRequestedSegment < 0) return 0;
    int count = 0;
    for (int i = _lastRequestedSegment + 1;
        i <= _lastRequestedSegment + _prefetchAhead;
        i++) {
      if (_cache.contains(i)) count++;
    }
    return count;
  }
}
