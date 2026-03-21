import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/services/video_player_service.dart';

class SecureVideoPlayerScreen extends ConsumerStatefulWidget {
  final String fileId;
  final String fileName;
  final String jwtToken;
  final String userId;
  final String password;
  final String baseUrl;

  const SecureVideoPlayerScreen({
    super.key,
    required this.fileId,
    required this.fileName,
    required this.jwtToken,
    required this.userId,
    required this.password,
    required this.baseUrl,
  });

  @override
  ConsumerState<SecureVideoPlayerScreen> createState() =>
      _SecureVideoPlayerScreenState();
}

class _SecureVideoPlayerScreenState
    extends ConsumerState<SecureVideoPlayerScreen> {
  bool _showControls = true;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
    _initializePlayer();
  }

  void _enterFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _initializePlayer() async {
    if (_isDisposed) return;

    final service = ref.read(videoPlayerServiceProvider.notifier);
    await service.playSecureVideo(
      baseUrl: widget.baseUrl,
      jwtToken: widget.jwtToken,
      userId: widget.userId,
      password: widget.password,
      fileId: widget.fileId,
      fileName: widget.fileName,
    );

    // 标记为全屏模式
    service.enterFullscreen();
  }

  @override
  void dispose() {
    _isDisposed = true;
    // 不停止播放器 - 让它继续在小窗模式播放
    final service = ref.read(videoPlayerServiceProvider.notifier);
    service.exitFullscreen();
    _exitFullscreen();
    super.dispose();
  }

  void _togglePlayPause() {
    ref.read(videoPlayerServiceProvider.notifier).togglePlayPause();
  }

  void _seekTo(Duration position) {
    ref.read(videoPlayerServiceProvider.notifier).seekTo(position);
  }

  void _seekRelative(int seconds) {
    ref.read(videoPlayerServiceProvider.notifier).seekRelative(seconds);
  }

  /// 进入小窗模式并返回上一页
  void _enterPipAndGoBack() {
    final service = ref.read(videoPlayerServiceProvider.notifier);
    service.enterPipMode();
    _exitFullscreen();
    Navigator.pop(context);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final videoState = ref.watch(videoPlayerServiceProvider);
    final service = ref.read(videoPlayerServiceProvider.notifier);
    final controller = service.videoController;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(videoState, controller),
    );
  }

  Widget _buildBody(VideoPlayerState videoState, VideoController? controller) {
    if (!videoState.isInitialized && videoState.error == null) {
      return _buildInitializingView();
    }

    if (videoState.error != null) {
      return _buildErrorView(videoState.error!);
    }

    if (controller == null) {
      return _buildInitializingView();
    }

    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: controller,
            controls: NoVideoControls,
          ),
          if (videoState.isBuffering || videoState.isSeeking)
            _buildBufferingIndicator(videoState),
          if (_showControls && videoState.isInitialized)
            _buildControls(videoState),
          if (_showControls) _buildTopBar(videoState),
        ],
      ),
    );
  }

  Widget _buildInitializingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: Colors.green,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '正在建立安全连接...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'SAE 握手 + ChaCha20-Poly1305 加密',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 32),
          TextButton.icon(
            onPressed: () {
              _exitFullscreen();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('取消'),
            style: TextButton.styleFrom(foregroundColor: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildBufferingIndicator(VideoPlayerState videoState) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              videoState.isSeeking ? '跳转中...' : '缓冲中...',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline,
                  size: 48, color: Colors.orange),
            ),
            const SizedBox(height: 24),
            const Text(
              '播放失败',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                error,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    _exitFullscreen();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('返回'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade400,
                    side: BorderSide(color: Colors.grey.shade600),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: () {
                    _initializePlayer();
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重试'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(VideoPlayerState videoState) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: _enterPipAndGoBack,
                ),
                Expanded(
                  child: Text(
                    widget.fileName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 小窗模式按钮
                IconButton(
                  icon: const Icon(Icons.picture_in_picture_alt,
                      color: Colors.white),
                  tooltip: '小窗播放',
                  onPressed: _enterPipAndGoBack,
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withAlpha(51),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withAlpha(102)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, color: Colors.green, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'ChaCha20-Poly1305',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(VideoPlayerState videoState) {
    final progress = videoState.duration.inMilliseconds > 0
        ? videoState.position.inMilliseconds /
            videoState.duration.inMilliseconds
        : 0.0;

    final bufferedProgress = videoState.duration.inMilliseconds > 0
        ? videoState.bufferedPosition.inMilliseconds /
            videoState.duration.inMilliseconds
        : 0.0;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10,
                        color: Colors.white, size: 36),
                    onPressed: () => _seekRelative(-10),
                  ),
                  const SizedBox(width: 32),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(26),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        videoState.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 48,
                      ),
                      onPressed: _togglePlayPause,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(width: 32),
                  IconButton(
                    icon: const Icon(Icons.forward_10,
                        color: Colors.white, size: 36),
                    onPressed: () => _seekRelative(10),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 进度条
              Stack(
                children: [
                  // 缓冲进度
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: SliderComponentShape.noThumb,
                      activeTrackColor: Colors.white24,
                      inactiveTrackColor: Colors.white10,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: bufferedProgress.clamp(0.0, 1.0),
                      onChanged: null,
                    ),
                  ),
                  // 播放进度（可拖动）
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: Colors.green,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: Colors.green,
                      overlayColor: Colors.green.withAlpha(51),
                    ),
                    child: Slider(
                      value: progress.clamp(0.0, 1.0),
                      onChanged: (value) {
                        final newPosition = Duration(
                          milliseconds:
                              (value * videoState.duration.inMilliseconds)
                                  .round(),
                        );
                        _seekTo(newPosition);
                      },
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(videoState.position),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      _formatDuration(videoState.duration),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
