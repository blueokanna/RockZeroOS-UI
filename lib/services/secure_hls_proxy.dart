import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import 'hkdf_blake3.dart';

class SecureHlsProxyServer {
  HttpServer? _server;
  int? _port;

  final String baseUrl;
  String _sessionId;
  Uint8List _pmk;
  final String? password;
  final String? jwtToken;
  final Future<(String, Uint8List)> Function()? onSessionRebuild;
  final SecureHlsAdaptiveConfig adaptiveConfig;

  final Set<String> _prefetchInFlight = <String>{};
  int? _lastPrefetchCenter;
  DateTime? _lastPrefetchAt;

  late final HttpClient _backendClient;
  Future<(String, Uint8List)>? _sessionRebuildFuture;

  static const Duration _segmentRequestTimeout = Duration(seconds: 75);
  static const Duration _minPrefetchCooldown = Duration(milliseconds: 450);
  static const Duration _maxPrefetchCooldown = Duration(milliseconds: 1400);
  static const int _minPrefetchRadius = 1;
  static const int _maxPrefetchRadius = 3;

  int _dynamicPrefetchRadius = 2;
  Duration _dynamicPrefetchCooldown = const Duration(milliseconds: 800);
  int _dynamicMaxAttempts = 6;
  int _dynamicBaseBackoffMs = 280;
  int _dynamicMaxBackoffMs = 2600;
  int _dynamicMaxConnections = 6;
  final Random _jitter = Random();

  int _networkSampleCount = 0;
  double _emaFetchMs = 900;
  double _emaFailureRate = 0;

  int _segmentRetries = 0;

  SecureHlsRuntimeSnapshot get runtimeSnapshot => SecureHlsRuntimeSnapshot(
        segmentRetries: _segmentRetries,
      );

  SecureHlsProxyServer({
    required this.baseUrl,
    required String sessionId,
    required Uint8List pmk,
    this.password,
    this.jwtToken,
    this.onSessionRebuild,
    SecureHlsAdaptiveConfig? adaptiveConfig,
  })  : _sessionId = sessionId,
        _pmk = pmk,
        adaptiveConfig = adaptiveConfig ?? const SecureHlsAdaptiveConfig() {
    _applyInitialAdaptiveTuning();
    _backendClient = HttpClient()
      ..idleTimeout = const Duration(seconds: 30)
      ..maxConnectionsPerHost = _dynamicMaxConnections;
  }

  void _applyInitialAdaptiveTuning() {
    _dynamicMaxConnections = adaptiveConfig.recommendedConnections;
    _dynamicPrefetchRadius = adaptiveConfig.recommendedPrefetchRadius;
    _dynamicPrefetchCooldown = adaptiveConfig.recommendedPrefetchCooldown;
    _dynamicMaxAttempts = adaptiveConfig.recommendedMaxAttempts;
    _dynamicBaseBackoffMs = adaptiveConfig.recommendedBaseBackoffMs;
    _dynamicMaxBackoffMs = adaptiveConfig.recommendedMaxBackoffMs;
  }

  void _updateAdaptiveNetworkTuning({
    required int statusCode,
    required int elapsedMs,
  }) {
    _networkSampleCount += 1;
    const alpha = 0.20;
    _emaFetchMs = (_emaFetchMs * (1 - alpha)) + (elapsedMs * alpha);

    final failed = statusCode >= 400;
    final sampleFailure = failed ? 1.0 : 0.0;
    _emaFailureRate = (_emaFailureRate * (1 - alpha)) + (sampleFailure * alpha);

    if (_networkSampleCount < 8) {
      return;
    }

    final poorNetwork = _emaFetchMs > 1500 || _emaFailureRate > 0.22;
    final goodNetwork = _emaFetchMs < 520 && _emaFailureRate < 0.08;

    if (poorNetwork) {
      _dynamicPrefetchRadius = _minPrefetchRadius;
      _dynamicPrefetchCooldown = _maxPrefetchCooldown;
      _dynamicMaxAttempts = 8;
      _dynamicBaseBackoffMs = 420;
      _dynamicMaxBackoffMs = 3600;
      return;
    }

    if (goodNetwork) {
      _dynamicPrefetchRadius = _maxPrefetchRadius;
      _dynamicPrefetchCooldown = _minPrefetchCooldown;
      _dynamicMaxAttempts = adaptiveConfig.recommendedMaxAttempts;
      _dynamicBaseBackoffMs =
          max(220, adaptiveConfig.recommendedBaseBackoffMs - 40);
      _dynamicMaxBackoffMs = adaptiveConfig.recommendedMaxBackoffMs;
      return;
    }

    _applyInitialAdaptiveTuning();
  }

  Future<void> _adaptiveBackoffDelay(int attempt,
      {int? serverRetryAfterSec}) async {
    if (serverRetryAfterSec != null && serverRetryAfterSec > 0) {
      final clamped = serverRetryAfterSec.clamp(1, 6);
      await Future.delayed(Duration(seconds: clamped));
      return;
    }

    final factor = 1 << attempt.clamp(0, 5);
    final rawMs = _dynamicBaseBackoffMs * factor;
    final cappedMs = rawMs.clamp(_dynamicBaseBackoffMs, _dynamicMaxBackoffMs);
    final jitterMs = _jitter.nextInt(140);
    await Future.delayed(Duration(milliseconds: cappedMs + jitterMs));
  }

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen(_handleRequest);
    return 'http://127.0.0.1:$_port/playlist.m3u8';
  }

  Future<void> stop() async {
    _backendClient.close(force: true);
    await _server?.close(force: true);
    _server = null;
    _port = null;
  }

  void prefetchAroundSegment(int segmentIndex) {
    if (_server == null) return;

    final now = DateTime.now();
    if (_lastPrefetchCenter == segmentIndex &&
        _lastPrefetchAt != null &&
        now.difference(_lastPrefetchAt!) < _dynamicPrefetchCooldown) {
      return;
    }
    _lastPrefetchCenter = segmentIndex;
    _lastPrefetchAt = now;

    final radius =
        _dynamicPrefetchRadius.clamp(_minPrefetchRadius, _maxPrefetchRadius);
    final start = max(0, segmentIndex - radius);
    final end = segmentIndex + radius;

    for (int i = start; i <= end; i++) {
      final segmentName = 'segment_$i.ts';
      if (_prefetchInFlight.length >= adaptiveConfig.maxPrefetchInFlight) break;
      _prefetchSegment(segmentName).catchError((_) {});
    }
  }

  Future<void> _prefetchSegment(String segmentName) async {
    if (_prefetchInFlight.contains(segmentName)) return;
    _prefetchInFlight.add(segmentName);
    try {
      final result = await _fetchEncryptedSegment(segmentName);
      if (result.statusCode == HttpStatus.ok) {
        // no-op, warm backend caches only
      }
    } finally {
      _prefetchInFlight.remove(segmentName);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/playlist.m3u8') {
        await _handlePlaylistRequest(request);
      } else if (path.endsWith('.ts')) {
        await _handleSegmentRequest(request, path.substring(1));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not Found');
      }
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Internal Server Error: $e');
    } finally {
      await request.response.close();
    }
  }

  Future<void> _handlePlaylistRequest(HttpRequest request) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      final playlistUrl =
          '$baseUrl/api/v1/secure-hls/$_sessionId/playlist.m3u8';
      final response =
          await _backendClient.getUrl(Uri.parse(playlistUrl)).then((req) {
        if (jwtToken != null)
          req.headers.add('Authorization', 'Bearer $jwtToken');
        return req.close();
      });

      if (response.statusCode == HttpStatus.ok) {
        final content = await response.transform(utf8.decoder).join();
        final modified = _modifyPlaylist(content);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
        request.response.write(modified);
        return;
      }

      final body = await response.transform(utf8.decoder).join();
      final rebuilt = await _rebuildSessionIfNeeded(
        statusCode: response.statusCode,
        errorBody: body,
        trigger: 'playlist',
      );
      if (rebuilt && attempt == 0) continue;

      request.response.statusCode = response.statusCode;
      request.response.write('Failed to fetch playlist: $body');
      return;
    }
  }

  String _modifyPlaylist(String content) {
    return content.replaceAllMapped(
      RegExp(r'(segment_\d+\.ts)'),
      (m) => 'http://127.0.0.1:$_port/${m.group(1)}',
    );
  }

  Future<void> _handleSegmentRequest(
      HttpRequest request, String segmentName) async {
    final maxAttempts = _dynamicMaxAttempts;
    int lastStatus = HttpStatus.internalServerError;
    String lastErrorBody = 'Unknown error';

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) _segmentRetries += 1;

      final result = await _fetchEncryptedSegment(segmentName);
      if (result.statusCode == HttpStatus.ok && result.data != null) {
        final decrypted = _decryptSegment(result.data!);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType('video', 'mp2t');
        request.response.headers.contentLength = decrypted.length;
        request.response.add(decrypted);
        return;
      }

      lastStatus = result.statusCode;
      lastErrorBody = result.errorBody ?? 'Unknown backend error';

      final rebuilt = await _rebuildSessionIfNeeded(
        statusCode: lastStatus,
        errorBody: lastErrorBody,
        trigger: segmentName,
      );
      if (rebuilt) continue;

      if (lastStatus == HttpStatus.serviceUnavailable ||
          lastStatus == HttpStatus.notFound) {
        final retryAfter =
            _parseRetryAfterSeconds(result.retryAfterHeader, defaultValue: 1);
        await _adaptiveBackoffDelay(attempt, serverRetryAfterSec: retryAfter);
        continue;
      }

      if (attempt + 1 >= maxAttempts) break;
      await _adaptiveBackoffDelay(attempt);
    }

    request.response.statusCode = lastStatus;
    request.response.write('Backend error: $lastErrorBody');
  }

  Future<_SegmentFetchResult> _fetchEncryptedSegment(String segmentName) async {
    final startedAt = DateTime.now();
    final segmentUrl = '$baseUrl/api/v1/secure-hls/$_sessionId/$segmentName';

    final req = await _backendClient.getUrl(Uri.parse(segmentUrl));
    if (jwtToken != null) {
      req.headers.add('Authorization', 'Bearer $jwtToken');
    }

    final resp = await req.close().timeout(_segmentRequestTimeout);

    if (resp.statusCode == HttpStatus.ok) {
      final encryptedData = await resp.fold<List<int>>(
        [],
        (previous, element) => previous..addAll(element),
      ).timeout(_segmentRequestTimeout);
      _updateAdaptiveNetworkTuning(
        statusCode: HttpStatus.ok,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
      return _SegmentFetchResult(
          statusCode: HttpStatus.ok, data: Uint8List.fromList(encryptedData));
    }

    final errorBody = await resp
        .transform(utf8.decoder)
        .join()
        .timeout(_segmentRequestTimeout);
    _updateAdaptiveNetworkTuning(
      statusCode: resp.statusCode,
      elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
    return _SegmentFetchResult(
      statusCode: resp.statusCode,
      errorBody: errorBody,
      retryAfterHeader: resp.headers.value('retry-after'),
    );
  }

  Uint8List _decryptSegment(Uint8List encryptedData) {
    if (encryptedData.length < 28) {
      throw Exception('Invalid encrypted segment payload length');
    }

    final nonce = encryptedData.sublist(0, 12);
    final ciphertextWithTag = encryptedData.sublist(12);
    final key = _deriveKey(_pmk, 'hls-master-key');

    final cipher = ChaCha20Poly1305(ChaCha7539Engine(), Poly1305());
    final params = AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0));
    cipher.init(false, params);
    return cipher.process(ciphertextWithTag);
  }

  Uint8List _deriveKey(Uint8List pmk, String info) {
    final hkdf = HkdfBlake3.withSessionSalt(_sessionId, pmk);
    return hkdf.expand(Uint8List.fromList(utf8.encode(info)), 32);
  }

  int _parseRetryAfterSeconds(String? headerValue, {int defaultValue = 1}) {
    if (headerValue == null || headerValue.isEmpty) return defaultValue;
    final parsed = int.tryParse(headerValue.trim());
    if (parsed == null || parsed < 1) return defaultValue;
    return parsed.clamp(1, 8);
  }

  bool _shouldRebuildSession(int statusCode, String errorBody) {
    if (statusCode == HttpStatus.unauthorized ||
        statusCode == HttpStatus.notFound ||
        statusCode == HttpStatus.gone) {
      return true;
    }

    final lower = errorBody.toLowerCase();
    return lower.contains('session not found') ||
        lower.contains('session expired') ||
        lower.contains('invalid segment access ticket');
  }

  Future<bool> _rebuildSessionIfNeeded({
    required int statusCode,
    required String errorBody,
    required String trigger,
  }) async {
    if (onSessionRebuild == null) return false;
    if (!_shouldRebuildSession(statusCode, errorBody)) return false;

    if (_sessionRebuildFuture != null) {
      final rebuilt = await _sessionRebuildFuture!;
      _sessionId = rebuilt.$1;
      _pmk = rebuilt.$2;
      return true;
    }

    debugPrint(
        '[SecureHLS Proxy] Session appears stale during $trigger, rebuilding chain...');
    _sessionRebuildFuture = onSessionRebuild!.call();
    try {
      final rebuilt = await _sessionRebuildFuture!;
      _sessionId = rebuilt.$1;
      _pmk = rebuilt.$2;
      return true;
    } catch (_) {
      return false;
    } finally {
      _sessionRebuildFuture = null;
    }
  }
}

class _SegmentFetchResult {
  final int statusCode;
  final Uint8List? data;
  final String? errorBody;
  final String? retryAfterHeader;

  const _SegmentFetchResult({
    required this.statusCode,
    this.data,
    this.errorBody,
    this.retryAfterHeader,
  });
}

class SecureHlsRuntimeSnapshot {
  final int segmentRetries;

  const SecureHlsRuntimeSnapshot({
    required this.segmentRetries,
  });
}

class SecureHlsAdaptiveConfig {
  final int cpuCores;
  final int? bitrateBps;
  final bool lowMemoryMode;
  final int maxPrefetchInFlight;

  const SecureHlsAdaptiveConfig({
    this.cpuCores = 4,
    this.bitrateBps,
    this.lowMemoryMode = false,
    this.maxPrefetchInFlight = 4,
  });

  int get bitrateMbps => ((bitrateBps ?? 0) / 1000000).round();

  int get recommendedConnections {
    if (lowMemoryMode || cpuCores <= 4) return 3;
    if (cpuCores <= 6) return 4;
    return 6;
  }

  int get recommendedPrefetchRadius {
    if (lowMemoryMode || cpuCores <= 4) return 1;
    if (bitrateMbps >= 15) return 1;
    if (bitrateMbps >= 8) return 2;
    return 3;
  }

  Duration get recommendedPrefetchCooldown {
    if (lowMemoryMode || cpuCores <= 4)
      return const Duration(milliseconds: 1200);
    if (bitrateMbps >= 12) return const Duration(milliseconds: 900);
    return const Duration(milliseconds: 700);
  }

  int get recommendedMaxAttempts {
    if (bitrateMbps >= 18 || lowMemoryMode) return 7;
    return 6;
  }

  int get recommendedBaseBackoffMs {
    if (bitrateMbps >= 18) return 360;
    return 280;
  }

  int get recommendedMaxBackoffMs {
    if (bitrateMbps >= 18) return 3200;
    return 2400;
  }
}
