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
  String _loadingStatus = '姝ｅ湪寤虹珛瀹夊叏杩炴帴...';
  String? _authToken;
  String? _hlsSessionId;
  String? _userId;
  String? _userSaeSecret;
  bool _isDownloading = false;
  double _downloadProgress = 0;

  // 瀹夊叏浠ｇ悊锛氭嫤鎴?libmpv 璇锋眰锛岃В瀵?ChaCha20-Poly1305 鍔犲瘑鐨勮棰戞
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
      // 鈽?鎾斁瑙嗛鍓嶅仠姝㈡鍦ㄦ挱鏀剧殑闊抽锛岄伩鍏嶉煶瑙嗛鍚屾椂鎾斁
      ref.read(audioPlayerServiceProvider.notifier).stop();

      setState(() {
        _isLoading = true;
        _error = null;
        _loadingStatus = '姝ｅ湪鑾峰彇鍑嵁...';
      });

      // 鑾峰彇鐢ㄦ埛鍑嵁
      const storage = FlutterSecureStorage();
      _authToken = await storage.read(key: 'access_token');
      _userId = await storage.read(key: 'user_id');
      _userSaeSecret = await storage.read(key: 'user_password_hash');

      if (_authToken == null || _authToken!.isEmpty) {
        _setError('鏈櫥褰曪紝璇峰厛鐧诲綍');
        return;
      }

      if (_userId == null || _userSaeSecret == null) {
        _setError('鏃犳硶鑾峰彇鐢ㄦ埛鍑嵁锛岃閲嶆柊鐧诲綍');
        return;
      }

      await _loadResumeProgress();
      await _fetchDurationHint();

      // 閫氳繃 SAE 瀹夊叏閫氶亾 + direct 妯″紡浼犺緭锛堜笉闇€瑕?ZKP 璇佹槑锛?
      await _tryHlsStreaming();
    } catch (e, stack) {
      debugPrint('[VideoPlayer] Error: $e');
      debugPrint('[VideoPlayer] Stack: $stack');
      _setError('鎾斁澶辫触: ${_formatError(e.toString())}');
    }
  }

  Future<void> _tryHlsStreaming() async {
    setState(() {
      _loadingStatus = '姝ｅ湪鎵ц SAE 瀹夊叏鎻℃墜...';
    });

    debugPrint('[VideoPlayer] Starting SAE handshake for secure HLS...');

    final handshakeService = SaeHandshakeService(
      baseUrl: widget.baseUrl,
      jwtToken: _authToken!,
    );

    final filePath = widget.filePath;
    final fileId = widget.fileId;

    // 鈹€鈹€ Step 1: SAE 鎻℃墜 + 浼氳瘽鍒涘缓锛堝姞瀵嗘ā寮忥紝鎵€鏈夋 ChaCha20-Poly1305 鍔犲瘑浼犺緭锛夆攢鈹€鈹€
    late final String sessionId;
    late final Uint8List pmk;

    try {
      final result = await handshakeService.performHandshake(
        filePath: filePath,
        fileId: fileId,
        password: _userSaeSecret!,
        userId: _userId!,
        directMode: false, // 鈽?绂佺敤 direct 妯″紡锛屽己鍒跺姞瀵嗕紶杈?
      );

      sessionId = result.$1;
      pmk = result.$2;
      _hlsSessionId = sessionId;
    } on SaeHandshakeException catch (e) {
      debugPrint('[VideoPlayer] SAE/session stage failed: $e');
      if (e.stage == SaeStage.createSession) {
        if (e.statusCode == 412) {
          _setError(
            '浼氳瘽鍒涘缓琚嫆缁濓紙澶栭儴缂撳瓨涓嶅彲鐢級銆俓n'
            '璇锋鏌?HLS_CACHE_PATH 鏄惁鎸囧悜宸叉寕杞藉閮ㄥ瓨鍌紝鎴栧叧闂?ROCKZERO_STRICT_EXTERNAL_HLS_CACHE銆俓n'
            '鍚庣淇℃伅: ${_formatError(e.message)}',
          );
        } else {
          _setError('浼氳瘽鍒涘缓澶辫触(${e.statusCode}): ${_formatError(e.message)}');
        }
      } else {
        _setError(
            'SAE 瀹夊叏鎻℃墜澶辫触(${e.stage.name}/${e.statusCode}): ${_formatError(e.message)}');
      }
      return;
    } catch (e) {
      debugPrint('[VideoPlayer] SAE handshake failed: $e');
      _setError('SAE 瀹夊叏鎻℃墜澶辫触: ${_formatError(e.toString())}');
      return;
    }

    debugPrint('[VideoPlayer] HLS session (encrypted mode): $sessionId');

    // 鈹€鈹€ Step 2: 鍚姩鏈湴瀹夊叏浠ｇ悊锛堣В瀵?ChaCha20-Poly1305 鍔犲瘑鐨勮棰戞锛夆攢鈹€鈹€鈹€
    //
    // 瀹夊叏鏋舵瀯锛?
    //   - 鏈嶅姟绔墍鏈夎棰戞鍧囦娇鐢?ChaCha20-Poly1305 鍔犲瘑浼犺緭锛堜笉鍏佽鏄庢枃锛?
    //   - 鏈湴浠ｇ悊鎷︽埅 libmpv 鐨?HTTP 璇锋眰
    //   - 浠ｇ悊浠庢湇鍔＄鑾峰彇鍔犲瘑鏁版嵁锛屼娇鐢?PMK 娲剧敓瀵嗛挜鏈湴瑙ｅ瘑
    //   - 瑙ｅ瘑鍚庣殑鏄庢枃浠呭瓨鍦ㄤ簬璁惧鍐呭瓨涓紝涓嶈惤鐩?
    //   - libmpv 浠?127.0.0.1 鑾峰彇瑙ｅ瘑鍚庣殑鏄庢枃瑙嗛娈?

    if (!mounted) return;
    setState(() => _loadingStatus = '姝ｅ湪鍚姩瀹夊叏浠ｇ悊...');

    late final String proxyPlaylistUrl;

    try {
      // 鍒涘缓浼氳瘽閲嶅缓鍥炶皟锛堝綋 session 杩囨湡鏃惰嚜鍔ㄩ噸鏂版彙鎵嬶級
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
      _setError('瀹夊叏浠ｇ悊鍚姩澶辫触: ${_formatError(e.toString())}');
      return;
    }

    // 鈹€鈹€ Step 3: 绛夊緟棣栦釜鍒嗙墖灏辩华锛堥€氳繃浠ｇ悊妫€鏌ユ挱鏀惧垪琛級鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
    if (!mounted) return;
    setState(() => _loadingStatus = '姝ｅ湪绛夊緟瑙嗛鍒嗙墖...');

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
          _loadingStatus = '姝ｅ湪绛夊緟瑙嗛鍒嗙墖... (${i + 1}s)';
        });
      }
    }

    if (!playlistReady) {
      _setError('鎾斁鍒楄〃鐢熸垚瓒呮椂锛堝凡绛夊緟 90 绉掞級锛岃妫€鏌ヨ棰戠紪鐮佹牸寮忔垨鏈嶅姟鍣?ffmpeg 閰嶇疆');
      return;
    }

    if (!mounted) return;

    setState(() => _loadingStatus = '姝ｅ湪鍒濆鍖栨挱鏀惧櫒...');

    // 鈹€鈹€ Step 4: 鍒涘缓 media_kit 鎾斁鍣?鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: _calculateAdaptiveBufferBytes(),
      ),
    );

    // libmpv 涓撶敤灞炴€э細浼樺寲 HLS 娴佹挱鏀?
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
      if (Platform.isAndroid) {
        await mpv.setProperty('hwdec', 'mediacodec-copy');
        await mpv.setProperty('hwdec-codecs', 'all');
        await mpv.setProperty('vd-lavc-software-fallback', 'no');
        await mpv.setProperty('vo', 'gpu');
        await mpv.setProperty('gpu-context', 'android');
      } else {
        await mpv.setProperty('hwdec', 'auto-safe');
        await mpv.setProperty('vd-lavc-software-fallback', 'yes');
      }
      await mpv.setProperty('video-sync', 'audio');
      await mpv.setProperty('interpolation', 'no');
      await mpv.setProperty('audio-pitch-correction', 'yes');
      await mpv.setProperty('hr-seek', 'yes');
      // 寮哄埗灏嗘祦璧峰鏃堕棿閲嶅畾鍚戜负 0锛屼慨澶?PTS 鍋忕Щ瀵艰嚧鐨勬椂闂存樉绀洪敊璇?
      await mpv.setProperty('rebase-start-time', 'yes');
      // 鐢熸垚缂哄け PTS 骞朵涪寮冩崯鍧忓抚锛屽噺灏戦煶鐢绘紓绉讳笌鍗￠】銆?
      await mpv.setProperty(
        'demuxer-lavf-o',
        'fflags=+genpts+discardcorrupt',
      );
      // 鈽?寮哄埗鍏佽鍦ㄢ€滅洿鎾€滺LS 娴佷腑杩涜 seek 鎿嶄綔
      await mpv.setProperty('force-seekable', 'yes');

      // 缁撳悎璁惧鎬ц兘鍜岀爜鐜囧姩鎬佽皟鏁寸紦鍐蹭笌鍥炶绐楀彛銆?
      await _applyAdaptiveMpvTuning(mpv);
    }

    _videoController = VideoController(_player!);
    _setupPlayerListeners();

    // 鐩戝惉鎾斁閿欒
    final errorCompleter = Completer<String?>();
    StreamSubscription<String>? errorSub;
    errorSub = _player!.stream.error.listen((error) {
      if (error.isNotEmpty && !errorCompleter.isCompleted) {
        errorCompleter.complete(error);
        errorSub?.cancel();
      }
    });

    // 鐩戝惉鎴愬姛寮€濮嬫挱鏀?
    final playingCompleter = Completer<bool>();
    StreamSubscription<bool>? playingSub;
    playingSub = _player!.stream.playing.listen((playing) {
      if (playing && !playingCompleter.isCompleted) {
        playingCompleter.complete(true);
        playingSub?.cancel();
      }
    });

    // 鐩戝惉鏃堕暱鑾峰彇锛堣〃绀哄獟浣撳厓鏁版嵁宸茶В鏋愶級
    final durationCompleter = Completer<bool>();
    StreamSubscription<Duration>? durationSub;
    durationSub = _player!.stream.duration.listen((dur) {
      if (dur.inMilliseconds > 0 && !durationCompleter.isCompleted) {
        durationCompleter.complete(true);
        durationSub?.cancel();
      }
    });

    // 鈹€鈹€ 浣跨敤鏈湴瀹夊叏浠ｇ悊 URL锛堝姞瀵嗕紶杈?+ 鏈湴瑙ｅ瘑锛夆攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
    //
    // media_kit 鈫?GET http://127.0.0.1:{port}/playlist.m3u8  (鏈湴浠ｇ悊)
    //           鈫?GET http://127.0.0.1:{port}/segment_N.ts   (鏈湴浠ｇ悊)
    //
    // 浠ｇ悊鍐呴儴娴佺▼锛?
    //   浠ｇ悊 鈫?GET /api/v1/secure-hls/{session_id}/segment_N.ts (鏈嶅姟绔紝鍔犲瘑鏁版嵁)
    //        鈫?ChaCha20-Poly1305 瑙ｅ瘑锛堜娇鐢?PMK 娲剧敓瀵嗛挜锛?
    //        鈫?杩斿洖鏄庢枃 MPEG-TS 缁?libmpv
    //
    // 瀹夊叏淇濋殰锛?
    //   - 缃戠粶浼犺緭鍏ㄧ▼ ChaCha20-Poly1305 鍔犲瘑
    //   - SAE 鎻℃墜纭繚浼氳瘽瀵嗛挜瀹夊叏浜ゆ崲
    //   - Session ID 涓嶅彲鐚滄祴锛?28 浣嶉殢鏈猴級
    //   - 鏄庢枃鏁版嵁浠呭瓨鍦ㄤ簬璁惧鍐呭瓨涓?
    //   - 纾佺洏缂撳瓨娈典娇鐢?ChaCha20-Poly1305 闈欐€佸姞瀵?
    await _player!.open(
      Media(proxyPlaylistUrl),
      play: true,
    );

    // 涓嶅啀鍦?open 鍚庣珛鍗?seek 鈥?绛夊緟鎾斁纭鍚庡啀澶勭悊

    // 绛夊緟鎾斁淇″彿銆佹椂闀夸俊鍙锋垨閿欒锛岃秴鏃?25 绉?
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
      // 瓒呮椂浣嗘棤閿欒 鈥?浠嶇劧鏄剧ず鎾斁鍣紙鍙兘鍦ㄧ紦鍐插ぇ鏂囦欢锛?
      debugPrint(
          '[VideoPlayer] HLS playback timeout but no error 鈥?showing player');
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _offerResumePromptIfNeeded();
      return;
    }

    // 鎾斁鍣ㄦ姤閿?
    debugPrint('[VideoPlayer] HLS playback error: $result');
    _setError('鎾斁澶辫触: ${_formatError(result.toString())}');
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

  /// 鏄剧ず浣嶇疆
  Duration get _displayPosition {
    return _position;
  }

  Duration get _effectiveTotalDuration {
    // 鏈嶅姟绔椂闀夸紭鍏堬紝鎾斁鍣ㄦ椂闀夸綔涓哄洖閫€銆?
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
        content: Text('妫€娴嬪埌涓婃鎾斁鍒?${_formatDuration(savedDisplay)}锛屾槸鍚︾户缁紵'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '缁х画鎾斁',
          onPressed: () {
            // _seekTo 鎺ユ敹鏄剧ず鍧愭爣
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
      return 'Server transcoding failed, please try again later';
    }
    if (error.contains('HTTP 404') || error.contains('404')) {
      return 'Video segment is temporarily unavailable, please retry';
    }
    if (error.contains('HTTP 503') || error.contains('503')) {
      return 'Video segment is still being generated, please wait and retry';
    }
    if (error.contains('timeout') || error.contains('Timeout')) {
      return 'Connection timed out, please check your network';
    }
    if (error.contains('SAE') || error.contains('handshake')) {
      return '瀹夊叏鎻℃墜澶辫触锛岃閲嶆柊鐧诲綍';
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
    // 鍋滄瀹夊叏浠ｇ悊
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
    // 鍋滄瀹夊叏浠ｇ悊鏈嶅姟鍣?
    _proxyServer?.stop();
    _proxyServer = null;
    unawaited(_saveResumeProgressIfNeeded(_position));
    _cleanupHlsSession();
    _exitFullscreen();
    WakelockPlus.disable();
    super.dispose();
  }

  void _enterFullscreen() {
    // 浣跨敤 immersiveSticky 瀹屽叏闅愯棌鐘舵€佹爮鍜屽鑸爮锛屽疄鐜扮湡姝ｅ叏灞?
    // 鐢ㄦ埛浠庤竟缂樻粦鍔ㄥ彲涓存椂鏄剧ず绯荤粺 UI锛屾澗鎵嬪悗鑷姩闅愯棌
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

    // 鈽?淇锛氫唬鐞嗗皢 segment_N.ts 閲嶅啓涓?http://127.0.0.1:PORT/segment_N.ts锛?
    //   鏃х殑 ^segment_ 閿氱偣鏃犳硶鍖归厤浠ｇ悊 URL锛屽鑷?segmentCount 濮嬬粓涓?0銆?
    //   鍘绘帀琛岄閿氱偣锛屽尮閰?segment 妯″紡鍦ㄨ鍐呬换鎰忎綅缃嚭鐜扮殑鎯呭喌銆?
    final segmentCount = RegExp(r'segment_\d+\.ts').allMatches(content).length;
    final hasEndList = content.contains('#EXT-X-ENDLIST');

    // 杩涜涓殑闀胯棰戯細鑷冲皯 2 娈靛啀寮€鎾紝閬垮厤鎾斁鍣ㄧ珛鍒昏姹?segment_1 鍛戒腑 404銆?
    // 宸茬粨鏉熺煭瑙嗛锛氬厑璁稿崟娈垫挱鏀俱€?
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

  /// Seek 鍒版寚瀹氫綅缃紙鎺ユ敹 **鏄剧ず鍧愭爣** = 鐢ㄦ埛鐪嬪埌鐨勬椂闂磋酱锛?
  ///
  /// 鍐呴儴鑷姩杞崲涓烘挱鏀惧櫒鍘熷 PTS 鍧愭爣銆?
  /// 鈽?鏀硅繘锛氬紓姝ラ璇锋眰鐩爣鍒嗙墖锛岃Е鍙戞湇鍔＄鎸夐渶鐢熸垚锛堝噺灏?seek 寤惰繜锛夈€?
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

    // 鈽?棰勮姹傜洰鏍囧垎鐗囧強鐩搁偦鍒嗙墖锛氳Е鍙戞湇鍔＄鎸夐渶鐢熸垚
    // 褰撶敤鎴?seek 鍒拌繙瓒呯紦鍐插尯鐨勪綅缃椂锛屾湇鍔＄ get_segment_direct
    // 浼氳嚜鍔ㄨ皟鐢?generate_segment_on_demand 鎸夐渶鐢熸垚鐩爣鍒嗙墖銆?
    // 閫氳繃 HEAD 璇锋眰棰勮Е鍙戠敓鎴愶紝鍑忓皯 mpv 瀹為檯璇锋眰鏃剁殑绛夊緟鏃堕棿銆?
    final displaySeconds = displayPos.inSeconds;
    final targetSegmentIndex = displaySeconds ~/ 2; // 2 绉掍竴涓垎鐗?
    _proxyServer?.prefetchAroundSegment(targetSegmentIndex);

    _player!.seek(Duration(milliseconds: clampedMs));
  }

  /// 鍩轰簬褰撳墠 **鏄剧ず浣嶇疆** 鍋氱浉瀵?seek
  void _seekRelative(int seconds) {
    _seekTo(_displayPosition + Duration(seconds: seconds));
  }

  void _setPlaybackSpeed(double speed) {
    _player?.setRate(speed);
    setState(() => _playbackSpeed = speed);
  }

  // ============ 鎺у埗鏍忔樉绀?闅愯棌 ============

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

  // ============ 涓嬭浇 ============

  Future<void> _downloadFile() async {
    if (_isDownloading) return;

    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.storage.request();
      if (!status.isGranted && Platform.isAndroid) {
        final ms = await Permission.manageExternalStorage.request();
        if (!ms.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Storage permission is required')));
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
        throw Exception('鏃犳硶鑾峰彇涓嬭浇鐩綍');
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
              content: Text('宸蹭笅杞藉埌 ${downloadDir.path}'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('涓嬭浇澶辫触: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  // ============ 鏍煎紡鍖栧伐鍏?============

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ============ UI 鏋勫缓 ============

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
              // 瑙嗛鐢婚潰
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

              // 缂撳啿鎸囩ず鍣?(MD3 椋庢牸) 鈥斺€?浣跨敤 RepaintBoundary 闅旂閲嶇粯
              if (_isBuffering && !_isLoading)
                const Center(
                  child: RepaintBoundary(
                    child: MD3BufferingIndicator(
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                ),

              // 鑷畾涔夋帶鍒舵爮 鈥斺€?AnimatedSwitcher 瀹炵幇涓濇粦娣″叆/娣″嚭
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: (!_isLoading && _error == null && _showControls)
                    ? _buildControlsOverlay()
                    : const SizedBox.shrink(key: ValueKey('controls_hidden')),
              ),

              // 鍔犺浇鐘舵€?
              if (_isLoading) _buildLoading(),

              // 閿欒鐘舵€?
              if (_error != null && !_isLoading) _buildError(),

              // 涓嬭浇杩涘害
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
            // 椤堕儴鏍?
            _buildTopBar(),
            const Spacer(),
            // 涓棿鎾斁鎸夐挳
            _buildCenterControls(),
            const Spacer(),
            // 搴曢儴杩涘害鏉″拰鎺у埗鎸夐挳
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
                      'SAE+ChaCha20',
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
              tooltip: 'Download original file',
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
        // 蹇€€ 10 绉?
        IconButton(
          icon: const Icon(Icons.replay_10_rounded,
              color: Colors.white, size: 36),
          onPressed: () => _seekRelative(-10),
          splashRadius: 28,
        ),
        const SizedBox(width: 32),
        // 鎾斁/鏆傚仠
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
        // 蹇繘 10 绉?
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
    // 鎷栨嫿浣嶇疆宸叉槸鏄剧ず鍧愭爣锛屾甯告挱鏀惧垯鐢ㄤ慨姝ｅ悗鐨?_displayPosition
    final displayPosition = _isDraggingProgress && _dragPreviewPosition != null
        ? _dragPreviewPosition!
        : _displayPosition;
    final posMs = displayPosition.inMilliseconds.toDouble();
    // 缂撳啿浣嶇疆涓庢樉绀烘椂闂磋酱淇濇寔涓€鑷?
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
            // 鏃堕棿琛?- 鏀惧湪 slider 涓婃柟
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
            // MD3 椋庢牸杩涘害鏉?- 鍗曞眰 slider锛岀敤鑷畾涔?track 鏄剧ず缂撳啿
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
            // 搴曢儴鎺у埗鎸夐挳
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Spacer(),
                  // 鎾斁閫熷害
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

  /// 鏄剧ず鍔犲瘑鍗忚璇︽儏寮圭獥 鈥?甯︽祦姘寸嚎鍔ㄧ敾
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
                '鎾斁閫熷害',
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
      detailText: 'SAE 瀹夊叏鎻℃墜 鈫?AES-256 闈欐€佸姞瀵?鈫?Session 閴存潈',
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
              label: const Text('閲嶈瘯'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _exitFullscreen();
                Navigator.pop(context);
              },
              child: const Text('杩斿洖'),
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
                        Text('涓嬭浇涓?..', style: TextStyle(color: Colors.white))),
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
// 鍔犲瘑娴佹按绾垮姩鐢诲簳閮ㄥ脊绐?
// ============================================================

/// 鏁版嵁妯″瀷 鈥斺€?娴佹按绾夸腑鐨勬瘡涓崗璁妭鐐?
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

/// 鍔ㄧ敾鍔犲瘑璇︽儏闈㈡澘 鈥斺€?宸ュ巶娴佹按绾块鏍?
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
  // 涓绘椂闂寸嚎鎺у埗鍣紙椹卞姩鎵€鏈夊崱鐗囩殑鍑哄満锛?
  late final AnimationController _masterController;
  // 鐩剧墝鑴夊啿
  late final AnimationController _shieldPulseController;
  // 鏁版嵁绮掑瓙娴佸姩
  late final AnimationController _particleController;
  // 鑺傜偣婵€娲婚棯鍏?
  late final AnimationController _glowController;

  late final List<_ProtocolNode> _nodes;

  // 涓烘瘡涓妭鐐硅绠楃殑鍏ュ満鍔ㄧ敾锛坰lide + fade锛?
  final List<Animation<double>> _slideAnimations = [];
  final List<Animation<double>> _fadeAnimations = [];
  // 杩炴帴绾垮姩鐢?
  final List<Animation<double>> _connectorAnimations = [];
  // 婵€娲荤姸鎬佸姩鐢?
  final List<Animation<double>> _activateAnimations = [];

  @override
  void initState() {
    super.initState();

    // 鏋勫缓鑺傜偣鍒楄〃
    _nodes = _buildNodes();

    // ---- 涓绘椂闂寸嚎 ----
    // 鎬绘椂闀?= 鑺傜偣鏁?* 350ms锛堜氦閿欓棿闅旓級+ 灏鹃儴浣欓噺
    final totalMs = _nodes.length * 350 + 400;
    _masterController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );

    // 涓烘瘡涓妭鐐瑰垱寤轰氦閿欏姩鐢?
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

      // 婵€娲诲姩鐢伙紙鍗＄墖鍑虹幇鍚?鈫?鍏夌幆鎵╂暎锛?
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

      // 杩炴帴绾匡紙浠庝笂涓€涓妭鐐瑰埌褰撳墠鑺傜偣涔嬮棿鐨勭閬擄級
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

    // ---- 鍏夋晥锛堟煍鍜屾笎鍙橈級 ----
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);

    // 鍚姩涓绘椂闂寸嚎
    _masterController.forward();
  }

  List<_ProtocolNode> _buildNodes() {
    final runtime = widget.runtime;
    final retries = runtime?.segmentRetries ?? 0;
    final fallbackPath = retries > 0;
    return [
      _ProtocolNode(
        icon: Icons.vpn_key_rounded,
        title: 'Key Exchange',
        subtitle: 'WPA3-SAE (Simultaneous Authentication of Equals)',
        detail:
            'Dragonfly key exchange establishes session keys resistant to offline dictionary attacks.',
        color: Colors.orangeAccent,
      ),
      _ProtocolNode(
        icon: Icons.lock_rounded,
        title: 'At-Rest Encryption',
        subtitle: 'ChaCha20-Poly1305',
        detail:
            'Cached segments are stored as encrypted payloads; raw TS data is not persisted in plaintext.',
        color: Colors.cyanAccent,
      ),
      _ProtocolNode(
        icon: Icons.security_rounded,
        title: 'Segment Access Control',
        subtitle: fallbackPath
            ? 'Session Token + Encrypted GET Fallback'
            : 'Session Auth Ticket (GET)',
        detail: fallbackPath
            ? 'Proxy detected retries and switched to encrypted fallback while preserving secure segment transport.'
            : 'Segments are fetched through authenticated session tickets and decrypted locally before decoding.',
        color: Colors.purpleAccent,
      ),
      _ProtocolNode(
        icon: Icons.fingerprint_rounded,
        title: 'Runtime Integrity',
        subtitle: 'Poly1305 Authentication Tag',
        detail: 'Segment retry count: $retries',
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
              // 鎷栨嫿鎸囩ず鏉?
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
              // 鐩剧墝鏍囬琛?
              _buildAnimatedHeader(),
              const SizedBox(height: 6),
              _buildSubtitleRow(),
              const SizedBox(height: 24),
              // 娴佹按绾胯妭鐐瑰垪琛?
              ..._buildPipelineNodes(),
              // 浼氳瘽淇℃伅鍗?
              // 浼氳瘽淇℃伅鍗?
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

  /// 鐩剧墝鏍囬 鈥?甯﹁剦鍐插厜鏁?
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
              'End-to-End Encrypted Playback',
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
    final mode = (runtime?.segmentRetries ?? 0) > 0
        ? 'ZKP + Encrypted GET Fallback'
        : 'ZKP Verified Segment Path';
    return Text(
      'SAE + ChaCha20-Poly1305 + $mode + Poly1305',
      style: TextStyle(
        color: Colors.greenAccent,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// 鏋勫缓娴佹按绾胯妭鐐瑰垪琛紙鍗＄墖 + 杩炴帴绾夸氦鏇挎帓鍒楋級
  List<Widget> _buildPipelineNodes() {
    final List<Widget> widgets = [];
    for (int i = 0; i < _nodes.length; i++) {
      // 杩炴帴绾匡紙闄や簡绗竴涓妭鐐逛箣鍓嶏級
      if (i > 0) {
        widgets.add(_buildAnimatedConnector(i - 1));
      }
      // 鑺傜偣鍗＄墖
      widgets.add(_buildAnimatedNode(i));
    }
    return widgets;
  }

  /// 甯﹀姩鐢荤殑杩炴帴绠￠亾绾?
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

  /// 甯﹀姩鐢荤殑鍗忚鑺傜偣鍗＄墖
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

  /// 浼氳瘽淇℃伅鍗＄墖
  Widget _buildSessionInfo() {
    final sessionId = widget.sessionId!;
    return AnimatedBuilder(
      animation: _masterController,
      builder: (context, _) {
        // 鍦ㄦ墍鏈夎妭鐐瑰嚭鐜板悗鍐嶆樉绀?
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
                        '浼氳瘽淇℃伅',
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
                    'Transport mode: ${(widget.runtime?.segmentRetries ?? 0) > 0 ? 'ZKP + Encrypted GET Fallback' : 'Session GET + ChaCha20-Poly1305'}',
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

/// 鍗曚釜鍗忚鑺傜偣鍗＄墖 鈥斺€?甯︽縺娲诲姩鏁堝拰鍏夌矑瀛?
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
              // 鍥炬爣 + 婵€娲诲厜鐜?
              _buildIconWithGlow(glow),
              const SizedBox(width: 14),
              // 鏂囧瓧鍖哄煙
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
                'Active',
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

/// 娴佹按绾胯繛鎺ョ閬撶粯鍒跺櫒 鈥斺€?甯︽祦鍔ㄧ矑瀛?
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

    // 绠￠亾绾匡紙娓愬彉锛?
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

    // 鍙戝厜绠￠亾鑳屾櫙
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

    // 娴佸姩绮掑瓙锛? 涓矑瀛愭部绠￠亾娴佸姩锛屼娇鐢ㄦ寮︽洸绾垮疄鐜版祦鐣呰繍鍔級
    if (progress > 0.3) {
      for (int i = 0; i < 5; i++) {
        final phase = (particlePhase + i / 5.0) % 1.0;
        // 浣跨敤 sin 鏇茬嚎璁╃矑瀛愬湪绔偣鍑忛€燂紝涓棿鍔犻€燂紙鏇磋嚜鐒剁殑娴佸姩鎰燂級
        final easedPhase = 0.5 - 0.5 * cos(phase * pi);
        final y = top + (bottom - top) * easedPhase;
        // 浣跨敤 sin虏 鏇茬嚎骞虫粦娣″叆娣″嚭
        final opacity = sin(phase * pi);
        final blendColor = Color.lerp(fromColor, toColor, phase)!;
        // 绮掑瓙澶у皬闅忎綅缃彉鍖栵紙涓棿鏈€澶э級
        final radius = 2.0 + opacity * 1.5;
        final particlePaint = Paint()
          ..color = blendColor.withValues(alpha: opacity * 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

        canvas.drawCircle(Offset(centerX, y), radius, particlePaint);
      }
    }

    // 绠ご (鈻? 鍦ㄧ閬撴湯绔?
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
