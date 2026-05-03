import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

class AudioPlayerState {
  final bool isPlaying;
  final bool isBuffering;
  final bool isLooping;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final double volume;
  final double speed;
  final String? currentFileName;
  final String? currentUrl;
  final String? error;
  final bool isInitialized;

  const AudioPlayerState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.isLooping = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.volume = 1.0,
    this.speed = 1.0,
    this.currentFileName,
    this.currentUrl,
    this.error,
    this.isInitialized = false,
  });

  AudioPlayerState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    bool? isLooping,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    double? volume,
    double? speed,
    String? currentFileName,
    String? currentUrl,
    String? error,
    bool? isInitialized,
  }) {
    return AudioPlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isLooping: isLooping ?? this.isLooping,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      currentFileName: currentFileName ?? this.currentFileName,
      currentUrl: currentUrl ?? this.currentUrl,
      error: error,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }

  bool get hasAudio => currentUrl != null && currentUrl!.isNotEmpty;
}

class RockZeroAudioHandler extends BaseAudioHandler with SeekHandler {
  AudioPlayer _player;
  final List<StreamSubscription> _subs = [];

  RockZeroAudioHandler(this._player) {
    _bindPlayer();
  }

  void rebindPlayer(AudioPlayer newPlayer) {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _player = newPlayer;
    _bindPlayer();
  }

  void _bindPlayer() {
    _subs.add(_player.playbackEventStream.listen((event) {
      final playing = _player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: _mapProcessingState(_player.processingState),
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ));
    }));

    _subs.add(_player.durationStream.listen((duration) {
      final item = mediaItem.value;
      if (item != null && duration != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    }));
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
  }
}

RockZeroAudioHandler? _globalAudioHandler;

bool get _supportsAudioService {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
}

Future<RockZeroAudioHandler?> _getOrCreateHandler(AudioPlayer player) async {
  if (!_supportsAudioService) return null;
  if (_globalAudioHandler != null) {
    _globalAudioHandler!.rebindPlayer(player);
    return _globalAudioHandler!;
  }
  try {
    _globalAudioHandler = await AudioService.init(
      builder: () => RockZeroAudioHandler(player),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.rockzero.audio',
        androidNotificationChannelName: 'RockZero Audio',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: false,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );
  } catch (e) {
    debugPrint('[AudioPlayerService] AudioService.init() failed: $e');

    _globalAudioHandler = null;
  }
  return _globalAudioHandler;
}

class AudioPlayerService extends Notifier<AudioPlayerState> {
  AudioPlayer? _audioPlayer;
  RockZeroAudioHandler? _audioHandler;
  String? _authToken;

  final List<StreamSubscription> _subscriptions = [];

  @override
  AudioPlayerState build() {
    ref.onDispose(() {
      _dispose();
    });
    return const AudioPlayerState();
  }

  Future<void> _loadToken() async {
    const storage = FlutterSecureStorage();
    _authToken = await storage.read(key: 'access_token');
  }

  Future<void> play(
    String url,
    String fileName, {
    Duration? startPosition,
    double? startVolume,
    double? startSpeed,
    bool? startLooping,
    bool autoPlay = true,
  }) async {
    if (state.currentUrl == url && _audioPlayer != null) {
      if (startVolume != null) {
        await _audioPlayer!.setVolume(startVolume);
        state = state.copyWith(volume: startVolume);
      }
      if (startSpeed != null) {
        await _audioPlayer!.setSpeed(startSpeed);
        state = state.copyWith(speed: startSpeed);
      }
      if (startLooping != null) {
        await _audioPlayer!
            .setLoopMode(startLooping ? LoopMode.one : LoopMode.off);
        state = state.copyWith(isLooping: startLooping);
      }
      if (startPosition != null && startPosition > Duration.zero) {
        await _seekToWithRetry(startPosition);
      }
      if (autoPlay) {
        await _audioPlayer!.play();
      } else {
        await _audioPlayer!.pause();
      }
      return;
    }

    await stop();

    state = state.copyWith(
      currentUrl: url,
      currentFileName: fileName,
      isBuffering: true,
      error: null,
    );

    try {
      await _loadToken();

      _audioPlayer = AudioPlayer();

      _audioHandler = await _getOrCreateHandler(_audioPlayer!);

      final headers = <String, String>{};
      if (_authToken != null && _authToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_authToken';
      }

      String streamUrl = url;
      try {
        final uri = Uri.parse(url);
        final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';
        String infoPath = '';
        bool foundPlay = false;
        for (final segment in uri.pathSegments) {
          if (foundPlay) infoPath += '/$segment';
          if (segment == 'play' || segment == 'stream') foundPlay = true;
        }
        if (infoPath.isEmpty) {
          infoPath = uri.path.replaceFirst(
            RegExp(r'/api/v1/(streaming|filemanager)/(play|stream)/'),
            '/',
          );
        }
        final infoUrl = '$baseUrl/api/v1/streaming/info$infoPath';

        final response = await http
            .get(Uri.parse(infoUrl), headers: headers)
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          final needsTranscode = json['needs_audio_transcode'] ?? false;
          final transcodeUrl = json['transcode_url'];

          if (needsTranscode && transcodeUrl != null) {
            streamUrl = '$baseUrl$transcodeUrl';
          }
        }
      } catch (e) {
        debugPrint('[AudioPlayerService] Failed to fetch media info: $e');
      }

      await _audioPlayer!
          .setUrl(streamUrl, headers: headers)
          .timeout(const Duration(seconds: 30));

      _audioHandler?.mediaItem.add(MediaItem(
        id: streamUrl,
        title: fileName,
        artist: 'RockZero',
        duration: _audioPlayer!.duration ?? Duration.zero,
      ));

      _setupListeners();

      state = state.copyWith(isInitialized: true);

      if (startVolume != null) {
        await _audioPlayer!.setVolume(startVolume);
        state = state.copyWith(volume: startVolume);
      }

      if (startSpeed != null) {
        await _audioPlayer!.setSpeed(startSpeed);
        state = state.copyWith(speed: startSpeed);
      }

      if (startLooping != null) {
        await _audioPlayer!
            .setLoopMode(startLooping ? LoopMode.one : LoopMode.off);
        state = state.copyWith(isLooping: startLooping);
      }

      if (startPosition != null && startPosition > Duration.zero) {
        await _seekToWithRetry(startPosition);
      }

      if (autoPlay) {
        await _audioPlayer!.play();
      } else {
        await _audioPlayer!.pause();
      }
    } catch (e) {
      state = state.copyWith(
        error: _getErrorMessage(e),
        isBuffering: false,
      );
    }
  }

  void _setupListeners() {
    _cancelSubscriptions();

    _subscriptions.add(_audioPlayer!.playerStateStream.listen((playerState) {
      state = state.copyWith(
        isPlaying: playerState.playing,
        isBuffering: playerState.processingState == ProcessingState.buffering ||
            playerState.processingState == ProcessingState.loading,
      );

      if (playerState.processingState == ProcessingState.completed) {
        if (state.isLooping) {
          _audioPlayer?.seek(Duration.zero);
          _audioPlayer?.play();
        }
      }
    }));

    _subscriptions.add(_audioPlayer!.positionStream.listen((position) {
      state = state.copyWith(position: position);
    }));

    _subscriptions.add(_audioPlayer!.durationStream.listen((duration) {
      if (duration != null) {
        state = state.copyWith(duration: duration);

        final item = _audioHandler?.mediaItem.value;
        if (item != null) {
          _audioHandler?.mediaItem.add(item.copyWith(duration: duration));
        }
      }
    }));

    _subscriptions.add(_audioPlayer!.bufferedPositionStream.listen((buffered) {
      state = state.copyWith(bufferedPosition: buffered);
    }));
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('codec') || errorStr.contains('format')) {
      return '不支持的音频格式';
    }
    if (errorStr.contains('network') ||
        errorStr.contains('connection') ||
        errorStr.contains('timeout')) {
      return '网络错误，请检查连接';
    }
    return '加载音频失败';
  }

  Future<void> togglePlayPause() async {
    if (_audioPlayer == null) return;
    if (state.isPlaying) {
      await _audioPlayer!.pause();
    } else {
      await _audioPlayer!.play();
    }
  }

  Future<void> pause() async {
    await _audioPlayer?.pause();
  }

  Future<void> resume() async {
    await _audioPlayer?.play();
  }

  Future<void> seekTo(Duration position) async {
    if (_audioPlayer == null) return;
    await _audioPlayer!.seek(_clampSeekPosition(position));
  }

  Duration _clampSeekPosition(Duration position) {
    final safePosition = position < Duration.zero ? Duration.zero : position;

    final totalDuration = state.duration;
    if (totalDuration > Duration.zero) {
      return Duration(
        milliseconds:
            safePosition.inMilliseconds.clamp(0, totalDuration.inMilliseconds),
      );
    }

    return safePosition;
  }

  Future<void> _seekToWithRetry(Duration position) async {
    if (_audioPlayer == null) return;

    final target = _clampSeekPosition(position);
    for (int attempt = 0; attempt < 5; attempt++) {
      await _audioPlayer!.seek(target);

      final current = _audioPlayer!.position;
      final deltaMs = (current.inMilliseconds - target.inMilliseconds).abs();
      if (deltaMs <= 1200) {
        return;
      }

      await Future.delayed(Duration(milliseconds: 150 * (attempt + 1)));
    }
  }

  Future<void> seekForward() async {
    final newPos = state.position + const Duration(seconds: 10);
    await seekTo(newPos > state.duration ? state.duration : newPos);
  }

  Future<void> seekBackward() async {
    final newPos = state.position - const Duration(seconds: 10);
    await seekTo(newPos < Duration.zero ? Duration.zero : newPos);
  }

  void toggleLoop() {
    final newLooping = !state.isLooping;
    state = state.copyWith(isLooping: newLooping);
    _audioPlayer?.setLoopMode(newLooping ? LoopMode.one : LoopMode.off);
  }

  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume);
    await _audioPlayer?.setVolume(volume);
  }

  Future<void> setSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await _audioPlayer?.setSpeed(speed);
  }

  Future<void> stop() async {
    _cancelSubscriptions();
    await _audioHandler?.stop();
    await _audioPlayer?.stop();
    await _audioPlayer?.dispose();
    _audioPlayer = null;

    state = const AudioPlayerState();
  }

  void _dispose() {
    _cancelSubscriptions();
    _audioPlayer?.dispose();
    _audioPlayer = null;
  }
}

final audioPlayerServiceProvider =
    NotifierProvider<AudioPlayerService, AudioPlayerState>(
  AudioPlayerService.new,
);
