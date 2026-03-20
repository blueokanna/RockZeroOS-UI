import 'dart:async';
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

class _SecureHlsVideoPlayerState extends ConsumerState<SecureHlsVideoPlayer> {
  Player? _player;
  VideoController? _videoController;

  bool _isLoading = true;
  String? _error;
  String _loadingStatus = '正在建立安全连接...';
  String? _authToken;
  String? _hlsSessionId;
  String? _userId;
  String? _userSaeSecret;
  bool _isDownloading = false;
  double _downloadProgress = 0;

  // 安全代理：拦截 libmpv 请求，解密 AES-256-GCM 加密的视频段
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

  // === PTS 时间戳偏移修正 ===
  // 某些视频文件（尤其是 MKV 容器）内部 PTS 时间戳不从 0 开始，
  // 导致 stream-copy 生成的 HLS 分片继承了错误的起始时间。
  // 例如：视频实际时长 1:30，但 PTS 从 26:28:10 开始，导致播放器显示 26:28:10 ~ 26:29:40。
  Duration _startOffset = Duration.zero;
  bool _offsetDetected = false;
  bool _initialSeekDone = false;
  DateTime? _playbackOpenAt;

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

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
    WakelockPlus.enable();
    _initPlayer();
    _startHideControlsTimer();
  }

  Future<void> _initPlayer() async {
    try {
      // ★ 播放视频前停止正在播放的音频，避免音视频同时播放
      ref.read(audioPlayerServiceProvider.notifier).stop();

      setState(() {
        _isLoading = true;
        _error = null;
        _loadingStatus = '正在获取凭据...';
      });

      // 获取用户凭据
      const storage = FlutterSecureStorage();
      _authToken = await storage.read(key: 'access_token');
      _userId = await storage.read(key: 'user_id');
      _userSaeSecret = await storage.read(key: 'user_password_hash');

      if (_authToken == null || _authToken!.isEmpty) {
        _setError('未登录，请先登录');
        return;
      }

      if (_userId == null || _userSaeSecret == null) {
        _setError('无法获取用户凭据，请重新登录');
        return;
      }

      await _loadResumeProgress();
      await _fetchDurationHint();

      // 通过 SAE 安全通道 + direct 模式传输（不需要 ZKP 证明）
      await _tryHlsStreaming();
    } catch (e, stack) {
      debugPrint('[VideoPlayer] Error: $e');
      debugPrint('[VideoPlayer] Stack: $stack');
      _setError('播放失败: ${_formatError(e.toString())}');
    }
  }

  Future<void> _tryHlsStreaming() async {
    setState(() {
      _loadingStatus = '正在执行 SAE 安全握手...';
    });

    debugPrint('[VideoPlayer] Starting SAE handshake for secure HLS...');

    final handshakeService = SaeHandshakeService(
      baseUrl: widget.baseUrl,
      jwtToken: _authToken!,
    );

    final filePath = widget.filePath;
    final fileId = widget.fileId;

    // ── Step 1: SAE 握手 + 会话创建（加密模式，所有段 AES-256-GCM 加密传输）───
    late final String sessionId;
    late final Uint8List pmk;

    try {
      final result = await handshakeService.performHandshake(
        filePath: filePath,
        fileId: fileId,
        password: _userSaeSecret!,
        userId: _userId!,
        directMode: false, // ★ 禁用 direct 模式，强制加密传输
      );

      sessionId = result.$1;
      pmk = result.$2;
      _hlsSessionId = sessionId;
    } on SaeHandshakeException catch (e) {
      debugPrint('[VideoPlayer] SAE/session stage failed: $e');
      if (e.stage == SaeStage.createSession) {
        if (e.statusCode == 412) {
          _setError(
            '会话创建被拒绝（外部缓存不可用）。\n'
            '请检查 HLS_CACHE_PATH 是否指向已挂载外部存储，或关闭 ROCKZERO_STRICT_EXTERNAL_HLS_CACHE。\n'
            '后端信息: ${_formatError(e.message)}',
          );
        } else {
          _setError('会话创建失败(${e.statusCode}): ${_formatError(e.message)}');
        }
      } else {
        _setError(
            'SAE 安全握手失败(${e.stage.name}/${e.statusCode}): ${_formatError(e.message)}');
      }
      return;
    } catch (e) {
      debugPrint('[VideoPlayer] SAE handshake failed: $e');
      _setError('SAE 安全握手失败: ${_formatError(e.toString())}');
      return;
    }

    debugPrint('[VideoPlayer] HLS session (encrypted mode): $sessionId');

    // ── Step 2: 启动本地安全代理（解密 AES-256-GCM 加密的视频段）────
    //
    // 安全架构：
    //   - 服务端所有视频段均使用 AES-256-GCM 加密传输（不允许明文）
    //   - 本地代理拦截 libmpv 的 HTTP 请求
    //   - 代理从服务端获取加密数据，使用 PMK 派生密钥本地解密
    //   - 解密后的明文仅存在于设备内存中，不落盘
    //   - libmpv 从 127.0.0.1 获取解密后的明文视频段

    if (!mounted) return;
    setState(() => _loadingStatus = '正在启动安全代理...');

    late final String proxyPlaylistUrl;

    try {
      // 创建会话重建回调（当 session 过期时自动重新握手）
      Future<(String, Uint8List)> rebuildSession() async {
        debugPrint('[VideoPlayer] Rebuilding SAE session...');
        final newResult = await handshakeService.performHandshake(
          filePath: filePath,
          fileId: fileId,
          password: _userSaeSecret!,
          userId: _userId!,
          directMode: false,
        );
        _hlsSessionId = newResult.$1;
        return newResult;
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
      _setError('安全代理启动失败: ${_formatError(e.toString())}');
      return;
    }

    // ── Step 3: 等待首个分片就绪（通过代理检查播放列表）────────
    if (!mounted) return;
    setState(() => _loadingStatus = '正在等待视频分片...');

    bool playlistReady = false;
    for (int i = 0; i < 90; i++) {
      if (!mounted) return;

      try {
        final checkResponse = await http
            .get(Uri.parse(proxyPlaylistUrl))
            .timeout(const Duration(seconds: 5));

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
          _loadingStatus = '正在等待视频分片... (${i + 1}s)';
        });
      }
    }

    if (!playlistReady) {
      _setError('播放列表生成超时（已等待 90 秒），请检查视频编码格式或服务器 ffmpeg 配置');
      return;
    }

    if (!mounted) return;

    setState(() => _loadingStatus = '正在初始化播放器...');

    // ── Step 4: 创建 media_kit 播放器 ────────────────────────
    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: _calculateAdaptiveBufferBytes(),
      ),
    );

    // libmpv 专用属性：优化 HLS 流播放
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
      // 强制将流起始时间重定向为 0，修复 PTS 偏移导致的时间显示错误
      await mpv.setProperty('rebase-start-time', 'yes');
      // 生成缺失 PTS 并丢弃损坏帧，减少音画漂移与卡顿。
      await mpv.setProperty(
        'demuxer-lavf-o',
        'fflags=+genpts+discardcorrupt',
      );
      // ★ 强制允许在“直播”HLS 流中进行 seek 操作
      await mpv.setProperty('force-seekable', 'yes');

      // 结合设备性能和码率动态调整缓冲与回读窗口。
      await _applyAdaptiveMpvTuning(mpv);
    }

    _videoController = VideoController(_player!);
    _setupPlayerListeners();

    // 监听播放错误
    final errorCompleter = Completer<String?>();
    StreamSubscription<String>? errorSub;
    errorSub = _player!.stream.error.listen((error) {
      if (error.isNotEmpty && !errorCompleter.isCompleted) {
        errorCompleter.complete(error);
        errorSub?.cancel();
      }
    });

    // 监听成功开始播放
    final playingCompleter = Completer<bool>();
    StreamSubscription<bool>? playingSub;
    playingSub = _player!.stream.playing.listen((playing) {
      if (playing && !playingCompleter.isCompleted) {
        playingCompleter.complete(true);
        playingSub?.cancel();
      }
    });

    // 监听时长获取（表示媒体元数据已解析）
    final durationCompleter = Completer<bool>();
    StreamSubscription<Duration>? durationSub;
    durationSub = _player!.stream.duration.listen((dur) {
      if (dur.inMilliseconds > 0 && !durationCompleter.isCompleted) {
        durationCompleter.complete(true);
        durationSub?.cancel();
      }
    });

    // ── 使用本地安全代理 URL（加密传输 + 本地解密）───────────
    //
    // media_kit → GET http://127.0.0.1:{port}/playlist.m3u8  (本地代理)
    //           → GET http://127.0.0.1:{port}/segment_N.ts   (本地代理)
    //
    // 代理内部流程：
    //   代理 → GET /api/v1/secure-hls/{session_id}/segment_N.ts (服务端，加密数据)
    //        → AES-256-GCM 解密（使用 PMK 派生密钥）
    //        → 返回明文 MPEG-TS 给 libmpv
    //
    // 安全保障：
    //   - 网络传输全程 AES-256-GCM 加密
    //   - SAE 握手确保会话密钥安全交换
    //   - Session ID 不可猜测（128 位随机）
    //   - 明文数据仅存在于设备内存中
    //   - 磁盘缓存段使用 AES-256-GCM 静态加密
    await _player!.open(
      Media(proxyPlaylistUrl),
      play: true,
    );
    _playbackOpenAt = DateTime.now();

    // 不再在 open 后立即 seek — 等待播放确认后再处理

    // 等待播放信号、时长信号或错误，超时 25 秒
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
      // ★ 关键修复：渐进式 HLS 可能从最新分片开始，强制 seek 到实际内容起始点
      _forceSeekToStartIfNeeded();
      _offerResumePromptIfNeeded();
      return;
    }

    if (result == 'timeout') {
      // 超时但无错误 — 仍然显示播放器（可能在缓冲大文件）
      debugPrint(
          '[VideoPlayer] HLS playback timeout but no error — showing player');
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _forceSeekToStartIfNeeded();
      _offerResumePromptIfNeeded();
      return;
    }

    // 播放器报错
    debugPrint('[VideoPlayer] HLS playback error: $result');
    _setError('播放失败: ${_formatError(result.toString())}');
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
      // 尝试检测 PTS 偏移（基于位置）
      _detectTimestampOffsetFromPosition(position);
      // 首次检测到偏移后，seek 到实际内容起始点
      _performInitialSeekIfNeeded();
      _saveResumeProgressIfNeeded(position);
    }));

    _subscriptions.add(_player!.stream.duration.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
          // ⚠️ 不要将播放器报告的时长覆盖 _durationHint（服务端真实时长）
          // 否则 PTS 偏移检测会因 diff=0 而失败
          // _durationHint 仅来自服务端 media info API
        });
        // 尝试检测 PTS 偏移（基于时长对比）
        _detectTimestampOffsetFromDuration();
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

  /// PTS 偏移检测（基于时长对比）
  ///
  /// 如果播放器报告的时长远超服务器告知的真实时长，说明存在 PTS 偏移。
  /// 例如：服务器说视频时长 01:30，但播放器报告 26:29:40。
  /// 偏移量 = 26:29:40 - 01:30 = 26:28:10。
  void _detectTimestampOffsetFromDuration() {
    if (_offsetDetected) return;
    if (_durationHint <= Duration.zero || _duration <= Duration.zero) return;

    final diff = _duration - _durationHint;
    // 如果差异超过 30 秒，且播放器时长显著大于真实时长，则判定为 PTS 偏移
    if (diff.inSeconds > 30 &&
        _duration.inSeconds > _durationHint.inSeconds * 2) {
      setState(() {
        _startOffset = diff;
        _offsetDetected = true;
      });
      debugPrint(
        '[SecureHLS] ✅ PTS offset detected via duration comparison: '
        'offset=$_startOffset (player_duration=$_duration, hint=$_durationHint)',
      );
    }
  }

  /// PTS 偏移检测（基于位置）
  ///
  /// 备用检测方法：当服务器未返回时长提示时，
  /// 用第一个报告的位置判断偏移。
  void _detectTimestampOffsetFromPosition(Duration position) {
    if (_offsetDetected) return;
    if (_durationHint > Duration.zero) return; // 已有时长提示，使用时长对比法
    if (_duration <= Duration.zero) return;

    // 如果第一个报告的位置 > 60秒，很可能是 PTS 偏移
    if (position.inSeconds > 60) {
      setState(() {
        _startOffset = position;
        _offsetDetected = true;
      });
      debugPrint(
        '[SecureHLS] ✅ PTS offset detected via first position: '
        'offset=$_startOffset (first_position=$position)',
      );
    }
  }

  /// 检测到偏移后，seek 到实际内容的起始点
  void _performInitialSeekIfNeeded() {
    if (!_offsetDetected || _initialSeekDone) return;
    if (_startOffset <= Duration.zero) return;

    // 避免误判导致回跳：仅对明显异常的大偏移执行一次纠正。
    if (_startOffset.inSeconds < 300) {
      return;
    }

    _initialSeekDone = true;
    debugPrint(
        '[SecureHLS] Performing initial seek to content start: $_startOffset');
    _player?.seek(_startOffset);
  }

  /// ★ 强制 seek 到开头 —— 修复渐进式 HLS（无 #EXT-X-ENDLIST）导致
  /// 播放器从最新分片（live edge）开始播放，进度条一开始就满的问题。
  ///
  /// 策略：
  /// 1. 等一小段时间让播放器报告实际 position 和 duration
  /// 2. 如果 displayPosition 占 totalDuration 比例 > 80%，且不是短视频已近结尾，
  ///    认为播放器从 live edge 开始了，强制 seek 回开头
  /// 3. 如果有 PTS 偏移已检测到，使用 _startOffset 作为起始点
  void _forceSeekToStartIfNeeded() {
    if (_player == null) return;

    // 延迟 800ms，等播放器报告第一批 position/duration
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted || _player == null) return;

      final openedAt = _playbackOpenAt;
      if (openedAt == null ||
          DateTime.now().difference(openedAt).inSeconds > 4) {
        return;
      }

      final total = _effectiveTotalDuration;
      final displayPos = _displayPosition;

      debugPrint(
        '[SecureHLS] forceSeekToStart check: '
        'displayPos=$displayPos, total=$total, '
        'rawPos=$_position, rawDur=$_duration, '
        'offset=$_startOffset, offsetDetected=$_offsetDetected',
      );

      // 条件：总时长 > 30秒（不是极短视频），且当前显示位置已超过总时长 70%
      if (total.inSeconds > 30 &&
          displayPos.inSeconds > 0 &&
          displayPos.inMilliseconds > total.inMilliseconds * 0.9 &&
          displayPos.inSeconds > 120) {
        debugPrint(
          '[SecureHLS] ★ Detected live-edge start! '
          'displayPos=$displayPos is >70% of total=$total. '
          'Seeking to beginning...',
        );

        if (_offsetDetected && _startOffset > Duration.zero) {
          // 有 PTS 偏移：seek 到偏移点（内容起始）
          _player?.seek(_startOffset);
        } else {
          // 无偏移：直接 seek 到 0
          _player?.seek(Duration.zero);
        }
      } else if (_position.inSeconds > 0 &&
          _duration.inSeconds > 0 &&
          !_offsetDetected &&
          _position.inMilliseconds > _duration.inMilliseconds * 0.9 &&
          _duration.inSeconds > 240) {
        // 备用检查：rawPosition > 90% rawDuration（无偏移检测的情况）
        debugPrint(
          '[SecureHLS] ★ Fallback: rawPos=$_position > 90% of rawDur=$_duration. '
          'Seeking to zero...',
        );
        _player?.seek(Duration.zero);
      }
    });
  }

  /// 显示位置（修正 PTS 偏移）
  Duration get _displayPosition {
    if (_offsetDetected && _position >= _startOffset) {
      return _position - _startOffset;
    }
    return _position;
  }

  Duration get _effectiveTotalDuration {
    if (_offsetDetected) {
      // 优先使用服务端返回的真实时长
      if (_durationHint > Duration.zero) {
        return _durationHint;
      }
      // 无服务端时长提示时，用播放器时长减去 PTS 偏移估算真实时长
      final estimated = _duration - _startOffset;
      if (estimated > Duration.zero) {
        return estimated;
      }
    }
    // ★ 渐进式 HLS 修复：当服务端返回了真实时长（durationHint），始终优先使用
    // 播放器报告的 _duration 可能因渐进式生成而不准确（偏大或偏小）
    if (_durationHint > Duration.zero) {
      // 如果 hint 和 player duration 差距在 5% 以内，使用两者中较大的
      // 如果差距很大，信任 hint（服务端通过 ffprobe 获取的精确值）
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

    // 将原始保存的位置转换为显示坐标
    final savedDisplay = _offsetDetected && savedRaw > _startOffset
        ? savedRaw - _startOffset
        : savedRaw;

    final total = _effectiveTotalDuration;
    if (total.inSeconds > 0 &&
        savedDisplay >= total - const Duration(seconds: 10)) {
      _clearResumeProgress();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('检测到上次播放到 ${_formatDuration(savedDisplay)}，是否继续？'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '继续播放',
          onPressed: () {
            // _seekTo 接收显示坐标
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

  void _setError(String error) {
    if (mounted) {
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  String _formatError(String error) {
    if (error.contains('HTTP 500') || error.contains('500')) {
      return '服务器转码失败，请稍后重试';
    }
    if (error.contains('HTTP 404') || error.contains('404')) {
      return '视频分片暂不可用，请重试（服务器正在生成或缓存已过期）';
    }
    if (error.contains('HTTP 503') || error.contains('503')) {
      return '视频分片仍在生成中，请稍后重试';
    }
    if (error.contains('timeout') || error.contains('Timeout')) {
      return '连接超时，请检查网络';
    }
    if (error.contains('SAE') || error.contains('handshake')) {
      return '安全握手失败，请重新登录';
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
    // 停止安全代理
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
    _hideControlsTimer?.cancel();
    _cancelSubscriptions();
    _player?.dispose();
    // 停止安全代理服务器
    _proxyServer?.stop();
    _proxyServer = null;
    unawaited(_saveResumeProgressIfNeeded(_position));
    _cleanupHlsSession();
    _exitFullscreen();
    WakelockPlus.disable();
    super.dispose();
  }

  void _enterFullscreen() {
    // 使用 immersiveSticky 完全隐藏状态栏和导航栏，实现真正全屏
    // 用户从边缘滑动可临时显示系统 UI，松手后自动隐藏
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

    // ★ 修复：代理将 segment_N.ts 重写为 http://127.0.0.1:PORT/segment_N.ts，
    //   旧的 ^segment_ 锚点无法匹配代理 URL，导致 segmentCount 始终为 0。
    //   去掉行首锚点，匹配 segment 模式在行内任意位置出现的情况。
    final segmentCount = RegExp(r'segment_\d+\.ts').allMatches(content).length;
    final hasEndList = content.contains('#EXT-X-ENDLIST');

    // 进行中的长视频：至少 2 段再开播，避免播放器立刻请求 segment_1 命中 404。
    // 已结束短视频：允许单段播放。
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

  /// Seek 到指定位置（接收 **显示坐标** = 用户看到的时间轴）
  ///
  /// 内部自动转换为播放器原始 PTS 坐标。
  /// ★ 改进：异步预请求目标分片，触发服务端按需生成（减少 seek 延迟）。
  void _seekTo(Duration displayPos) {
    if (_player == null) return;

    // 将显示坐标转换为原始 PTS 坐标
    Duration rawTarget = displayPos;
    if (_offsetDetected) {
      rawTarget = displayPos + _startOffset;
    }

    final int targetMs = rawTarget.inMilliseconds;
    final int minMs = _startOffset.inMilliseconds;
    final int maxMs = _duration > Duration.zero
        ? _duration.inMilliseconds
        : (_offsetDetected
            ? (_durationHint + _startOffset).inMilliseconds
            : targetMs);
    final clampedMs = targetMs.clamp(minMs, maxMs);

    // ★ 预请求目标分片及相邻分片：触发服务端按需生成
    // 当用户 seek 到远超缓冲区的位置时，服务端 get_segment_direct
    // 会自动调用 generate_segment_on_demand 按需生成目标分片。
    // 通过 HEAD 请求预触发生成，减少 mpv 实际请求时的等待时间。
    final displaySeconds = displayPos.inSeconds;
    final targetSegmentIndex = displaySeconds ~/ 2; // 2 秒一个分片
    _proxyServer?.prefetchAroundSegment(targetSegmentIndex);

    _player!.seek(Duration(milliseconds: clampedMs));
  }

  /// 基于当前 **显示位置** 做相对 seek
  void _seekRelative(int seconds) {
    _seekTo(_displayPosition + Duration(seconds: seconds));
  }

  void _setPlaybackSpeed(double speed) {
    _player?.setRate(speed);
    setState(() => _playbackSpeed = speed);
  }

  // ============ 控制栏显示/隐藏 ============

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

  // ============ 下载 ============

  Future<void> _downloadFile() async {
    if (_isDownloading) return;

    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.storage.request();
      if (!status.isGranted && Platform.isAndroid) {
        final ms = await Permission.manageExternalStorage.request();
        if (!ms.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('需要存储权限')));
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
        throw Exception('无法获取下载目录');
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
      final request = http.Request('GET', Uri.parse(downloadUrl));
      if (_authToken != null) {
        request.headers['Authorization'] = 'Bearer $_authToken';
      }

      final client = http.Client();
      final response = await client.send(request);
      final contentLength = response.contentLength ?? 0;
      final sink = file.openWrite();
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0 && mounted) {
          setState(() => _downloadProgress = received / contentLength);
        }
      }

      await sink.close();
      client.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('已下载到 ${downloadDir.path}'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  // ============ 格式化工具 ============

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ============ UI 构建 ============

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
              // 视频画面
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

              // 缓冲指示器 (MD3 风格) —— 使用 RepaintBoundary 隔离重绘
              if (_isBuffering && !_isLoading)
                const Center(
                  child: RepaintBoundary(
                    child: MD3BufferingIndicator(
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                ),

              // 自定义控制栏 —— AnimatedSwitcher 实现丝滑淡入/淡出
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: (!_isLoading && _error == null && _showControls)
                    ? _buildControlsOverlay()
                    : const SizedBox.shrink(key: ValueKey('controls_hidden')),
              ),

              // 加载状态
              if (_isLoading) _buildLoading(),

              // 错误状态
              if (_error != null && !_isLoading) _buildError(),

              // 下载进度
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
            // 顶部栏
            _buildTopBar(),
            const Spacer(),
            // 中间播放按钮
            _buildCenterControls(),
            const Spacer(),
            // 底部进度条和控制按钮
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
              tooltip: '下载原文件',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 快退 10 秒
        IconButton(
          icon: const Icon(Icons.replay_10_rounded,
              color: Colors.white, size: 36),
          onPressed: () => _seekRelative(-10),
          splashRadius: 28,
        ),
        const SizedBox(width: 32),
        // 播放/暂停
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
        // 快进 10 秒
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
    // 拖拽位置已是显示坐标，正常播放则用修正后的 _displayPosition
    final displayPosition = _isDraggingProgress && _dragPreviewPosition != null
        ? _dragPreviewPosition!
        : _displayPosition;
    final posMs = displayPosition.inMilliseconds.toDouble();
    // 缓冲位置也需修正 PTS 偏移
    final rawBufMs = _bufferedPosition.inMilliseconds.toDouble();
    final offsetMs =
        _offsetDetected ? _startOffset.inMilliseconds.toDouble() : 0.0;
    final bufMs =
        (rawBufMs - offsetMs).clamp(0.0, totalMs > 0 ? totalMs : rawBufMs);
    final safeTotalMs = totalMs <= 0 ? posMs : totalMs;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 时间行 - 放在 slider 上方
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
            // MD3 风格进度条 - 单层 slider，用自定义 track 显示缓冲
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
            // 底部控制按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Spacer(),
                  // 播放速度
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

  /// 显示加密协议详情弹窗 — 带流水线动画
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
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '播放速度',
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
      detailText: 'SAE 安全握手 → AES-256 静态加密 → Session 鉴权',
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
              label: const Text('重试'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _exitFullscreen();
                Navigator.pop(context);
              },
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadProgress() {
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
                const Expanded(
                    child:
                        Text('下载中...', style: TextStyle(color: Colors.white))),
                Text('${(_downloadProgress * 100).toInt()}%',
                    style: const TextStyle(color: Colors.white)),
              ],
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

// ============================================================
// 加密流水线动画底部弹窗
// ============================================================

/// 数据模型 —— 流水线中的每个协议节点
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

/// 动画加密详情面板 —— 工厂流水线风格
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
  // 主时间线控制器（驱动所有卡片的出场）
  late final AnimationController _masterController;
  // 盾牌脉冲
  late final AnimationController _shieldPulseController;
  // 数据粒子流动
  late final AnimationController _particleController;
  // 节点激活闪光
  late final AnimationController _glowController;

  late final List<_ProtocolNode> _nodes;

  // 为每个节点计算的入场动画（slide + fade）
  final List<Animation<double>> _slideAnimations = [];
  final List<Animation<double>> _fadeAnimations = [];
  // 连接线动画
  final List<Animation<double>> _connectorAnimations = [];
  // 激活状态动画
  final List<Animation<double>> _activateAnimations = [];

  @override
  void initState() {
    super.initState();

    // 构建节点列表
    _nodes = _buildNodes();

    // ---- 主时间线 ----
    // 总时长 = 节点数 * 350ms（交错间隔）+ 尾部余量
    final totalMs = _nodes.length * 350 + 400;
    _masterController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );

    // 为每个节点创建交错动画
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

      // 激活动画（卡片出现后 → 光环扩散）
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

      // 连接线（从上一个节点到当前节点之间的管道）
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

    // ---- 光效（柔和渐变） ----
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);

    // 启动主时间线
    _masterController.forward();
  }

  List<_ProtocolNode> _buildNodes() {
    final runtime = widget.runtime;
    final zkpPath = runtime?.zkpActive == true;
    final fallbackPath = runtime?.fallbackActive == true;
    return [
      _ProtocolNode(
        icon: Icons.vpn_key_rounded,
        title: '密钥交换',
        subtitle: 'WPA3-SAE (Simultaneous Authentication of Equals)',
        detail: 'Dragonfly 密钥交换协议，抵抗离线字典攻击，建立安全会话',
        color: Colors.orangeAccent,
      ),
      _ProtocolNode(
        icon: Icons.lock_rounded,
        title: '静态存储加密',
        subtitle: 'AES-256-GCM (Galois/Counter Mode)',
        detail: '磁盘上的缓存视频段使用 AES-256-GCM 加密，即使物理访问也无法读取',
        color: Colors.cyanAccent,
      ),
      _ProtocolNode(
        icon: Icons.security_rounded,
        title: '分片访问鉴权',
        subtitle: zkpPath
            ? 'Bulletproofs ZKP (POST)'
            : 'Session Token + Encrypted GET Fallback',
        detail: fallbackPath
            ? '检测到 proof 失败时已切换加密 GET 兜底，链路仍为 AES-256-GCM 加密分片传输'
            : '当前分片请求通过 ZKP proof 校验，失败时会自动会话重建后重试',
        color: Colors.purpleAccent,
      ),
      _ProtocolNode(
        icon: Icons.fingerprint_rounded,
        title: '链路运行状态',
        subtitle: 'Blake3 Cryptographic Hash',
        detail:
            'proof请求: ${runtime?.proofGenerateRequests ?? 0}，失败: ${runtime?.proofGenerateFailures ?? 0}，分片重试: ${runtime?.segmentRetries ?? 0}',
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
              // 拖拽指示条
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
              // 盾牌标题行
              _buildAnimatedHeader(),
              const SizedBox(height: 6),
              _buildSubtitleRow(),
              const SizedBox(height: 24),
              // 流水线节点列表
              ..._buildPipelineNodes(),
              // 会话信息卡
              // 会话信息卡
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

  /// 盾牌标题 — 带脉冲光效
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
            const Text(
              '端到端加密保护',
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
    final mode = runtime?.fallbackActive == true
        ? 'ZKP + Encrypted GET Fallback'
        : 'ZKP Verified Segment Path';
    return Text(
      'SAE + AES-256-GCM + $mode + Blake3',
      style: TextStyle(
        color: Colors.greenAccent,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// 构建流水线节点列表（卡片 + 连接线交替排列）
  List<Widget> _buildPipelineNodes() {
    final List<Widget> widgets = [];
    for (int i = 0; i < _nodes.length; i++) {
      // 连接线（除了第一个节点之前）
      if (i > 0) {
        widgets.add(_buildAnimatedConnector(i - 1));
      }
      // 节点卡片
      widgets.add(_buildAnimatedNode(i));
    }
    return widgets;
  }

  /// 带动画的连接管道线
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

  /// 带动画的协议节点卡片
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

  /// 会话信息卡片
  Widget _buildSessionInfo() {
    final sessionId = widget.sessionId!;
    return AnimatedBuilder(
      animation: _masterController,
      builder: (context, _) {
        // 在所有节点出现后再显示
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
                      const Text(
                        '会话信息',
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
                    'Session: ${sessionId.length > 20 ? '${sessionId.substring(0, 20)}...' : sessionId}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '传输模式: ${widget.runtime?.fallbackActive == true ? 'ZKP + Encrypted GET Fallback' : 'ZKP POST + AES-256-GCM'}',
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

/// 单个协议节点卡片 —— 带激活动效和光粒子
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
              // 图标 + 激活光环
              _buildIconWithGlow(glow),
              const SizedBox(width: 14),
              // 文字区域
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
              const Text(
                '已启用',
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

/// 流水线连接管道绘制器 —— 带流动粒子
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

    // 管道线（渐变）
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

    // 发光管道背景
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

    // 流动粒子（5 个粒子沿管道流动，使用正弦曲线实现流畅运动）
    if (progress > 0.3) {
      for (int i = 0; i < 5; i++) {
        final phase = (particlePhase + i / 5.0) % 1.0;
        // 使用 sin 曲线让粒子在端点减速，中间加速（更自然的流动感）
        final easedPhase = 0.5 - 0.5 * cos(phase * pi);
        final y = top + (bottom - top) * easedPhase;
        // 使用 sin² 曲线平滑淡入淡出
        final opacity = sin(phase * pi);
        final blendColor = Color.lerp(fromColor, toColor, phase)!;
        // 粒子大小随位置变化（中间最大）
        final radius = 2.0 + opacity * 1.5;
        final particlePaint = Paint()
          ..color = blendColor.withValues(alpha: opacity * 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

        canvas.drawCircle(Offset(centerX, y), radius, particlePaint);
      }
    }

    // 箭头 (▽) 在管道末端
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
