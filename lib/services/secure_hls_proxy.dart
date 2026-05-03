import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

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
  Future<(String, Uint8List)>? _sessionRebuildFuture;

  final Set<String> _prefetchInFlight = <String>{};
  int? _lastPrefetchCenter;
  DateTime? _lastPrefetchAt;

  late final HttpClient _backendClient;

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

  int _proofGenerateRequests = 0;
  int _proofGenerateFailures = 0;
  int _segmentRetries = 0;
  int _postProofSuccessHits = 0;
  bool _backendNoDiskMode = false;
  String? _segmentTicket;
  int? _segmentTicketExpiresAtMs;
  Future<String?>? _segmentTicketInFlight;
  final Queue<String> _proofQueue = Queue<String>();
  Future<void>? _proofBatchInFlight;
  static const int _proofBatchTarget = 6;
  static const Duration _segmentRequestTimeout = Duration(seconds: 75);

  SecureHlsRuntimeSnapshot get runtimeSnapshot => SecureHlsRuntimeSnapshot(
        proofGenerateRequests: _proofGenerateRequests,
        proofGenerateFailures: _proofGenerateFailures,
        segmentRetries: _segmentRetries,
        fallbackGetHits: 0,
        postProofSuccessHits: _postProofSuccessHits,
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

    _dynamicPrefetchRadius = adaptiveConfig.recommendedPrefetchRadius;
    _dynamicPrefetchCooldown = adaptiveConfig.recommendedPrefetchCooldown;
    _dynamicMaxAttempts = adaptiveConfig.recommendedMaxAttempts;
    _dynamicBaseBackoffMs = adaptiveConfig.recommendedBaseBackoffMs;
    _dynamicMaxBackoffMs = adaptiveConfig.recommendedMaxBackoffMs;
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
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;

      debugPrint('[SecureHLS Proxy] Started on http://127.0.0.1:$_port');
      debugPrint('[SecureHLS Proxy] Using Bulletproofs ZKP authentication');

      _server!.listen(_handleRequest);

      unawaited(_warmProofQueueIfNeeded(force: true)
          .catchError((Object error, StackTrace stackTrace) {
        debugPrint('[SecureHLS Proxy] Proof warmup failed: $error');
        debugPrint('[SecureHLS Proxy] Proof warmup stack: $stackTrace');
      }));
      unawaited(_ensureSegmentTicket(forceRefresh: true)
          .catchError((Object error, StackTrace stackTrace) {
        debugPrint('[SecureHLS Proxy] Segment ticket warmup failed: $error');
        debugPrint(
            '[SecureHLS Proxy] Segment ticket warmup stack: $stackTrace');
        return null;
      }));

      return 'http://127.0.0.1:$_port/playlist.m3u8';
    } catch (e) {
      debugPrint('[SecureHLS Proxy] Failed to start: $e');
      rethrow;
    }
  }

  Future<void> stop() async {
    _backendClient.close(force: true);
    await _server?.close(force: true);
    _server = null;
    _port = null;
    debugPrint('[SecureHLS Proxy] Stopped');
  }

  void prefetchAroundSegment(int segmentIndex) {
    if (_server == null) return;
    if (_backendNoDiskMode) return;

    final now = DateTime.now();
    if (_lastPrefetchCenter == segmentIndex &&
        _lastPrefetchAt != null &&
        now.difference(_lastPrefetchAt!) < _dynamicPrefetchCooldown) {
      return;
    }
    _lastPrefetchCenter = segmentIndex;
    _lastPrefetchAt = now;

    debugPrint(
        '[SecureHLS Proxy] Prefetch requested around segment $segmentIndex');

    final radius =
        _dynamicPrefetchRadius.clamp(_minPrefetchRadius, _maxPrefetchRadius);
    final start = max(0, segmentIndex - radius);
    final end = segmentIndex + radius;

    for (int i = start; i <= end; i++) {
      final segmentName = 'segment_$i.ts';

      if (_prefetchInFlight.length >= adaptiveConfig.maxPrefetchInFlight) {
        break;
      }

      _prefetchSegment(segmentName).catchError((e) {
        debugPrint('[SecureHLS Proxy] Prefetch failed for $segmentName: $e');
      });
    }
  }

  Future<void> _prefetchSegment(String segmentName) async {
    if (_prefetchInFlight.contains(segmentName)) {
      return;
    }

    _prefetchInFlight.add(segmentName);
    try {
      final ticket = await _ensureSegmentTicket();
      final zkpProof =
          ticket == null ? await _generateBulletproofZkpProofCached() : null;
      final segmentUrl = '$baseUrl/api/v1/secure-hls/$_sessionId/$segmentName';

      final request = await _backendClient.postUrl(Uri.parse(segmentUrl));
      request.headers.contentType = ContentType.json;
      if (jwtToken != null) {
        request.headers.add('Authorization', 'Bearer $jwtToken');
      }
      request.write(jsonEncode({
        if (ticket != null) 'zkp_ticket': ticket,
        if (zkpProof != null) 'zkp_proof': zkpProof,
      }));

      final response = await request.close();

      if (response.statusCode == 200) {
        await response.drain<void>();
        debugPrint('[SecureHLS Proxy] Prefetched: $segmentName');
      } else {
        await response.drain<void>();
      }
    } catch (e) {
      debugPrint('[SecureHLS Proxy] Prefetch error for $segmentName: $e');
    } finally {
      _prefetchInFlight.remove(segmentName);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      debugPrint('[SecureHLS Proxy] Request: ${request.method} $path');

      if (path == '/playlist.m3u8') {
        await _handlePlaylistRequest(request);
      } else if (path.endsWith('.ts')) {
        await _handleSegmentRequest(request, path);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not Found');
        await request.response.close();
      }
    } catch (e) {
      debugPrint('[SecureHLS Proxy] Error handling request: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Internal Server Error: $e');
      await request.response.close();
    }
  }

  Future<void> _handlePlaylistRequest(HttpRequest request) async {
    try {
      for (int attempt = 0; attempt < 2; attempt++) {
        final playlistUrl =
            '$baseUrl/api/v1/secure-hls/$_sessionId/playlist.m3u8';
        final response =
            await _backendClient.getUrl(Uri.parse(playlistUrl)).then((req) {
          if (jwtToken != null) {
            req.headers.add('Authorization', 'Bearer $jwtToken');
          }
          return req.close();
        });

        if (response.statusCode == 200) {
          final content = await response.transform(utf8.decoder).join();
          final modifiedContent = _modifyPlaylist(content);

          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
          request.response.write(modifiedContent);
          return;
        }

        final errorBody = await response.transform(utf8.decoder).join();
        final rebuilt = await _rebuildSessionIfNeeded(
          statusCode: response.statusCode,
          errorBody: errorBody,
          trigger: 'playlist',
        );

        if (rebuilt && attempt == 0) {
          continue;
        }

        request.response.statusCode = response.statusCode;
        request.response.write('Failed to fetch playlist: $errorBody');
        return;
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

      debugPrint('[SecureHLS Proxy] Fetching segment: $segmentName');

      final int maxAttempts = _dynamicMaxAttempts;
      int lastStatus = HttpStatus.internalServerError;
      String lastErrorBody = 'Unknown error';

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (attempt > 0) {
          _segmentRetries += 1;
        }
        _SegmentFetchResult result;
        try {
          result = await _fetchEncryptedSegment(
            segmentName,
            forceRefreshProof: false,
          );
        } catch (e) {
          debugPrint('[SecureHLS Proxy] Proof path failed: $e');
          result = _SegmentFetchResult(
            statusCode: HttpStatus.serviceUnavailable,
            errorBody: e.toString(),
          );
        }

        if (result.statusCode == HttpStatus.ok && result.data != null) {
          final decryptedData = await _decryptSegment(result.data!);

          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType('video', 'mp2t');
          request.response.headers.contentLength = decryptedData.length;
          request.response.add(decryptedData);

          debugPrint(
              '[SecureHLS Proxy] Segment served: $segmentName (${decryptedData.length} bytes)');
          return;
        }

        lastStatus = result.statusCode;
        lastErrorBody = result.errorBody ?? 'Unknown backend error';

        final lower = lastErrorBody.toLowerCase();
        final invalidProof = lastStatus == HttpStatus.unauthorized &&
            (lower.contains('invalid zkp proof') ||
                lower.contains('invalid segment access ticket'));

        if (invalidProof) {
          _invalidateProofCache();
          _SegmentFetchResult retryAfterProofRefresh;
          try {
            retryAfterProofRefresh = await _fetchEncryptedSegment(
              segmentName,
              forceRefreshProof: true,
            );
          } catch (e) {
            debugPrint('[SecureHLS Proxy] Refreshed proof path failed: $e');
            retryAfterProofRefresh = _SegmentFetchResult(
              statusCode: HttpStatus.serviceUnavailable,
              errorBody: e.toString(),
            );
          }
          if (retryAfterProofRefresh.statusCode == HttpStatus.ok &&
              retryAfterProofRefresh.data != null) {
            final decryptedData =
                await _decryptSegment(retryAfterProofRefresh.data!);
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType('video', 'mp2t');
            request.response.headers.contentLength = decryptedData.length;
            request.response.add(decryptedData);
            return;
          }

          lastStatus = retryAfterProofRefresh.statusCode;
          lastErrorBody =
              retryAfterProofRefresh.errorBody ?? 'Invalid proof after refresh';
        }

        final rebuilt = await _rebuildSessionIfNeeded(
          statusCode: lastStatus,
          errorBody: lastErrorBody,
          trigger: segmentName,
        );

        if (rebuilt) {
          _invalidateProofCache();
          continue;
        }

        if (lastStatus == HttpStatus.serviceUnavailable ||
            lastStatus == HttpStatus.notFound) {
          final retryAfterSec =
              _parseRetryAfterSeconds(result.retryAfterHeader, defaultValue: 1);
          await _adaptiveBackoffDelay(
            attempt,
            serverRetryAfterSec: retryAfterSec,
          );
          continue;
        }

        if (attempt + 1 >= maxAttempts) {
          break;
        }

        await _adaptiveBackoffDelay(attempt);
      }

      request.response.statusCode = lastStatus;
      request.response.write('Backend error: $lastErrorBody');
      return;
    } catch (e, stack) {
      debugPrint('[SecureHLS Proxy] Segment error: $e');
      debugPrint('[SecureHLS Proxy] Stack: $stack');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Error: $e');
    } finally {
      await request.response.close();
    }
  }

  Future<String> _generateBulletproofZkpProofCached({
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      _proofQueue.clear();
    }

    if (_proofQueue.isNotEmpty) {
      final proof = _proofQueue.removeFirst();
      _warmProofQueueIfNeeded();
      return proof;
    }

    await _warmProofQueueIfNeeded(force: true);
    if (_proofQueue.isNotEmpty) {
      final proof = _proofQueue.removeFirst();
      _warmProofQueueIfNeeded();
      return proof;
    }

    return _generateBulletproofZkpProof();
  }

  bool _isSegmentTicketUsable() {
    if (_segmentTicket == null || _segmentTicket!.isEmpty) {
      return false;
    }
    final expiresAtMs = _segmentTicketExpiresAtMs;
    if (expiresAtMs == null) {
      return true;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return nowMs < (expiresAtMs - 5000);
  }

  Future<String?> _ensureSegmentTicket({bool forceRefresh = false}) async {
    if (!forceRefresh && _isSegmentTicketUsable()) {
      return _segmentTicket;
    }

    if (_segmentTicketInFlight != null) {
      return _segmentTicketInFlight;
    }

    if (jwtToken == null || jwtToken!.isEmpty) {
      return null;
    }

    _segmentTicketInFlight = () async {
      final proof = await _generateBulletproofZkpProofCached(
        forceRefresh: forceRefresh,
      );

      final uri = Uri.parse(
        '$baseUrl/api/v1/secure-hls/session/$_sessionId/proof-ticket',
      );
      final request = await _backendClient.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.add('Authorization', 'Bearer $jwtToken');
      request.write(jsonEncode({'zkp_proof': proof}));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == HttpStatus.ok) {
        final payload = jsonDecode(body);
        if (payload is Map<String, dynamic> && payload['ticket'] is String) {
          _segmentTicket = payload['ticket'] as String;
          final expiresAt = payload['expires_at'];
          if (expiresAt is int) {
            _segmentTicketExpiresAtMs = expiresAt * 1000;
          } else {
            _segmentTicketExpiresAtMs = null;
          }
          return _segmentTicket;
        }
      }

      if (response.statusCode == HttpStatus.notFound) {
        return null;
      }

      throw StateError(
        'Failed to obtain segment ticket: ${response.statusCode} - $body',
      );
    }();

    try {
      return await _segmentTicketInFlight;
    } finally {
      _segmentTicketInFlight = null;
    }
  }

  Future<void> _warmProofQueueIfNeeded({bool force = false}) async {
    if (!force && (_proofQueue.length >= 2 || _proofBatchInFlight != null)) {
      return;
    }

    _proofBatchInFlight = _generateBulletproofZkpProofBatch(_proofBatchTarget)
        .then((proofs) {
          for (final proof in proofs) {
            _proofQueue.addLast(proof);
          }
        })
        .catchError((_) {})
        .whenComplete(() {
          _proofBatchInFlight = null;
        });

    await _proofBatchInFlight;
  }

  Future<List<String>> _generateBulletproofZkpProofBatch(int count) async {
    if (jwtToken == null || jwtToken!.isEmpty) {
      throw StateError('JWT token is required for batch proof generation');
    }

    final uri = Uri.parse('$baseUrl/api/v1/zkp/proof/generate-batch');
    final request = await _backendClient.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.headers.add('Authorization', 'Bearer $jwtToken');
    request.write(jsonEncode({
      'context': 'hls_segment_access',
      'count': count,
    }));

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw StateError(
        'Backend batch proof generation failed: ${response.statusCode} - $responseBody',
      );
    }

    final payload = jsonDecode(responseBody);
    if (payload is! Map<String, dynamic>) {
      throw StateError('Invalid batch proof payload format');
    }

    if (payload['success'] != true) {
      throw StateError(
        'Backend batch proof generation returned failure: ${payload['error']}',
      );
    }

    final proofsRaw = payload['proofs'];
    if (proofsRaw is! List) {
      throw StateError('Invalid proofs field in batch proof response');
    }

    final proofs = <String>[];
    for (final item in proofsRaw) {
      if (item is String) {
        proofs.add(item);
      } else if (item is Map) {
        proofs.add(base64Encode(utf8.encode(jsonEncode(item))));
      }
    }

    if (proofs.isEmpty) {
      throw StateError('Batch proof response did not include usable proofs');
    }

    return proofs;
  }

  Future<String> _generateBulletproofZkpProof() async {
    if (jwtToken == null || jwtToken!.isEmpty) {
      throw StateError('JWT token is required for ZKP proof generation');
    }

    _proofGenerateRequests += 1;
    try {
      final uri = Uri.parse('$baseUrl/api/v1/zkp/proof/generate');
      final request = await _backendClient.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.add('Authorization', 'Bearer $jwtToken');
      request.write(jsonEncode({
        'context': 'hls_segment_access',
      }));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        _proofGenerateFailures += 1;
        throw StateError(
          'Backend proof generation failed: ${response.statusCode} - $responseBody',
        );
      }

      final payload = jsonDecode(responseBody);
      if (payload is! Map<String, dynamic>) {
        throw StateError('Invalid proof response payload format');
      }

      final success = payload['success'] == true;
      if (!success) {
        final error = payload['error']?.toString() ?? 'unknown error';
        _proofGenerateFailures += 1;
        throw StateError('Backend proof generation failed: $error');
      }

      final proof = payload['proof'];
      if (proof is String) {
        return proof;
      }

      if (proof is Map) {
        final proofJson = jsonEncode(Map<String, dynamic>.from(proof));
        return base64Encode(utf8.encode(proofJson));
      }

      throw StateError('Invalid proof field type from backend');
    } catch (_) {
      _proofGenerateFailures += 1;
      rethrow;
    }
  }

  void _invalidateProofCache() {
    _segmentTicket = null;
    _segmentTicketExpiresAtMs = null;
    _proofQueue.clear();
  }

  int _parseRetryAfterSeconds(String? headerValue, {int defaultValue = 1}) {
    if (headerValue == null || headerValue.isEmpty) {
      return defaultValue;
    }
    final parsed = int.tryParse(headerValue.trim());
    if (parsed == null || parsed < 1) {
      return defaultValue;
    }
    return parsed.clamp(1, 8);
  }

  void _applyBackendNoDiskSignal(HttpHeaders headers) {
    final noDiskHeader = headers.value('x-no-disk-mode');
    final noDisk = noDiskHeader != null && noDiskHeader.toLowerCase() == 'true';

    if (noDisk == _backendNoDiskMode) {
      return;
    }

    _backendNoDiskMode = noDisk;
    if (_backendNoDiskMode) {
      _dynamicPrefetchRadius = 0;
      _dynamicPrefetchCooldown = const Duration(seconds: 2);
      _dynamicMaxAttempts = max(_dynamicMaxAttempts, 10);
      _dynamicBaseBackoffMs = max(_dynamicBaseBackoffMs, 420);
      _dynamicMaxBackoffMs = max(_dynamicMaxBackoffMs, 3800);
      _backendClient.maxConnectionsPerHost = 2;
      debugPrint(
        '[SecureHLS Proxy] Backend in no-disk mode; prefetch disabled and concurrency reduced',
      );
    } else {
      _applyInitialAdaptiveTuning();
      _backendClient.maxConnectionsPerHost = _dynamicMaxConnections;
    }
  }

  Future<_SegmentFetchResult> _fetchEncryptedSegment(
    String segmentName, {
    required bool forceRefreshProof,
  }) async {
    final startedAt = DateTime.now();
    final segmentUrl = '$baseUrl/api/v1/secure-hls/$_sessionId/$segmentName';
    final ticket = await _ensureSegmentTicket(forceRefresh: forceRefreshProof);
    final zkpProof = ticket == null
        ? await _generateBulletproofZkpProofCached(
            forceRefresh: forceRefreshProof,
          )
        : null;

    final backendRequest = await _backendClient.postUrl(Uri.parse(segmentUrl));
    backendRequest.headers.contentType = ContentType.json;
    if (jwtToken != null) {
      backendRequest.headers.add('Authorization', 'Bearer $jwtToken');
    }
    backendRequest.write(jsonEncode({
      if (ticket != null) 'zkp_ticket': ticket,
      if (zkpProof != null) 'zkp_proof': zkpProof,
    }));

    final backendResponse =
        await backendRequest.close().timeout(_segmentRequestTimeout);
    _applyBackendNoDiskSignal(backendResponse.headers);

    if (backendResponse.statusCode == HttpStatus.ok) {
      _postProofSuccessHits += 1;
      final encryptedData = await backendResponse.fold<List<int>>(
        [],
        (previous, element) => previous..addAll(element),
      ).timeout(_segmentRequestTimeout);
      _updateAdaptiveNetworkTuning(
        statusCode: HttpStatus.ok,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
      return _SegmentFetchResult(
        statusCode: HttpStatus.ok,
        data: Uint8List.fromList(encryptedData),
      );
    }

    final errorBody = await backendResponse
        .transform(utf8.decoder)
        .join()
        .timeout(_segmentRequestTimeout);
    debugPrint(
      '[SecureHLS Proxy] Backend error: ${backendResponse.statusCode} - $errorBody',
    );
    _updateAdaptiveNetworkTuning(
      statusCode: backendResponse.statusCode,
      elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
    return _SegmentFetchResult(
      statusCode: backendResponse.statusCode,
      errorBody: errorBody,
      retryAfterHeader: backendResponse.headers.value('retry-after'),
    );
  }

  Future<Uint8List> _decryptSegment(Uint8List encryptedData) async {
    if (encryptedData.length < 28) {
      debugPrint(
          '[SecureHLS Proxy] Invalid encrypted data length: ${encryptedData.length}');
      throw Exception('Invalid encrypted data format');
    }

    try {
      final nonce = encryptedData.sublist(0, 12);
      final decryptionKey = _deriveKey(_pmk, 'hls-master-key');

      final ciphertext = encryptedData.sublist(12, encryptedData.length - 16);
      final macBytes = encryptedData.sublist(encryptedData.length - 16);

      final plaintext = await Chacha20.poly1305Aead().decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(macBytes)),
        secretKey: SecretKey(decryptionKey),
      );

      debugPrint(
          '[SecureHLS Proxy] Decrypted segment: ${plaintext.length} bytes');
      return Uint8List.fromList(plaintext);
    } catch (e, stack) {
      debugPrint('[SecureHLS Proxy] Decryption error: $e');
      debugPrint('[SecureHLS Proxy] Stack trace: $stack');
      rethrow;
    }
  }

  Uint8List _deriveKey(Uint8List key, String info) {
    final hkdf = HkdfBlake3.withSessionSalt(_sessionId, key);
    return hkdf.expand(Uint8List.fromList(utf8.encode(info)), 32);
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
        lower.contains('invalid zkp proof') ||
        lower.contains('does not have zkp registration');
  }

  Future<bool> _rebuildSessionIfNeeded({
    required int statusCode,
    required String errorBody,
    required String trigger,
  }) async {
    if (onSessionRebuild == null) {
      return false;
    }
    if (!_shouldRebuildSession(statusCode, errorBody)) {
      return false;
    }

    if (_sessionRebuildFuture != null) {
      final rebuilt = await _sessionRebuildFuture!;
      _sessionId = rebuilt.$1;
      _pmk = rebuilt.$2;
      _invalidateProofCache();
      return true;
    }

    debugPrint(
        '[SecureHLS Proxy] Session appears stale during $trigger, rebuilding chain...');

    _sessionRebuildFuture = onSessionRebuild!.call();
    try {
      final rebuilt = await _sessionRebuildFuture!;
      _sessionId = rebuilt.$1;
      _pmk = rebuilt.$2;
      _invalidateProofCache();
      debugPrint('[SecureHLS Proxy] Session rebuilt: $_sessionId');
      return true;
    } catch (e) {
      debugPrint('[SecureHLS Proxy] Session rebuild failed: $e');
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
  final int proofGenerateRequests;
  final int proofGenerateFailures;
  final int segmentRetries;
  final int fallbackGetHits;
  final int postProofSuccessHits;

  const SecureHlsRuntimeSnapshot({
    required this.proofGenerateRequests,
    required this.proofGenerateFailures,
    required this.segmentRetries,
    required this.fallbackGetHits,
    required this.postProofSuccessHits,
  });

  bool get zkpActive => postProofSuccessHits > 0;
  bool get fallbackActive => fallbackGetHits > 0;
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
    if (lowMemoryMode || cpuCores <= 4) {
      return const Duration(milliseconds: 1200);
    }
    if (bitrateMbps >= 12) {
      return const Duration(milliseconds: 900);
    }
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
