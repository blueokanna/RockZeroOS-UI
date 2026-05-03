import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory, getDownloadsDirectory;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/i18n/app_localizations.dart';
import '../../../../core/widgets/md3_loading_indicator.dart';
import '../../../../core/widgets/shell_scaffold.dart';
import '../../../../core/services/audio_player_service.dart';
import '../../../../services/sae_handshake_service.dart';
import '../../../../services/secure_hls_proxy.dart';

class SecureHlsVideoPlayer extends ConsumerStatefulWidget {
  final String? filePath;
  final String? fileId;
  final String fileName;
  final String baseUrl;

  const SecureHlsVideoPlayer({
    super.key,
    this.filePath,
    this.fileId,
    required this.fileName,
    required this.baseUrl,
  }) : assert(filePath != null || fileId != null,
            'Either filePath or fileId is required');

  @override
  ConsumerState<SecureHlsVideoPlayer> createState() =>
      _SecureHlsVideoPlayerState();
}

class _SecureHlsVideoPlayerState extends ConsumerState<SecureHlsVideoPlayer>
    with WidgetsBindingObserver {
  static const int _maxPlaybackStartupAttempts = 3;
  static const int _maxDownloadAttempts = 4;

  Player? _player;
  VideoController? _videoController;

  bool _isLoading = true;
  String? _error;
  bool _lastErrorIsFatal = false;
  String _loadingStatus = '';
  String? _authToken;
  String? _hlsSessionId;
  String? _userId;
  String? _userSaeSecret;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  bool _isRecoveringSession = false;
  int _downloadTotalBytes = 0;
  int _downloadReceivedBytes = 0;
  DateTime _lastDownloadPersistAt = DateTime.fromMillisecondsSinceEpoch(0);

  Timer? _networkTelemetryTimer;
  final ListQueue<double> _networkScoreSamples = ListQueue<double>();
  double _networkScore = 0.0;
  int _lastObservedSegmentRetries = 0;
  int _latestRetryDelta = 0;
  int _latestBufferAheadSec = 0;

  SecureHlsProxyServer? _proxyServer;

  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _showControls = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _durationHint = Duration.zero;
  int? _videoBitrateBps;
  bool _isDraggingProgress = false;
  Duration? _dragPreviewPosition;
  Duration? _lastSavedPosition;
  Duration _bufferedPosition = Duration.zero;
  Timer? _hideControlsTimer;
  DateTime _lastProgressSaveAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _resumePromptShown = false;

  double _playbackSpeed = 1.0;
  static const List<double> _speedOptions = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    3.0
  ];

  final List<StreamSubscription> _subscriptions = [];

  AppLocalizations get _strings =>
      AppLocalizations(WidgetsBinding.instance.platformDispatcher.locale);
  String _tr(String key, [Map<String, String> args = const {}]) =>
      _strings.tr(key, args);

  @override
  void initState() {
    super.initState();
    _loadingStatus = _tr('video.loading.connecting');
    WidgetsBinding.instance.addObserver(this);
    _enterFullscreen();
    WakelockPlus.enable();
    _initPlayer();
    _startHideControlsTimer();
    _startNetworkTelemetrySampler();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_persistDownloadTaskSnapshot());
      unawaited(_saveResumeProgressIfNeeded(_position));
    }
  }

  void _startNetworkTelemetrySampler() {
    _networkTelemetryTimer?.cancel();
    _networkTelemetryTimer = Timer.periodic(
      const Duration(milliseconds: 1200),
      (_) => _sampleNetworkTelemetry(),
    );
  }

  void _sampleNetworkTelemetry() {
    if (!mounted) return;

    final runtime = _proxyServer?.runtimeSnapshot;
    final retries = runtime?.segmentRetries ?? 0;
    final retryDelta = max(0, retries - _lastObservedSegmentRetries);
    _lastObservedSegmentRetries = retries;

    final bufferAheadMs =
        max(0, _bufferedPosition.inMilliseconds - _position.inMilliseconds);
    final bufferAheadSec = (bufferAheadMs / 1000).floor();

    final normalizedBuffer = (bufferAheadSec / 12.0).clamp(0.0, 1.0);
    final proofReq = runtime?.proofGenerateRequests ?? 0;
    final proofFail = runtime?.proofGenerateFailures ?? 0;
    final proofFailureRate = proofReq > 0 ? proofFail / proofReq : 0.0;

    double score = 0.15 + normalizedBuffer * 0.72;
    if (_isBuffering) {
      score -= 0.25;
    }
    score -= retryDelta * 0.12;
    score -= proofFailureRate * 0.22;
    score = score.clamp(0.0, 1.0);

    _networkScoreSamples.addLast(score);
    while (_networkScoreSamples.length > 22) {
      _networkScoreSamples.removeFirst();
    }

    setState(() {
      _networkScore = score;
      _latestRetryDelta = retryDelta;
      _latestBufferAheadSec = bufferAheadSec;
    });
  }

  String _networkQualityLabel() {
    if (_networkScore >= 0.75) return _tr('video.network.stable');
    if (_networkScore >= 0.45) return _tr('video.network.fair');
    return _tr('video.network.poor');
  }

  Color _networkQualityColor() {
    if (_networkScore >= 0.75) return Colors.greenAccent;
    if (_networkScore >= 0.45) return Colors.amberAccent;
    return Colors.redAccent;
  }

  Future<void> _initPlayer() async {
    try {
      ref.read(audioPlayerServiceProvider.notifier).stop();

      setState(() {
        _isLoading = true;
        _error = null;
        _lastErrorIsFatal = false;
        _loadingStatus = _tr('video.loading.fetch_credentials');
      });

      const storage = FlutterSecureStorage();
      _authToken = await storage.read(key: 'access_token');
      _userId = await storage.read(key: 'user_id');
      _userSaeSecret = await storage.read(key: 'user_password_hash');

      if (_authToken == null || _authToken!.isEmpty) {
        _setError(_tr('video.error.not_logged_in'), fatal: true);
        return;
      }

      if (_userId == null || _userSaeSecret == null) {
        _setError(_tr('video.error.missing_credentials'), fatal: true);
        return;
      }

      await _loadResumeProgress();
      await _fetchDurationHint();
      await _tryRecoverPendingDownloadTask();

      await _tryHlsStreamingWithRetries();
    } catch (e, stack) {
      debugPrint('[VideoPlayer] Error: $e');
      debugPrint('[VideoPlayer] Stack: $stack');
      _setError(
        _tr('video.error.play_failed', {'message': _formatError(e.toString())}),
      );
    }
  }

  Future<void> _tryHlsStreamingWithRetries() async {
    Object? lastError;
    for (int attempt = 1; attempt <= _maxPlaybackStartupAttempts; attempt++) {
      if (!mounted) return;
      if (attempt > 1) {
        setState(() {
          _loadingStatus = _tr('video.loading.retry_connecting', {
            'attempt': '$attempt',
            'total': '$_maxPlaybackStartupAttempts',
          });
        });
      }
      try {
        await _tryHlsStreaming();
        if (_error == null) {
          return;
        }
        if (_lastErrorIsFatal) {
          return;
        }
        lastError = _error;
      } catch (e) {
        lastError = e;
      }

      if (attempt < _maxPlaybackStartupAttempts) {
        await Future.delayed(_retryDelay(attempt));
      }
    }

    if (mounted && _error == null && lastError != null) {
      _setError(_tr('video.error.play_init_failed', {
        'message': _formatError(lastError.toString()),
      }));
    }
  }

  Duration _retryDelay(int attempt) {
    final baseMs = (450 * (1 << (attempt - 1))).clamp(450, 5000);
    final jitterMs = Random().nextInt(300);
    return Duration(milliseconds: baseMs + jitterMs);
  }

  bool _isFatalPlaylistStatus(int statusCode) {
    return statusCode == 401 || statusCode == 403 || statusCode == 412;
  }

  bool _isRetryableHandshakeError(SaeHandshakeException e) {
    return e.statusCode == 0 ||
        e.statusCode == 408 ||
        e.statusCode == 429 ||
        e.statusCode == 500 ||
        e.statusCode == 502 ||
        e.statusCode == 503 ||
        e.statusCode == 504;
  }

  Future<void> _tryHlsStreaming() async {
    setState(() {
      _loadingStatus = _tr('video.loading.handshake');
    });

    debugPrint('[VideoPlayer] Starting SAE handshake for secure HLS...');

    final handshakeService = SaeHandshakeService(
      baseUrl: widget.baseUrl,
      jwtToken: _authToken!,
    );

    final filePath = widget.filePath;
    final fileId = widget.fileId;

    late final String sessionId;
    late final Uint8List pmk;

    try {
      final result = await handshakeService.performHandshake(
        filePath: filePath,
        fileId: fileId,
        password: _userSaeSecret!,
        userId: _userId!,
        directMode: false,
      );

      sessionId = result.$1;
      pmk = result.$2;
      _hlsSessionId = sessionId;
    } on SaeHandshakeException catch (e) {
      debugPrint('[VideoPlayer] SAE/session stage failed: $e');
      if (e.stage == SaeStage.createSession) {
        if (e.statusCode == 412) {
          _setError(
              _tr('video.error.session_create_rejected', {
                'message': _formatError(e.message),
              }),
              fatal: true);
        } else {
          _setError(
              _tr('video.error.session_create_failed', {
                'status': '${e.statusCode}',
                'message': _formatError(e.message),
              }),
              fatal: e.statusCode >= 400 && e.statusCode < 500);
        }
      } else {
        _setError(
            _tr('video.error.sae_stage_failed', {
              'stage': e.stage.name,
              'status': '${e.statusCode}',
              'message': _formatError(e.message),
            }),
            fatal: e.stage == SaeStage.createSession &&
                e.statusCode >= 400 &&
                e.statusCode < 500);
      }
      return;
    } catch (e) {
      debugPrint('[VideoPlayer] SAE handshake failed: $e');
      _setError(_tr('video.error.sae_failed', {
        'message': _formatError(e.toString()),
      }));
      return;
    }

    debugPrint('[VideoPlayer] HLS session (encrypted mode): $sessionId');

    if (!mounted) return;
    setState(() => _loadingStatus = _tr('video.loading.starting_proxy'));

    late final String proxyPlaylistUrl;

    try {
      Future<(String, Uint8List)> rebuildSession() async {
        debugPrint('[VideoPlayer] Rebuilding SAE session...');
        Object? lastError;
        if (mounted) {
          setState(() => _isRecoveringSession = true);
        }
        try {
          for (int attempt = 1; attempt <= 3; attempt++) {
            try {
              final newResult = await handshakeService.performHandshake(
                filePath: filePath,
                fileId: fileId,
                password: _userSaeSecret!,
                userId: _userId!,
                directMode: false,
              );
              _hlsSessionId = newResult.$1;
              return newResult;
            } on SaeHandshakeException catch (e) {
              lastError = e;
              if (!_isRetryableHandshakeError(e) || attempt >= 3) {
                rethrow;
              }
              await Future.delayed(_retryDelay(attempt));
            } catch (e) {
              lastError = e;
              if (attempt >= 3) {
                rethrow;
              }
              await Future.delayed(_retryDelay(attempt));
            }
          }
        } finally {
          if (mounted) {
            setState(() => _isRecoveringSession = false);
          }
        }
        throw Exception(_tr('video.error.session_rebuild_failed', {
          'message': '${lastError ?? _tr('video.error.unknown')}',
        }));
      }

      _proxyServer = SecureHlsProxyServer(
        baseUrl: widget.baseUrl,
        sessionId: sessionId,
        pmk: pmk,
        password: _userSaeSecret!,
        jwtToken: _authToken,
        onSessionRebuild: rebuildSession,
        adaptiveConfig: _buildAdaptiveConfig(),
      );

      proxyPlaylistUrl = await _proxyServer!.start();
      debugPrint('[VideoPlayer] Secure proxy started: $proxyPlaylistUrl');
    } catch (e) {
      debugPrint('[VideoPlayer] Failed to start secure proxy: $e');
      _setError(_tr('video.error.proxy_start_failed', {
        'message': _formatError(e.toString()),
      }));
      return;
    }

    if (!mounted) return;
    setState(() => _loadingStatus = _tr('video.loading.waiting_segments'));

    bool playlistReady = false;
    int consecutiveFatal5xx = 0;
    for (int i = 0; i < 90; i++) {
      if (!mounted) return;

      try {
        final checkResponse = await http
            .get(Uri.parse(proxyPlaylistUrl))
            .timeout(const Duration(seconds: 5));

        if (_isFatalPlaylistStatus(checkResponse.statusCode)) {
          _setError(
              _tr('video.error.playlist_auth_failed', {
                'status': '${checkResponse.statusCode}',
              }),
              fatal: true);
          return;
        }

        if (checkResponse.statusCode >= 500 &&
            checkResponse.statusCode != 503) {
          consecutiveFatal5xx += 1;
          if (consecutiveFatal5xx >= 3) {
            _setError(_tr('video.error.segment_service_failed', {
              'status': '${checkResponse.statusCode}',
            }));
            return;
          }
        } else {
          consecutiveFatal5xx = 0;
        }

        if (checkResponse.statusCode == 200) {
          final content = checkResponse.body;
          if (_isPlaylistReadyForPlayback(content)) {
            debugPrint(
                '[VideoPlayer] HLS playlist ready after ${i + 1} attempts');
            playlistReady = true;
            break;
          }
        }
        debugPrint(
            '[VideoPlayer] HLS playlist not ready (status=${checkResponse.statusCode}), waiting... (${i + 1}s)');
      } catch (e) {
        debugPrint(
            '[VideoPlayer] HLS playlist check failed: $e, waiting... (${i + 1}s)');
      }

      if (i < 5) {
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        await Future.delayed(const Duration(seconds: 1));
      }

      if (mounted) {
        setState(() {
          _loadingStatus = _tr('video.loading.waiting_segments_seconds', {
            'seconds': '${i + 1}',
          });
        });
      }
    }

    if (!playlistReady) {
      _setError(_tr('video.error.playlist_timeout'));
      return;
    }

    if (!mounted) return;

    setState(() => _loadingStatus = _tr('video.loading.initializing_player'));

    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: _calculateAdaptiveBufferBytes(),
      ),
    );

    if (_player!.platform is NativePlayer) {
      final mpv = _player!.platform as NativePlayer;
      await mpv.setProperty('demuxer-max-bytes', '256MiB');
      await mpv.setProperty('demuxer-readahead-secs', '32');
      await mpv.setProperty('cache', 'yes');
      await mpv.setProperty('cache-secs', '48');
      await mpv.setProperty('cache-pause', 'yes');
      await mpv.setProperty('cache-pause-wait', '1.0');
      await mpv.setProperty('demuxer-max-back-bytes', '64MiB');
      await mpv.setProperty('vd-lavc-threads', '0');
      await mpv.setProperty('ad-lavc-threads', '0');
      await mpv.setProperty('hwdec', 'auto-safe');
      await mpv.setProperty('vd-lavc-software-fallback', 'yes');
      await mpv.setProperty('video-sync', 'audio');
      await mpv.setProperty('interpolation', 'no');
      await mpv.setProperty('audio-pitch-correction', 'yes');
      await mpv.setProperty('hr-seek', 'yes');
      await mpv.setProperty('rebase-start-time', 'yes');
      await mpv.setProperty(
        'demuxer-lavf-o',
        'fflags=+genpts+discardcorrupt',
      );
      await mpv.setProperty('force-seekable', 'yes');
      await _applyAdaptiveMpvTuning(mpv);
    }

    _videoController = VideoController(_player!);
    _setupPlayerListeners();

    final errorCompleter = Completer<String?>();
    StreamSubscription<String>? errorSub;
    errorSub = _player!.stream.error.listen((error) {
      if (error.isNotEmpty && !errorCompleter.isCompleted) {
        errorCompleter.complete(error);
        errorSub?.cancel();
      }
    });

    final playingCompleter = Completer<bool>();
    StreamSubscription<bool>? playingSub;
    playingSub = _player!.stream.playing.listen((playing) {
      if (playing && !playingCompleter.isCompleted) {
        playingCompleter.complete(true);
        playingSub?.cancel();
      }
    });

    final durationCompleter = Completer<bool>();
    StreamSubscription<Duration>? durationSub;
    durationSub = _player!.stream.duration.listen((dur) {
      if (dur.inMilliseconds > 0 && !durationCompleter.isCompleted) {
        durationCompleter.complete(true);
        durationSub?.cancel();
      }
    });

    await _player!.open(
      Media(proxyPlaylistUrl),
      play: true,
    );
    final result = await Future.any([
      playingCompleter.future.then((_) => 'playing'),
      durationCompleter.future.then((_) => 'duration_ready'),
      errorCompleter.future.then((e) => 'error:$e'),
      Future.delayed(const Duration(seconds: 25), () => 'timeout'),
    ]);

    errorSub.cancel();
    playingSub.cancel();
    durationSub.cancel();

    if (result == 'playing' || result == 'duration_ready') {
      debugPrint('[VideoPlayer] HLS playback started successfully ($result)');
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _offerResumePromptIfNeeded();
      return;
    }

    if (result == 'timeout') {
      debugPrint(
          '[VideoPlayer] HLS playback timeout but no error — showing player');
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _offerResumePromptIfNeeded();
      return;
    }

    debugPrint('[VideoPlayer] HLS playback error: $result');
    _setError(_tr('video.error.play_failed', {
      'message': _formatError(result.toString()),
    }));
  }

  void _setupPlayerListeners() {
    _cancelSubscriptions();

    _subscriptions.add(_player!.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    }));

    _subscriptions.add(_player!.stream.position.listen((position) {
      if (mounted) {
        setState(() => _position = position);
      }
      _saveResumeProgressIfNeeded(position);
    }));

    _subscriptions.add(_player!.stream.duration.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    }));

    _subscriptions.add(_player!.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    }));

    _subscriptions.add(_player!.stream.buffer.listen((buffer) {
      if (mounted) setState(() => _bufferedPosition = buffer);
    }));

    _subscriptions.add(_player!.stream.error.listen((error) {
      if (error.isNotEmpty && mounted) {
        debugPrint('[SecureHLS] Player error: $error');
      }
    }));

    _subscriptions.add(_player!.stream.completed.listen((completed) {
      if (completed && mounted) {
        debugPrint('[SecureHLS] Playback completed');
        _clearResumeProgress();
      }
    }));
  }

  String _resumeProgressKey() {
    final stableId = widget.filePath ?? widget.fileId ?? widget.fileName;
    final normalized = Uri.encodeComponent(stableId);
    return 'secure_hls_progress:$normalized';
  }

  Future<void> _loadResumeProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_resumeProgressKey());
      if (ms != null && ms > 0) {
        _lastSavedPosition = Duration(milliseconds: ms);
      }
    } catch (e) {
      debugPrint('[SecureHLS] Failed to load resume progress: $e');
    }
  }

  Future<void> _clearResumeProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_resumeProgressKey());
      _lastSavedPosition = null;
    } catch (e) {
      debugPrint('[SecureHLS] Failed to clear resume progress: $e');
    }
  }

  Future<void> _saveResumeProgressIfNeeded(Duration position) async {
    if (position.inSeconds < 5) return;

    final total = _effectiveTotalDuration;
    if (total.inSeconds > 0 &&
        position >= total - const Duration(seconds: 10)) {
      await _clearResumeProgress();
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastProgressSaveAt).inSeconds < 2) return;
    _lastProgressSaveAt = now;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_resumeProgressKey(), position.inMilliseconds);
    } catch (e) {
      debugPrint('[SecureHLS] Failed to save resume progress: $e');
    }
  }

  Future<void> _fetchDurationHint() async {
    final mediaPath = widget.filePath;
    if (mediaPath == null || mediaPath.isEmpty) return;
    if (_authToken == null || _authToken!.isEmpty) return;

    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/api/v1/filemanager/media/info?path=${Uri.encodeQueryComponent(mediaPath)}',
      );
      final response = await http.get(uri, headers: {
        'Authorization': 'Bearer $_authToken',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final dynamic rawDuration = data['duration'];
      final double? durationSeconds =
          rawDuration is num ? rawDuration.toDouble() : null;
      final dynamic rawBitrate = data['bitrate'] ?? data['bit_rate'];
      final int? bitrate = rawBitrate is num
          ? rawBitrate.toInt()
          : int.tryParse(rawBitrate?.toString() ?? '');
      if (durationSeconds != null && durationSeconds > 0) {
        final hint = Duration(milliseconds: (durationSeconds * 1000).round());
        if (!mounted) return;
        setState(() {
          if (hint > _durationHint) {
            _durationHint = hint;
          }
          if (bitrate != null && bitrate > 0) {
            _videoBitrateBps = bitrate;
          }
        });
      }
    } catch (e) {
      debugPrint('[SecureHLS] Failed to fetch duration hint: $e');
    }
  }

  int _calculateAdaptiveBufferBytes() {
    final bitrate = _videoBitrateBps;
    final cores = Platform.numberOfProcessors;
    final lowEnd = cores <= 4;

    if (bitrate == null || bitrate <= 0) {
      return lowEnd ? 96 * 1024 * 1024 : 160 * 1024 * 1024;
    }

    final bitrateBytesPerSec = bitrate / 8.0;
    final targetSeconds = bitrate >= 18 * 1000000
        ? 18
        : bitrate >= 10 * 1000000
            ? 22
            : bitrate >= 6 * 1000000
                ? 28
                : 34;
    final estimated = (bitrateBytesPerSec * targetSeconds * 1.8).round();

    final minBuffer = 48 * 1024 * 1024;
    final maxBuffer = lowEnd ? 128 * 1024 * 1024 : 220 * 1024 * 1024;
    return estimated.clamp(minBuffer, maxBuffer);
  }

  SecureHlsAdaptiveConfig _buildAdaptiveConfig() {
    final cores = Platform.numberOfProcessors;
    final lowMemoryMode = cores <= 4;
    return SecureHlsAdaptiveConfig(
      cpuCores: cores,
      bitrateBps: _videoBitrateBps,
      lowMemoryMode: lowMemoryMode,
      maxPrefetchInFlight: lowMemoryMode ? 2 : 4,
    );
  }

  Future<void> _applyAdaptiveMpvTuning(NativePlayer mpv) async {
    final bitrate = _videoBitrateBps ?? 0;
    final highBitrate = bitrate >= 12 * 1000000;
    final ultraBitrate = bitrate >= 18 * 1000000;
    final lowEnd = Platform.numberOfProcessors <= 4;

    final readahead = ultraBitrate
        ? 80
        : highBitrate
            ? 56
            : lowEnd
                ? 28
                : 40;
    final cacheSecs = ultraBitrate
        ? 120
        : highBitrate
            ? 95
            : lowEnd
                ? 40
                : 70;
    final maxBackBytes = lowEnd ? '48MiB' : (highBitrate ? '96MiB' : '72MiB');

    await mpv.setProperty('demuxer-readahead-secs', '$readahead');
    await mpv.setProperty('cache-secs', '$cacheSecs');
    await mpv.setProperty('demuxer-max-back-bytes', maxBackBytes);
  }

  Duration get _displayPosition {
    return _position;
  }

  Duration get _effectiveTotalDuration {
    if (_durationHint > Duration.zero) {
      final diff = (_duration - _durationHint).abs();
      if (_duration > Duration.zero &&
          diff.inMilliseconds < _durationHint.inMilliseconds * 0.05) {
        return _duration > _durationHint ? _duration : _durationHint;
      }
      return _durationHint;
    }
    return _duration;
  }

  void _offerResumePromptIfNeeded() {
    if (!mounted || _resumePromptShown) return;
    final savedRaw = _lastSavedPosition;
    if (savedRaw == null || savedRaw.inSeconds < 10) return;

    _resumePromptShown = true;
    final savedDisplay = savedRaw;

    final total = _effectiveTotalDuration;
    if (total.inSeconds > 0 &&
        savedDisplay >= total - const Duration(seconds: 10)) {
      _clearResumeProgress();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_tr('video.resume.prompt', {
          'position': _formatDuration(savedDisplay),
        })),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: _tr('video.resume.continue'),
          onPressed: () {
            final target = savedDisplay > total ? total : savedDisplay;
            _seekTo(target);
          },
        ),
      ),
    );
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  void _setError(String error, {bool fatal = false}) {
    if (mounted) {
      setState(() {
        _error = error;
        _isLoading = false;
        _lastErrorIsFatal = fatal;
      });
    }
  }

  String _formatError(String error) {
    if (error.contains('HTTP 500') || error.contains('500')) {
      return _tr('video.error.transcoding_failed');
    }
    if (error.contains('HTTP 404') || error.contains('404')) {
      return _tr('video.error.segment_unavailable');
    }
    if (error.contains('HTTP 503') || error.contains('503')) {
      return _tr('video.error.segment_generating');
    }
    if (error.contains('timeout') || error.contains('Timeout')) {
      return _tr('video.error.connection_timeout');
    }
    if (error.contains('SocketException') ||
        error.contains('Connection closed')) {
      return _tr('video.error.network_unstable');
    }
    if (error.contains('SAE') || error.contains('handshake')) {
      return _tr('video.error.handshake_failed');
    }
    return error;
  }

  Future<void> _retry() async {
    await _cleanupHlsSession();
    _cancelSubscriptions();
    await _player?.stop();
    await _player?.dispose();
    _player = null;
    _videoController = null;
    await _proxyServer?.stop();
    _proxyServer = null;
    await _initPlayer();
  }

  Future<void> _cleanupHlsSession() async {
    if (_hlsSessionId != null && _authToken != null) {
      try {
        await _stopSessionById(_hlsSessionId!);
      } catch (e) {
        debugPrint('[SecureHLS] Failed to stop HLS session: $e');
      }
      _hlsSessionId = null;
    }
  }

  Future<void> _stopSessionById(String sessionId) async {
    if (_authToken == null || _authToken!.isEmpty) return;

    await http.post(
      Uri.parse('${widget.baseUrl}/api/v1/secure-hls/$sessionId/stop'),
      headers: {'Authorization': 'Bearer $_authToken'},
    );
    debugPrint('[SecureHLS] HLS session stopped: $sessionId');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _networkTelemetryTimer?.cancel();
    _cancelSubscriptions();
    _player?.dispose();
    _proxyServer?.stop();
    _proxyServer = null;
    unawaited(_saveResumeProgressIfNeeded(_position));
    _cleanupHlsSession();
    _exitFullscreen();
    WakelockPlus.disable();
    super.dispose();
  }

  void _enterFullscreen() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarDividerColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(bottomNavVisibleProvider.notifier).hide();
      }
    });
  }

  bool _isPlaylistReadyForPlayback(String content) {
    if (!content.contains('#EXTM3U')) return false;

    final segmentCount = RegExp(r'segment_\d+\.ts').allMatches(content).length;
    final hasEndList = content.contains('#EXT-X-ENDLIST');

    if (hasEndList) {
      return segmentCount >= 1;
    }
    return segmentCount >= 2;
  }

  void _exitFullscreen() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ));
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    ref.read(bottomNavVisibleProvider.notifier).show();
  }

  void _togglePlayPause() {
    if (_player == null) return;
    if (_isPlaying) {
      _player!.pause();
    } else {
      _player!.play();
    }
  }

  void _seekTo(Duration displayPos) {
    if (_player == null) return;

    final int targetMs = displayPos.inMilliseconds;
    final int minMs = 0;
    final int maxMs = _duration > Duration.zero
        ? _duration.inMilliseconds
        : (_durationHint > Duration.zero
            ? _durationHint.inMilliseconds
            : targetMs);
    final clampedMs = targetMs.clamp(minMs, maxMs);

    final displaySeconds = displayPos.inSeconds;
    final targetSegmentIndex = displaySeconds ~/ 2;
    _proxyServer?.prefetchAroundSegment(targetSegmentIndex);

    _player!.seek(Duration(milliseconds: clampedMs));
  }

  void _seekRelative(int seconds) {
    _seekTo(_displayPosition + Duration(seconds: seconds));
  }

  void _setPlaybackSpeed(double speed) {
    _player?.setRate(speed);
    setState(() => _playbackSpeed = speed);
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  Future<void> _downloadFile() async {
    if (_isDownloading) return;

    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.storage.request();
      if (!status.isGranted && Platform.isAndroid) {
        final ms = await Permission.manageExternalStorage.request();
        if (!ms.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_tr('video.permission.storage_required'))),
            );
          }
          return;
        }
      }
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      Directory? downloadDir;
      if (Platform.isAndroid) {
        downloadDir =
            Directory('/storage/emulated/0/Download/RockZeroDownload');
      } else if (Platform.isIOS) {
        final docDir = await getApplicationDocumentsDirectory();
        downloadDir = Directory('${docDir.path}/RockZeroDownload');
      } else {
        final dlDir = await getDownloadsDirectory();
        if (dlDir != null) {
          downloadDir = Directory('${dlDir.path}/RockZeroDownload');
        }
      }

      if (downloadDir == null) {
        throw Exception(_tr('video.error.download_dir_unavailable'));
      }
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final String downloadUrl;
      if (widget.filePath != null) {
        downloadUrl =
            '${widget.baseUrl}/api/v1/filemanager/download?path=${Uri.encodeComponent(widget.filePath!)}';
      } else {
        downloadUrl =
            '${widget.baseUrl}/api/v1/files/${widget.fileId}/download';
      }

      final file = File('${downloadDir.path}/${widget.fileName}');
      final tempFile = File('${file.path}.part');

      await _saveDownloadTask(
        downloadUrl: downloadUrl,
        outputPath: file.path,
        tempPath: tempFile.path,
        totalBytes: 0,
      );

      await _downloadWithResume(
        downloadUrl: downloadUrl,
        outputFile: file,
        tempFile: tempFile,
      );

      await _clearDownloadTask();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                _tr('video.download.completed', {'path': downloadDir.path})),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      await _persistDownloadTaskSnapshot();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('video.download.failed', {'message': '$e'})),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _downloadWithResume({
    required String downloadUrl,
    required File outputFile,
    required File tempFile,
  }) async {
    for (int attempt = 1; attempt <= _maxDownloadAttempts; attempt++) {
      final exists = await tempFile.exists();
      int received = exists ? await tempFile.length() : 0;

      final request = http.Request('GET', Uri.parse(downloadUrl));
      if (_authToken != null) {
        request.headers['Authorization'] = 'Bearer $_authToken';
      }
      if (received > 0) {
        request.headers['Range'] = 'bytes=$received-';
      }

      final client = http.Client();
      IOSink? sink;
      try {
        final streamed =
            await client.send(request).timeout(const Duration(seconds: 45));

        if (received > 0 && streamed.statusCode == 200) {
          await tempFile.writeAsBytes(<int>[]);
          received = 0;
        }

        if (streamed.statusCode != 200 && streamed.statusCode != 206) {
          throw HttpException(_tr('video.download.http_failed', {
            'status': '${streamed.statusCode}',
          }));
        }

        final totalBytes = streamed.statusCode == 206
            ? received + (streamed.contentLength ?? 0)
            : (streamed.contentLength ?? 0);

        if (mounted) {
          setState(() {
            _downloadReceivedBytes = received;
            _downloadTotalBytes = totalBytes;
          });
        }
        await _saveDownloadTask(
          downloadUrl: downloadUrl,
          outputPath: outputFile.path,
          tempPath: tempFile.path,
          totalBytes: totalBytes,
        );

        sink = tempFile.openWrite(
            mode: received > 0 ? FileMode.append : FileMode.write);
        await for (final chunk in streamed.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (mounted && totalBytes > 0) {
            setState(() {
              _downloadProgress = (received / totalBytes).clamp(0.0, 1.0);
              _downloadReceivedBytes = received;
              _downloadTotalBytes = totalBytes;
            });
          }
          final now = DateTime.now();
          if (now.difference(_lastDownloadPersistAt).inMilliseconds >= 900) {
            _lastDownloadPersistAt = now;
            await _saveDownloadTask(
              downloadUrl: downloadUrl,
              outputPath: outputFile.path,
              tempPath: tempFile.path,
              totalBytes: totalBytes,
            );
          }
        }
        await sink.flush();
        await sink.close();
        sink = null;

        if (await outputFile.exists()) {
          await outputFile.delete();
        }
        await tempFile.rename(outputFile.path);
        await _clearDownloadTask();
        return;
      } on TimeoutException {
        if (attempt >= _maxDownloadAttempts) {
          rethrow;
        }
      } on SocketException {
        if (attempt >= _maxDownloadAttempts) {
          rethrow;
        }
      } finally {
        await sink?.close();
        client.close();
      }

      await Future.delayed(_retryDelay(attempt));
    }
  }

  String _downloadTaskStorageKey() {
    final stableId = widget.filePath ?? widget.fileId ?? widget.fileName;
    return 'secure_hls_download_task:${Uri.encodeComponent(stableId)}';
  }

  Future<void> _saveDownloadTask({
    required String downloadUrl,
    required String outputPath,
    required String tempPath,
    required int totalBytes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final tempFile = File(tempPath);
    final received = await tempFile.exists() ? await tempFile.length() : 0;
    final payload = <String, dynamic>{
      'downloadUrl': downloadUrl,
      'outputPath': outputPath,
      'tempPath': tempPath,
      'totalBytes': totalBytes,
      'receivedBytes': received,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_downloadTaskStorageKey(), jsonEncode(payload));
  }

  Future<void> _persistDownloadTaskSnapshot() async {
    if (!_isDownloading) return;
    final info = await _readDownloadTask();
    if (info == null) return;
    final downloadUrl = info['downloadUrl'] as String?;
    final outputPath = info['outputPath'] as String?;
    final tempPath = info['tempPath'] as String?;
    if (downloadUrl == null || outputPath == null || tempPath == null) return;
    await _saveDownloadTask(
      downloadUrl: downloadUrl,
      outputPath: outputPath,
      tempPath: tempPath,
      totalBytes: _downloadTotalBytes,
    );
  }

  Future<Map<String, dynamic>?> _readDownloadTask() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_downloadTaskStorageKey());
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      await prefs.remove(_downloadTaskStorageKey());
    }
    return null;
  }

  Future<void> _clearDownloadTask() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_downloadTaskStorageKey());
  }

  Future<void> _tryRecoverPendingDownloadTask() async {
    if (!mounted || _isDownloading) return;
    final info = await _readDownloadTask();
    if (info == null) return;

    final downloadUrl = info['downloadUrl'] as String?;
    final outputPath = info['outputPath'] as String?;
    final tempPath = info['tempPath'] as String?;
    final totalBytes = (info['totalBytes'] as num?)?.toInt() ?? 0;
    if (downloadUrl == null || outputPath == null || tempPath == null) {
      await _clearDownloadTask();
      return;
    }

    final tempFile = File(tempPath);
    final outputFile = File(outputPath);
    if (!await tempFile.exists()) {
      await _clearDownloadTask();
      return;
    }
    if (await outputFile.exists()) {
      await _clearDownloadTask();
      return;
    }

    final received = await tempFile.length();
    if (!mounted) return;
    setState(() {
      _isDownloading = true;
      _downloadReceivedBytes = received;
      _downloadTotalBytes = totalBytes;
      if (totalBytes > 0) {
        _downloadProgress = (received / totalBytes).clamp(0.0, 1.0);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_tr('video.download.recovered_task'))),
    );

    try {
      await _downloadWithResume(
        downloadUrl: downloadUrl,
        outputFile: outputFile,
        tempFile: tempFile,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr('video.download.recovered_done')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(_tr('video.download.recovered_failed', {'message': '$e'})),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _exitFullscreen();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.black,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarDividerColor: Colors.black,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (_videoController != null && !_isLoading && _error == null)
                GestureDetector(
                  onTap: _toggleControls,
                  onDoubleTapDown: (details) {
                    final screenWidth = MediaQuery.of(context).size.width;
                    if (details.globalPosition.dx < screenWidth / 3) {
                      _seekRelative(-10);
                    } else if (details.globalPosition.dx >
                        screenWidth * 2 / 3) {
                      _seekRelative(10);
                    } else {
                      _togglePlayPause();
                    }
                  },
                  child: Video(
                    controller: _videoController!,
                    fill: Colors.black,
                    controls: NoVideoControls,
                  ),
                ),
              if (_isBuffering && !_isLoading)
                const Center(
                  child: RepaintBoundary(
                    child: MD3BufferingIndicator(
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: (!_isLoading && _error == null && _showControls)
                    ? _buildControlsOverlay()
                    : const SizedBox.shrink(key: ValueKey('controls_hidden')),
              ),
              if (_isLoading) _buildLoading(),
              if (_error != null && !_isLoading) _buildError(),
              if (_isDownloading) _buildDownloadProgress(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return KeyedSubtree(
      key: const ValueKey('controls_visible'),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black54,
              Colors.transparent,
              Colors.transparent,
              Colors.black54,
            ],
            stops: [0.0, 0.15, 0.85, 1.0],
          ),
        ),
        child: Column(
          children: [
            _buildTopBar(),
            _buildSecurityRuntimeStrip(),
            const Spacer(),
            _buildCenterControls(),
            const Spacer(),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () {
                _exitFullscreen();
                Navigator.pop(context);
              },
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                widget.fileName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showEncryptionDetails(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 14,
                      color: Colors.greenAccent,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'SAE+AES256',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.white),
              onPressed: _downloadFile,
              tooltip: _tr('video.action.download_original'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityRuntimeStrip() {
    final runtime = _proxyServer?.runtimeSnapshot;
    if (runtime == null && !_isRecoveringSession) {
      return const SizedBox(height: 6);
    }

    final fallbackActive = runtime?.fallbackActive == true;
    final zkpActive = runtime?.zkpActive == true;
    final retries = runtime?.segmentRetries ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            _buildRuntimeChip(
              label: _isRecoveringSession
                  ? _tr('video.runtime.rebuilding_session')
                  : (zkpActive
                      ? _tr('video.runtime.zkp_path')
                      : _tr('video.runtime.session_path')),
              color: _isRecoveringSession
                  ? Colors.amberAccent
                  : (zkpActive ? Colors.greenAccent : Colors.lightBlueAccent),
              icon: _isRecoveringSession
                  ? Icons.sync_rounded
                  : Icons.verified_user_rounded,
            ),
            const SizedBox(width: 8),
            _buildRuntimeChip(
              label: fallbackActive
                  ? _tr('video.runtime.fallback_active')
                  : _tr('video.runtime.direct_verified'),
              color: fallbackActive ? Colors.orangeAccent : Colors.cyanAccent,
              icon: fallbackActive
                  ? Icons.route_rounded
                  : Icons.check_circle_outline_rounded,
            ),
            const SizedBox(width: 8),
            _buildRuntimeChip(
              label: _tr('video.runtime.retries', {'count': '$retries'}),
              color: retries > 0 ? Colors.orangeAccent : Colors.white70,
              icon: Icons.refresh_rounded,
            ),
            const Spacer(),
            Text(
              _tr('video.runtime.proof_stats', {
                'requests': '${runtime?.proofGenerateRequests ?? 0}',
                'failures': '${runtime?.proofGenerateFailures ?? 0}',
              }),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuntimeChip({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.replay_10_rounded,
              color: Colors.white, size: 36),
          onPressed: () => _seekRelative(-10),
          splashRadius: 28,
        ),
        const SizedBox(width: 32),
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _togglePlayPause,
            splashColor: Colors.white24,
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),
          ),
        ),
        const SizedBox(width: 32),
        IconButton(
          icon: const Icon(Icons.forward_10_rounded,
              color: Colors.white, size: 36),
          onPressed: () => _seekRelative(10),
          splashRadius: 28,
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final totalMs = _effectiveTotalDuration.inMilliseconds.toDouble();
    final displayPosition = _isDraggingProgress && _dragPreviewPosition != null
        ? _dragPreviewPosition!
        : _displayPosition;
    final posMs = displayPosition.inMilliseconds.toDouble();
    final rawBufMs = _bufferedPosition.inMilliseconds.toDouble();
    final bufMs = rawBufMs.clamp(0.0, totalMs > 0 ? totalMs : rawBufMs);
    final safeTotalMs = totalMs <= 0 ? posMs : totalMs;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildNetworkQualityIndicator(),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    _formatDuration(displayPosition),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDuration(_effectiveTotalDuration),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                  elevation: 2,
                  pressedElevation: 4,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: colorScheme.primary,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                thumbColor: colorScheme.primary,
                overlayColor: colorScheme.primary.withValues(alpha: 0.12),
                secondaryActiveTrackColor: Colors.white.withValues(alpha: 0.3),
              ),
              child: Slider(
                value: safeTotalMs > 0
                    ? (posMs / safeTotalMs).clamp(0.0, 1.0)
                    : 0.0,
                secondaryTrackValue: safeTotalMs > 0
                    ? (bufMs / safeTotalMs).clamp(0.0, 1.0)
                    : 0.0,
                onChanged: safeTotalMs <= 0
                    ? null
                    : (value) {
                        final newPos = Duration(
                          milliseconds: (value * safeTotalMs).round(),
                        );
                        setState(() {
                          _isDraggingProgress = true;
                          _dragPreviewPosition = newPos;
                        });
                      },
                onChangeStart: (_) {
                  _hideControlsTimer?.cancel();
                  setState(() {
                    _isDraggingProgress = true;
                    _dragPreviewPosition = displayPosition;
                  });
                },
                onChangeEnd: (value) {
                  final target = _dragPreviewPosition ??
                      Duration(milliseconds: (value * safeTotalMs).round());
                  setState(() {
                    _isDraggingProgress = false;
                    _dragPreviewPosition = null;
                  });
                  _seekTo(target);
                  _startHideControlsTimer();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Spacer(),
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _showSpeedPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          '${_playbackSpeed}x',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkQualityIndicator() {
    final color = _networkQualityColor();
    final samples = _networkScoreSamples.toList(growable: false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.network_check_rounded, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  _tr('video.network.summary', {
                    'quality': _networkQualityLabel(),
                    'seconds': '$_latestBufferAheadSec',
                  }),
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  _latestRetryDelta > 0
                      ? _tr('video.network.retry_up', {
                          'count': '$_latestRetryDelta',
                        })
                      : _tr('video.network.retry_steady'),
                  style: TextStyle(
                    color: _latestRetryDelta > 0
                        ? Colors.orangeAccent
                        : Colors.white70,
                    fontSize: 10,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            SizedBox(
              height: 18,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(22, (index) {
                  final value = index < samples.length ? samples[index] : 0.0;
                  final barColor =
                      Color.lerp(Colors.redAccent, Colors.greenAccent, value)!;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0.7),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          height: max(2.0, value * 16),
                          decoration: BoxDecoration(
                            color: barColor.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEncryptionDetails() {
    final runtime = _proxyServer?.runtimeSnapshot;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _EncryptionPipelineSheet(
        sessionId: _hlsSessionId,
        runtime: runtime,
      ),
    );
  }

  void _showSpeedPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                _tr('video.control.playback_speed'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ..._speedOptions.map((speed) => ListTile(
                  title: Text(
                    '${speed}x',
                    style: TextStyle(
                      color: _playbackSpeed == speed
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white,
                      fontWeight: _playbackSpeed == speed
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: _playbackSpeed == speed
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    _setPlaybackSpeed(speed);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return SecureConnectionIndicator(
      statusText: _loadingStatus,
      detailText: _tr('video.loading.detail'),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            Text(_error!,
                style: const TextStyle(color: Colors.white54),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: Text(_tr('video.action.retry')),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _exitFullscreen();
                Navigator.pop(context);
              },
              child: Text(_tr('video.action.back')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadProgress() {
    final bytesText = _downloadTotalBytes > 0
        ? '${(_downloadReceivedBytes / (1024 * 1024)).toStringAsFixed(1)}MB / ${(_downloadTotalBytes / (1024 * 1024)).toStringAsFixed(1)}MB'
        : '${(_downloadReceivedBytes / (1024 * 1024)).toStringAsFixed(1)}MB';

    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.black87, borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.download, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(_tr('video.download.progress'),
                        style: const TextStyle(color: Colors.white))),
                Text('${(_downloadProgress * 100).toInt()}%',
                    style: const TextStyle(color: Colors.white)),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                bytesText,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: _downloadProgress, backgroundColor: Colors.white24),
          ],
        ),
      ),
    );
  }
}

class _ProtocolNode {
  final IconData icon;
  final String title;
  final String subtitle;
  final String detail;
  final Color color;

  const _ProtocolNode({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.color,
  });
}

class _EncryptionPipelineSheet extends StatefulWidget {
  final String? sessionId;
  final SecureHlsRuntimeSnapshot? runtime;

  const _EncryptionPipelineSheet({
    this.sessionId,
    this.runtime,
  });

  @override
  State<_EncryptionPipelineSheet> createState() =>
      _EncryptionPipelineSheetState();
}

class _EncryptionPipelineSheetState extends State<_EncryptionPipelineSheet>
    with TickerProviderStateMixin {
  late final AnimationController _masterController;
  late final AnimationController _shieldPulseController;
  late final AnimationController _particleController;
  late final AnimationController _glowController;

  late final List<_ProtocolNode> _nodes;

  final List<Animation<double>> _slideAnimations = [];
  final List<Animation<double>> _fadeAnimations = [];
  final List<Animation<double>> _connectorAnimations = [];
  final List<Animation<double>> _activateAnimations = [];

  AppLocalizations get _strings =>
      AppLocalizations(WidgetsBinding.instance.platformDispatcher.locale);
  String _tr(String key, [Map<String, String> args = const {}]) =>
      _strings.tr(key, args);

  @override
  void initState() {
    super.initState();

    _nodes = _buildNodes();
    final totalMs = _nodes.length * 350 + 400;
    _masterController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );

    for (int i = 0; i < _nodes.length; i++) {
      final startFraction = (i * 350) / totalMs;
      final endFraction = ((i * 350) + 400) / totalMs;
      final start = startFraction.clamp(0.0, 1.0);
      final end = endFraction.clamp(0.0, 1.0);

      _slideAnimations.add(
        Tween<double>(begin: 40.0, end: 0.0).animate(
          CurvedAnimation(
            parent: _masterController,
            curve: Interval(start, end, curve: Curves.easeOutExpo),
          ),
        ),
      );
      _fadeAnimations.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _masterController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        ),
      );

      final activateStart = (end + 0.02).clamp(0.0, 1.0);
      final activateEnd = (activateStart + 0.15).clamp(0.0, 1.0);
      _activateAnimations.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _masterController,
            curve: Interval(activateStart, activateEnd, curve: Curves.easeOut),
          ),
        ),
      );

      if (i > 0) {
        final connStart = ((i * 350) - 100) / totalMs;
        final connEnd = ((i * 350) + 100) / totalMs;
        _connectorAnimations.add(
          Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(
              parent: _masterController,
              curve: Interval(
                connStart.clamp(0.0, 1.0),
                connEnd.clamp(0.0, 1.0),
                curve: Curves.easeInOut,
              ),
            ),
          ),
        );
      }
    }

    _shieldPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);

    _masterController.forward();
  }

  List<_ProtocolNode> _buildNodes() {
    final runtime = widget.runtime;
    final zkpPath = runtime?.zkpActive == true;
    final fallbackPath = runtime?.fallbackActive == true;
    return [
      _ProtocolNode(
        icon: Icons.vpn_key_rounded,
        title: _tr('video.encryption.node.key_exchange.title'),
        subtitle: 'WPA3-SAE (Simultaneous Authentication of Equals)',
        detail: _tr('video.encryption.node.key_exchange.detail'),
        color: Colors.orangeAccent,
      ),
      _ProtocolNode(
        icon: Icons.lock_rounded,
        title: _tr('video.encryption.node.at_rest.title'),
        subtitle: 'AES-256-GCM (Galois/Counter Mode)',
        detail: _tr('video.encryption.node.at_rest.detail'),
        color: Colors.cyanAccent,
      ),
      _ProtocolNode(
        icon: Icons.security_rounded,
        title: _tr('video.encryption.node.segment_auth.title'),
        subtitle: zkpPath
            ? 'Bulletproofs ZKP (POST)'
            : 'Session Token + Encrypted GET Fallback',
        detail: fallbackPath
            ? _tr('video.encryption.node.segment_auth.detail_fallback')
            : _tr('video.encryption.node.segment_auth.detail_verified'),
        color: Colors.purpleAccent,
      ),
      _ProtocolNode(
        icon: Icons.fingerprint_rounded,
        title: _tr('video.encryption.node.runtime.title'),
        subtitle: 'Blake3 Cryptographic Hash',
        detail: _tr('video.encryption.node.runtime.detail', {
          'requests': '${runtime?.proofGenerateRequests ?? 0}',
          'failures': '${runtime?.proofGenerateFailures ?? 0}',
          'retries': '${runtime?.segmentRetries ?? 0}',
        }),
        color: Colors.tealAccent,
      ),
    ];
  }

  @override
  void dispose() {
    _masterController.dispose();
    _shieldPulseController.dispose();
    _particleController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _buildAnimatedHeader(),
              const SizedBox(height: 6),
              _buildSubtitleRow(),
              const SizedBox(height: 24),
              ..._buildPipelineNodes(),
              if (widget.sessionId != null) ...[
                const SizedBox(height: 20),
                _buildSessionInfo(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedHeader() {
    const themeColor = Colors.greenAccent;
    return AnimatedBuilder(
      animation: _shieldPulseController,
      builder: (context, child) {
        final pulse = _shieldPulseController.value;
        return Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: themeColor.withValues(alpha: 0.3 + pulse * 0.3),
                    blurRadius: 12 + pulse * 8,
                    spreadRadius: pulse * 4,
                  ),
                ],
              ),
              child: Icon(
                Icons.shield_rounded,
                color: themeColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _tr('video.encryption.title'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSubtitleRow() {
    final runtime = widget.runtime;
    return Text(
      runtime?.fallbackActive == true
          ? _tr('video.encryption.subtitle_fallback')
          : _tr('video.encryption.subtitle_verified'),
      style: TextStyle(
        color: Colors.greenAccent,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  List<Widget> _buildPipelineNodes() {
    final List<Widget> widgets = [];
    for (int i = 0; i < _nodes.length; i++) {
      if (i > 0) {
        widgets.add(_buildAnimatedConnector(i - 1));
      }
      widgets.add(_buildAnimatedNode(i));
    }
    return widgets;
  }

  Widget _buildAnimatedConnector(int connectorIndex) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _connectorAnimations[connectorIndex],
        _particleController,
      ]),
      builder: (context, _) {
        final progress = _connectorAnimations[connectorIndex].value;
        if (progress <= 0) return const SizedBox(height: 8);

        return SizedBox(
          height: 32,
          child: CustomPaint(
            size: const Size(double.infinity, 32),
            painter: _PipelineConnectorPainter(
              progress: progress,
              particlePhase: _particleController.value,
              fromColor: _nodes[connectorIndex].color,
              toColor: _nodes[connectorIndex + 1].color,
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedNode(int index) {
    final node = _nodes[index];
    return AnimatedBuilder(
      animation: _masterController,
      builder: (context, _) {
        final slide = _slideAnimations[index].value;
        final fade = _fadeAnimations[index].value;
        final activate = _activateAnimations[index].value;

        if (fade <= 0) return const SizedBox.shrink();

        return Transform.translate(
          offset: Offset(slide, 0),
          child: Opacity(
            opacity: fade,
            child: _NodeCard(
              node: node,
              activateProgress: activate,
              glowAnimation: _glowController,
              particleAnimation: _particleController,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSessionInfo() {
    final sessionId = widget.sessionId!;
    return AnimatedBuilder(
      animation: _masterController,
      builder: (context, _) {
        final showProgress = _masterController.value > 0.85
            ? ((_masterController.value - 0.85) / 0.15).clamp(0.0, 1.0)
            : 0.0;
        if (showProgress <= 0) return const SizedBox.shrink();

        return Opacity(
          opacity: showProgress,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - showProgress)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: Colors.white54, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        _tr('video.encryption.session_info'),
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tr('video.encryption.session_label', {
                      'sessionId': sessionId.length > 20
                          ? '${sessionId.substring(0, 20)}...'
                          : sessionId,
                    }),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tr('video.encryption.transport_mode', {
                      'mode': widget.runtime?.fallbackActive == true
                          ? _tr('video.encryption.transport_mode_fallback')
                          : _tr('video.encryption.transport_mode_verified'),
                    }),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NodeCard extends StatelessWidget {
  final _ProtocolNode node;
  final double activateProgress;
  final AnimationController glowAnimation;
  final AnimationController particleAnimation;

  const _NodeCard({
    required this.node,
    required this.activateProgress,
    required this.glowAnimation,
    required this.particleAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([glowAnimation, particleAnimation]),
      builder: (context, _) {
        final glow = glowAnimation.value;
        final borderAlpha = 0.15 + activateProgress * 0.25 + glow * 0.1;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: node.color.withValues(alpha: 0.06 + activateProgress * 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: node.color.withValues(alpha: borderAlpha.clamp(0.0, 1.0)),
              width: 1.2,
            ),
            boxShadow: activateProgress > 0.5
                ? [
                    BoxShadow(
                      color: node.color.withValues(alpha: 0.08 + glow * 0.06),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIconWithGlow(glow),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          node.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadge(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      node.subtitle,
                      style: TextStyle(
                        color: node.color.withValues(alpha: 0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      node.detail,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIconWithGlow(double glow) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: node.color.withValues(alpha: 0.12 + activateProgress * 0.08),
        borderRadius: BorderRadius.circular(10),
        boxShadow: activateProgress > 0.3
            ? [
                BoxShadow(
                  color: node.color.withValues(alpha: 0.2 + glow * 0.15),
                  blurRadius: 10 + glow * 6,
                  spreadRadius: glow * 2,
                ),
              ]
            : null,
      ),
      child: Icon(node.icon, color: node.color, size: 22),
    );
  }

  Widget _buildStatusBadge() {
    return AnimatedOpacity(
      opacity: activateProgress,
      duration: Duration.zero,
      child: Transform.scale(
        scale: 0.8 + activateProgress * 0.2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: Colors.greenAccent.withValues(alpha: 0.3),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded,
                  color: Colors.greenAccent, size: 10),
              const SizedBox(width: 3),
              Text(
                AppLocalizations(
                        WidgetsBinding.instance.platformDispatcher.locale)
                    .tr('video.status.enabled'),
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PipelineConnectorPainter extends CustomPainter {
  final double progress;
  final double particlePhase;
  final Color fromColor;
  final Color toColor;

  _PipelineConnectorPainter({
    required this.progress,
    required this.particlePhase,
    required this.fromColor,
    required this.toColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final top = 0.0;
    final bottom = size.height * progress;

    final linePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          fromColor.withValues(alpha: 0.6),
          toColor.withValues(alpha: 0.6),
        ],
      ).createShader(Rect.fromLTRB(centerX - 1, top, centerX + 1, bottom))
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(centerX, top), Offset(centerX, bottom), linePaint);

    final glowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          fromColor.withValues(alpha: 0.08),
          toColor.withValues(alpha: 0.08),
        ],
      ).createShader(Rect.fromLTRB(centerX - 6, top, centerX + 6, bottom))
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawLine(Offset(centerX, top), Offset(centerX, bottom), glowPaint);

    if (progress > 0.3) {
      for (int i = 0; i < 5; i++) {
        final phase = (particlePhase + i / 5.0) % 1.0;

        final easedPhase = 0.5 - 0.5 * cos(phase * pi);
        final y = top + (bottom - top) * easedPhase;

        final opacity = sin(phase * pi);
        final blendColor = Color.lerp(fromColor, toColor, phase)!;

        final radius = 2.0 + opacity * 1.5;
        final particlePaint = Paint()
          ..color = blendColor.withValues(alpha: opacity * 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

        canvas.drawCircle(Offset(centerX, y), radius, particlePaint);
      }
    }

    if (progress > 0.9) {
      final arrowPaint = Paint()
        ..color = toColor.withValues(alpha: 0.7)
        ..style = PaintingStyle.fill;

      final arrowPath = Path()
        ..moveTo(centerX - 5, bottom - 6)
        ..lineTo(centerX + 5, bottom - 6)
        ..lineTo(centerX, bottom)
        ..close();

      canvas.drawPath(arrowPath, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PipelineConnectorPainter old) =>
      old.progress != progress || old.particlePhase != particlePhase;
}
