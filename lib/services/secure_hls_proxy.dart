import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import 'hkdf_blake3.dart';

/// 安全 HLS 代理服务器
///
/// 使用 Bulletproofs 零知识证明进行视频段访问认证
///
/// 工作原理：
/// 1. 启动本地 HTTP 服务器（127.0.0.1:随机端口）
/// 2. 拦截播放器的 .ts 段请求
/// 3. 生成 Bulletproofs ZKP 证明（证明密码知识）
/// 4. 向后端发送 POST 请求（带 ZKP 证明）
/// 5. 解密视频段（使用 AES-256-GCM）
/// 6. 返回明文视频段给播放器
class SecureHlsProxyServer {
  HttpServer? _server;
  int? _port;
  final String baseUrl;
  String _sessionId;
  Uint8List _pmk; // Pairwise Master Key
  final String? password;
  final String? jwtToken; // JWT token for authenticated requests
  final Future<(String, Uint8List)> Function()? onSessionRebuild;
  final SecureHlsAdaptiveConfig adaptiveConfig;
  Future<(String, Uint8List)>? _sessionRebuildFuture;

  final Set<String> _prefetchInFlight = <String>{};
  int? _lastPrefetchCenter;
  DateTime? _lastPrefetchAt;

  /// ★ 复用单个 HttpClient 实例，启用 HTTP keep-alive 连接池
  /// 避免每个 segment 请求都创建新连接（大幅减少 TCP 握手开销）
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
  final Queue<String> _proofQueue = Queue<String>();
  Future<void>? _proofBatchInFlight;
  static const int _proofBatchTarget = 6;

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

  /// 启动代理服务器
  Future<String> start() async {
    try {
      // 绑定到本地回环地址的随机端口
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;

      debugPrint('[SecureHLS Proxy] Started on http://127.0.0.1:$_port');
      debugPrint('[SecureHLS Proxy] Using Bulletproofs ZKP authentication');

      // 处理请求
      _server!.listen(_handleRequest);

      // 预热一批 proof，避免首批 segment 请求阻塞在 proof 生成 RTT。
      unawaited(_warmProofQueueIfNeeded(force: true));
      unawaited(_ensureSegmentTicket(forceRefresh: true));

      // 返回代理服务器的播放列表 URL
      return 'http://127.0.0.1:$_port/playlist.m3u8';
    } catch (e) {
      debugPrint('[SecureHLS Proxy] Failed to start: $e');
      rethrow;
    }
  }

  /// 停止代理服务器
  Future<void> stop() async {
    _backendClient.close(force: true);
    await _server?.close(force: true);
    _server = null;
    _port = null;
    debugPrint('[SecureHLS Proxy] Stopped');
  }

  /// 预取指定段附近的视频段
  ///
  /// 在 seek 操作时调用，提前请求目标段附近的数据以减少延迟。
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

    // 预取窗口按实时网络状态动态调整。
    final radius =
        _dynamicPrefetchRadius.clamp(_minPrefetchRadius, _maxPrefetchRadius);
    final start = max(0, segmentIndex - radius);
    final end = segmentIndex + radius;

    for (int i = start; i <= end; i++) {
      final segmentName = 'segment_$i.ts';

      if (_prefetchInFlight.length >= adaptiveConfig.maxPrefetchInFlight) {
        break;
      }

      // 异步预取，不阻塞当前操作
      _prefetchSegment(segmentName).catchError((e) {
        debugPrint('[SecureHLS Proxy] Prefetch failed for $segmentName: $e');
      });
    }
  }

  /// 异步预取单个视频段
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
        // 读取并丢弃——让系统层面的缓存生效
        await response.drain<void>();
        debugPrint('[SecureHLS Proxy] Prefetched: $segmentName');
      } else {
        // 失败响应同样要消费完，避免连接池中残留脏流。
        await response.drain<void>();
      }
    } catch (e) {
      // 预取失败不影响正常播放
      debugPrint('[SecureHLS Proxy] Prefetch error for $segmentName: $e');
    } finally {
      _prefetchInFlight.remove(segmentName);
    }
  }

  /// 处理 HTTP 请求
  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      debugPrint('[SecureHLS Proxy] Request: ${request.method} $path');

      if (path == '/playlist.m3u8') {
        // 转发播放列表请求
        await _handlePlaylistRequest(request);
      } else if (path.endsWith('.ts')) {
        // 拦截视频段请求，添加 ZKP 证明
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

  /// 处理播放列表请求
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

  /// 修改播放列表，替换视频段 URL
  String _modifyPlaylist(String content) {
    // 将 segment_N.ts 替换为代理服务器的 URL
    return content.replaceAllMapped(
      RegExp(r'(segment_\d+\.ts)'),
      (match) => 'http://127.0.0.1:$_port/${match.group(1)}',
    );
  }

  /// 处理视频段请求（使用 Bulletproofs ZKP 证明）
  Future<void> _handleSegmentRequest(HttpRequest request, String path) async {
    try {
      final segmentName = path.substring(1); // 移除开头的 '/'

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
          final decryptedData = _decryptSegment(result.data!);

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
            final decryptedData = _decryptSegment(retryAfterProofRefresh.data!);
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

  /// 生成完整的 Bulletproofs ZKP 证明（由后端 Rust 统一生成）
  ///
  /// 通过受保护接口 `/api/v1/zkp/proof/generate` 调用服务端
  /// `rockzero_crypto::ZkpContext::generate_enhanced_proof`，确保前后端证明格式完全一致。
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

    // 兜底：批量接口不可用时回退单个 proof。
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

    if (jwtToken == null || jwtToken!.isEmpty) {
      return null;
    }

    final proof = await _generateBulletproofZkpProofCached(
      forceRefresh: forceRefresh,
    );

    final client = HttpClient();
    try {
      final uri = Uri.parse(
        '$baseUrl/api/v1/secure-hls/session/$_sessionId/proof-ticket',
      );
      final request = await client.postUrl(uri);
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
        // Legacy backend without ticket endpoint.
        return null;
      }

      throw StateError(
        'Failed to obtain segment ticket: ${response.statusCode} - $body',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _warmProofQueueIfNeeded({bool force = false}) async {
    if (!force && (_proofQueue.length >= 2 || _proofBatchInFlight != null)) {
      return;
    }

    _proofBatchInFlight =
        _generateBulletproofZkpProofBatch(_proofBatchTarget).then((proofs) {
      for (final proof in proofs) {
        _proofQueue.addLast(proof);
      }
    }).catchError((_) {
      // 忽略批量生成错误，调用方会回退单个 proof。
    }).whenComplete(() {
      _proofBatchInFlight = null;
    });

    await _proofBatchInFlight;
  }

  Future<List<String>> _generateBulletproofZkpProofBatch(int count) async {
    if (jwtToken == null || jwtToken!.isEmpty) {
      throw StateError('JWT token is required for batch proof generation');
    }

    final client = HttpClient();
    try {
      final uri = Uri.parse('$baseUrl/api/v1/zkp/proof/generate-batch');
      final request = await client.postUrl(uri);
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
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _generateBulletproofZkpProof() async {
    if (jwtToken == null || jwtToken!.isEmpty) {
      throw StateError('JWT token is required for ZKP proof generation');
    }

    _proofGenerateRequests += 1;

    final client = HttpClient();
    try {
      final uri = Uri.parse('$baseUrl/api/v1/zkp/proof/generate');
      final request = await client.postUrl(uri);
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
    } finally {
      client.close(force: true);
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
    return parsed.clamp(1, 5);
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

    final backendResponse = await backendRequest.close();
    _applyBackendNoDiskSignal(backendResponse.headers);

    if (backendResponse.statusCode == HttpStatus.ok) {
      _postProofSuccessHits += 1;
      final encryptedData = await backendResponse.fold<List<int>>(
        [],
        (previous, element) => previous..addAll(element),
      );
      _updateAdaptiveNetworkTuning(
        statusCode: HttpStatus.ok,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
      return _SegmentFetchResult(
        statusCode: HttpStatus.ok,
        data: Uint8List.fromList(encryptedData),
      );
    }

    final errorBody = await backendResponse.transform(utf8.decoder).join();
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

  /// 解密视频段（完整的 AES-256-GCM 实现）
  ///
  /// Rust端加密数据格式（使用 aes_gcm crate）：
  /// - 前 12 字节：nonce
  /// - 剩余部分：ciphertext + tag（tag自动附加在ciphertext末尾）
  Uint8List _decryptSegment(Uint8List encryptedData) {
    if (encryptedData.length < 28) {
      // 至少需要 12 字节 nonce + 16 字节 tag
      debugPrint(
          '[SecureHLS Proxy] Invalid encrypted data length: ${encryptedData.length}');
      throw Exception('Invalid encrypted data format');
    }

    try {
      // 提取 nonce（前 12 字节）
      final nonce = encryptedData.sublist(0, 12);

      // 剩余部分是 ciphertext + tag（tag 已经附加在 ciphertext 末尾）
      final ciphertextWithTag = encryptedData.sublist(12);

      // 从 PMK 派生解密密钥（AES-256 需要 32 字节）
      // 使用与 Rust 端完全一致的 info 参数："hls-master-key"
      final decryptionKey = _deriveKey(_pmk, 'hls-master-key');

      // 使用完整的 AES-256-GCM 解密
      // pointycastle 的 GCM 实现会自动处理附加在末尾的 tag
      final plaintext = _aesGcmDecrypt(
        ciphertextWithTag: ciphertextWithTag,
        key: decryptionKey,
        nonce: nonce,
      );

      debugPrint(
          '[SecureHLS Proxy] Decrypted segment: ${plaintext.length} bytes');
      return plaintext;
    } catch (e, stack) {
      debugPrint('[SecureHLS Proxy] Decryption error: $e');
      debugPrint('[SecureHLS Proxy] Stack trace: $stack');
      rethrow;
    }
  }

  /// AES-256-GCM 解密（完整的生产级实现）
  ///
  /// 使用 pointycastle 库实现标准的 AES-GCM 解密
  ///
  /// 参数：
  /// - ciphertextWithTag: 加密的数据 + 认证标签（tag 附加在末尾）
  /// - key: 32 字节的 AES-256 密钥
  /// - nonce: 12 字节的 nonce（IV）
  ///
  /// 返回：解密后的明文数据
  ///
  /// 抛出：如果认证失败或解密失败
  ///
  /// 注意：Rust 的 aes_gcm crate 会自动将 16 字节的 tag 附加到 ciphertext 末尾
  Uint8List _aesGcmDecrypt({
    required Uint8List ciphertextWithTag,
    required Uint8List key,
    required Uint8List nonce,
  }) {
    try {
      // 验证参数长度
      if (key.length != 32) {
        throw ArgumentError(
            'AES-256 requires a 32-byte key, got ${key.length}');
      }
      if (nonce.length != 12) {
        throw ArgumentError(
            'GCM requires a 12-byte nonce, got ${nonce.length}');
      }
      if (ciphertextWithTag.length < 16) {
        throw ArgumentError(
            'Ciphertext too short, must include 16-byte tag, got ${ciphertextWithTag.length}');
      }

      // 创建 AES-GCM 解密器
      final cipher = GCMBlockCipher(AESEngine());

      // 设置参数
      // pointycastle 的 GCM 实现期望 ciphertext + tag 作为输入
      final params = AEADParameters(
        KeyParameter(key),
        128, // tag 长度（位）
        nonce,
        Uint8List(0), // 附加认证数据（AAD）为空
      );

      // 初始化解密器
      cipher.init(false, params); // false = 解密模式

      // 执行解密（输入是 ciphertext + tag）
      final plaintext = cipher.process(ciphertextWithTag);

      debugPrint('[SecureHLS Proxy] AES-GCM decryption successful');
      return plaintext;
    } on ArgumentError catch (e) {
      debugPrint('[SecureHLS Proxy] Invalid GCM parameters: $e');
      throw Exception('GCM decryption failed: Invalid parameters - $e');
    } catch (e) {
      // 认证失败或其他错误
      debugPrint('[SecureHLS Proxy] GCM decryption failed: $e');
      throw Exception(
          'GCM decryption failed: Authentication tag verification failed or corrupted data');
    }
  }

  /// 从密钥派生子密钥（使用 HKDF-Blake3，与 Rust 端完全一致）
  ///
  /// Rust 端使用：
  /// ```rust
  /// let hkdf = HkdfBlake3::new_with_session_salt(&session_id, &pmk);
  /// hkdf.expand(b"hls-master-key", &mut encryption_key);
  /// ```
  ///
  /// 参数：
  /// - key: 主密钥（PMK）
  /// - info: 上下文信息字符串
  ///
  /// 返回：32 字节的派生密钥
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
