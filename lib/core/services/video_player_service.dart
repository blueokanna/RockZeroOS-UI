import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../services/secure_hls_player.dart';

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

  Future<void> playSecureVideo({
    required String baseUrl,
    required String jwtToken,
    required String userId,
    required String password,
    String? fileId,
    String? filePath,
    required String fileName,
  }) async {
    final resolvedTarget =
        (fileId != null && fileId.isNotEmpty) ? fileId : filePath;
    if (resolvedTarget == null || resolvedTarget.isEmpty) {
      throw ArgumentError('Either fileId or filePath must be provided');
    }

    if (state.currentFileId == resolvedTarget &&
        _player != null &&
        state.isInitialized) {
      await _player!.play();
      return;
    }

    await stop();

    state = state.copyWith(
      currentFileId: resolvedTarget,
      currentFileName: fileName,
      isBuffering: true,
      error: null,
      isInitialized: false,
    );

    try {
      _securePlayer = SecureHlsPlayer(
        baseUrl: baseUrl,
        jwtToken: jwtToken,
      );

      await _securePlayer!.initializeSaeHandshake(
        userId,
        password,
        fileId: fileId,
        filePath: filePath,
      );

      final playUrl = _securePlayer!.getDirectPlaylistUrl();
      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 16 * 1024 * 1024,
        ),
      );

      _videoController = VideoController(_player!);

      if (_player!.platform is NativePlayer) {
        final mpv = _player!.platform as NativePlayer;

        await mpv.setProperty('cache', 'no');
        await mpv.setProperty('cache-on-disk', 'no');
        await mpv.setProperty('cache-secs', '0');
        await mpv.setProperty('demuxer-max-bytes', '16MiB');
        await mpv.setProperty('demuxer-readahead-secs', '1');
        await mpv.setProperty('demuxer-max-back-bytes', '2MiB');

        await mpv.setProperty('vd-lavc-threads', '0');
        await mpv.setProperty('ad-lavc-threads', '0');
        await mpv.setProperty('demuxer-thread', 'yes');

        await mpv.setProperty('hwdec', 'auto-safe');
        await mpv.setProperty('hwdec-codecs', 'all');
        await mpv.setProperty('vd-lavc-software-fallback', 'inf');
        await mpv.setProperty('vd-lavc-dr', 'yes');

        await mpv.setProperty('rebase-start-time', 'yes');
        await mpv.setProperty(
          'demuxer-lavf-o',
          'fflags=+genpts+discardcorrupt,live_start_index=0',
        );
        await mpv.setProperty('force-seekable', 'yes');
        await mpv.setProperty(
            'stream-lavf-o', 'reconnect=1,reconnect_streamed=1');

        await mpv.setProperty('video-sync', 'audio');

        await mpv.setProperty('vo', 'gpu');
        await mpv.setProperty('gpu-context', 'auto');
      }

      _setupListeners();
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
      return 'Server transcoding failed, please try again later.';
    }
    if (error.contains('HTTP 404')) {
      return 'Video file not found.';
    }
    if (error.contains('timeout') || error.contains('Timeout')) {
      return 'Connection timed out, please check your network.';
    }
    if (error.contains('SAE') || error.contains('handshake')) {
      return 'Secure handshake failed, please log in again.';
    }
    if (error.contains('decrypt') || error.contains('Decrypt')) {
      return 'Decryption failed, the key may not match.';
    }
    return error;
  }

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

    StreamSubscription<bool>? seekBufferSub;
    seekBufferSub = _player!.stream.buffering.listen((buffering) {
      if (!buffering && state.isSeeking) {
        state = state.copyWith(isSeeking: false);
        seekBufferSub?.cancel();
      }
    });

    Future.delayed(const Duration(seconds: 30), () {
      if (state.isSeeking) {
        state = state.copyWith(isSeeking: false, isBuffering: false);
        seekBufferSub?.cancel();
      }
    });
  }

  Future<void> seekRelative(int seconds) async {
    final newPos = state.position + Duration(seconds: seconds);
    await seekTo(newPos);
  }

  void enterPipMode() {
    state = state.copyWith(isPipMode: true, isFullscreen: false);
  }

  void exitPipMode() {
    state = state.copyWith(isPipMode: false);
  }

  void enterFullscreen() {
    state = state.copyWith(isFullscreen: true, isPipMode: false);
  }

  void exitFullscreen() {
    state = state.copyWith(isFullscreen: false);
  }

  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume);
    await _player?.setVolume(volume * 100);
  }

  Future<void> setSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await _player?.setRate(speed);
  }

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
