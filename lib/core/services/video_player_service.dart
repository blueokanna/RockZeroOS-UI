import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../services/secure_hls_player.dart';

/// 视频播放器状态
class VideoPlayerState {
  final bool isPlaying;
  final bool isBuffering;
  final bool isPipMode;
  final bool isFullscreen;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final double volume;
  final double speed;
  final String? currentFileName;
  final String? currentFileId;
  final String? error;
  final bool isInitialized;
  final bool isSeeking;

  const VideoPlayerState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.isPipMode = false,
    this.isFullscreen = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.volume = 1.0,
    this.speed = 1.0,
    this.currentFileName,
    this.currentFileId,
    this.error,
    this.isInitialized = false,
    this.isSeeking = false,
  });

  VideoPlayerState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    bool? isPipMode,
    bool? isFullscreen,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    double? volume,
    double? speed,
    String? currentFileName,
    String? currentFileId,
    String? error,
    bool? isInitialized,
    bool? isSeeking,
  }) {
    return VideoPlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isPipMode: isPipMode ?? this.isPipMode,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      currentFileName: currentFileName ?? this.currentFileName,
      currentFileId: currentFileId ?? this.currentFileId,
      error: error,
      isInitialized: isInitialized ?? this.isInitialized,
      isSeeking: isSeeking ?? this.isSeeking,
    );
  }

  bool get hasVideo =>
      currentFileId != null && currentFileId!.isNotEmpty && isInitialized;
}

/// 全局视频播放器服务 - 支持小窗播放和后台播放
class VideoPlayerService extends Notifier<VideoPlayerState> {
  Player? _player;
  VideoController? _videoController;
  SecureHlsPlayer? _securePlayer;

  final List<StreamSubscription> _subscriptions = [];

  @override
  VideoPlayerState build() {
    ref.onDispose(_dispose);
    return const VideoPlayerState();
  }

  Player? get player => _player;
  VideoController? get videoController => _videoController;

  /// 开始播放安全加密视频
  Future<void> playSecureVideo({
    required String baseUrl,
    required String jwtToken,
    required String userId,
    required String password,
    required String fileId,
    required String fileName,
  }) async {
    // 如果正在播放同一个文件，不重新初始化
    if (state.currentFileId == fileId &&
        _player != null &&
        state.isInitialized) {
      await _player!.play();
      return;
    }

    // 停止当前播放
    await stop();

    state = state.copyWith(
      currentFileId: fileId,
      currentFileName: fileName,
      isBuffering: true,
      error: null,
      isInitialized: false,
    );

    try {
      // 1. SAE 握手
      _securePlayer = SecureHlsPlayer(
        baseUrl: baseUrl,
        jwtToken: jwtToken,
      );

      await _securePlayer!.initializeSaeHandshake(
        userId,
        password,
        fileId,
      );

      // 2. 使用直接播放模式（无代理，无加密，适合 ARM 设备）
      final playUrl = _securePlayer!.getDirectPlaylistUrl();

      // 3. 创建播放器
      //    ★ 低内存策略：限制播放器内部缓存，避免高内存设备压力
      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 16 * 1024 * 1024,
        ),
      );

      _videoController = VideoController(_player!);

      // 3.5. 设置 mpv 属性：PTS 修正 + HLS 优化 + ARM 多核 + 零磁盘缓存
      if (_player!.platform is NativePlayer) {
        final mpv = _player!.platform as NativePlayer;

        // ── 缓存策略：禁用磁盘缓存，限制内存缓存 ──
        await mpv.setProperty('cache', 'no');
        await mpv.setProperty('cache-on-disk', 'no');
        await mpv.setProperty('cache-secs', '0');
        await mpv.setProperty('demuxer-max-bytes', '16MiB');
        await mpv.setProperty('demuxer-readahead-secs', '1');
        await mpv.setProperty('demuxer-max-back-bytes', '2MiB');

        // ── 多核并行解码：自动利用所有 CPU 核心 ──
        await mpv.setProperty('vd-lavc-threads', '0');
        await mpv.setProperty('ad-lavc-threads', '0');
        await mpv.setProperty('demuxer-thread', 'yes');

        // ── 安卓平台强制硬件解码（MediaCodec），禁用软解回退 ──
        if (Platform.isAndroid) {
          await mpv.setProperty('hwdec', 'mediacodec-copy');
          await mpv.setProperty('hwdec-codecs', 'all');
          await mpv.setProperty('vd-lavc-software-fallback', 'no');
          await mpv.setProperty('vd-lavc-dr', 'yes');
          await mpv.setProperty('vo', 'gpu');
          await mpv.setProperty('gpu-context', 'android');
        } else {
          await mpv.setProperty('hwdec', 'auto-safe');
          await mpv.setProperty('hwdec-codecs', 'all');
          await mpv.setProperty('vd-lavc-software-fallback', 'inf');
          await mpv.setProperty('vd-lavc-dr', 'yes');
        }

        // ── PTS 时间戳修正 ──
        await mpv.setProperty('rebase-start-time', 'yes');

        // ── HLS 优化 ──
        await mpv.setProperty(
          'demuxer-lavf-o',
          'fflags=+genpts+discardcorrupt,live_start_index=0',
        );
        await mpv.setProperty('force-seekable', 'yes');
        await mpv.setProperty(
            'stream-lavf-o', 'reconnect=1,reconnect_streamed=1');

        // ── 音视频同步 ──
        await mpv.setProperty('video-sync', 'audio');

        // ── 渲染优化 ──
        await mpv.setProperty('vo', 'gpu');
        await mpv.setProperty('gpu-context', 'auto');
      }

      // 4. 设置监听器
      _setupListeners();

      // 5. 开始播放
      await _player!.open(Media(playUrl), play: true);

      state = state.copyWith(
        isInitialized: true,
        isBuffering: false,
      );
    } catch (e, stack) {
      debugPrint('[VideoPlayerService] Error: $e');
      debugPrint('[VideoPlayerService] Stack: $stack');
      state = state.copyWith(
        error: _formatError(e.toString()),
        isBuffering: false,
      );
    }
  }

  void _setupListeners() {
    _cancelSubscriptions();

    _subscriptions.add(_player!.stream.playing.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    }));

    _subscriptions.add(_player!.stream.position.listen((position) {
      if (!state.isSeeking) {
        state = state.copyWith(position: position);
      }
    }));

    _subscriptions.add(_player!.stream.duration.listen((duration) {
      state = state.copyWith(duration: duration);
    }));

    _subscriptions.add(_player!.stream.buffering.listen((buffering) {
      state = state.copyWith(isBuffering: buffering);
    }));

    _subscriptions.add(_player!.stream.buffer.listen((buffer) {
      state = state.copyWith(bufferedPosition: buffer);
    }));

    _subscriptions.add(_player!.stream.error.listen((error) {
      if (error.isNotEmpty) {
        debugPrint('[VideoPlayerService] Player error: $error');
      }
    }));

    _subscriptions.add(_player!.stream.completed.listen((completed) {
      if (completed) {
        debugPrint('[VideoPlayerService] Playback completed');
      }
    }));
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  String _formatError(String error) {
    if (error.contains('HTTP 500')) {
      return '服务器转码失败，请稍后重试';
    }
    if (error.contains('HTTP 404')) {
      return '视频文件不存在';
    }
    if (error.contains('timeout') || error.contains('Timeout')) {
      return '连接超时，请检查网络';
    }
    if (error.contains('SAE') || error.contains('handshake')) {
      return '安全握手失败，请重新登录';
    }
    if (error.contains('decrypt') || error.contains('Decrypt')) {
      return '解密失败，密钥可能不匹配';
    }
    return error;
  }

  /// 切换播放/暂停
  Future<void> togglePlayPause() async {
    if (_player == null) return;
    if (state.isPlaying) {
      await _player!.pause();
    } else {
      await _player!.play();
    }
  }

  Future<void> pause() async => await _player?.pause();
  Future<void> resume() async => await _player?.play();

  /// Seek 到指定位置
  Future<void> seekTo(Duration position) async {
    if (_player == null || !state.isInitialized) return;

    final clampedPosition = Duration(
      milliseconds:
          position.inMilliseconds.clamp(0, state.duration.inMilliseconds),
    );

    state = state.copyWith(
      isSeeking: true,
      isBuffering: true,
      position: clampedPosition,
    );

    // Notify proxy to prebuffer around the seek target
    final proxy = _securePlayer?.proxy;
    if (proxy != null) {
      final segmentIndex = clampedPosition.inSeconds ~/ 6;
      proxy.prefetchAroundSegment(segmentIndex);
    }

    try {
      await _player!.seek(clampedPosition);
    } catch (e) {
      debugPrint('[VideoPlayerService] Seek error: $e');
    }

    // Listen for buffering to end, then clear seeking state
    StreamSubscription<bool>? seekBufferSub;
    seekBufferSub = _player!.stream.buffering.listen((buffering) {
      if (!buffering && state.isSeeking) {
        state = state.copyWith(isSeeking: false);
        seekBufferSub?.cancel();
      }
    });

    // Safety timeout: 30 seconds max wait (server may need time to transcode)
    Future.delayed(const Duration(seconds: 30), () {
      if (state.isSeeking) {
        state = state.copyWith(isSeeking: false, isBuffering: false);
        seekBufferSub?.cancel();
      }
    });
  }

  /// 相对 seek
  Future<void> seekRelative(int seconds) async {
    final newPos = state.position + Duration(seconds: seconds);
    await seekTo(newPos);
  }

  /// 进入小窗模式
  void enterPipMode() {
    state = state.copyWith(isPipMode: true, isFullscreen: false);
  }

  /// 退出小窗模式
  void exitPipMode() {
    state = state.copyWith(isPipMode: false);
  }

  /// 进入全屏
  void enterFullscreen() {
    state = state.copyWith(isFullscreen: true, isPipMode: false);
  }

  /// 退出全屏
  void exitFullscreen() {
    state = state.copyWith(isFullscreen: false);
  }

  /// 设置音量
  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume);
    await _player?.setVolume(volume * 100);
  }

  /// 设置播放速度
  Future<void> setSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await _player?.setRate(speed);
  }

  /// 停止播放并清理资源
  Future<void> stop() async {
    _cancelSubscriptions();
    await _player?.stop();
    await _player?.dispose();
    _player = null;
    _videoController = null;

    await _securePlayer?.stop();
    _securePlayer = null;

    state = const VideoPlayerState();
  }

  void _dispose() {
    _cancelSubscriptions();
    _player?.dispose();
    _securePlayer?.stop();
  }
}

final videoPlayerServiceProvider =
    NotifierProvider<VideoPlayerService, VideoPlayerState>(
  VideoPlayerService.new,
);
