import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/video_player_service.dart';

/// 迷你视频播放器 - 浮动小窗，类似网易云音乐的小窗播放
class MiniVideoPlayer extends ConsumerStatefulWidget {
  const MiniVideoPlayer({super.key});

  @override
  ConsumerState<MiniVideoPlayer> createState() => _MiniVideoPlayerState();
}

class _MiniVideoPlayerState extends ConsumerState<MiniVideoPlayer> {
  Offset _position = const Offset(16, 100);
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final videoState = ref.watch(videoPlayerServiceProvider);
    final videoService = ref.read(videoPlayerServiceProvider.notifier);

    if (!videoState.hasVideo || !videoState.isPipMode) {
      return const SizedBox.shrink();
    }

    final controller = videoService.videoController;
    if (controller == null) return const SizedBox.shrink();

    final screenSize = MediaQuery.of(context).size;
    final colorScheme = Theme.of(context).colorScheme;

    // 小窗尺寸：16:9 比例
    const pipWidth = 200.0;
    const pipHeight = 112.0;

    // 确保小窗不超出屏幕
    final clampedX = _position.dx.clamp(0.0, screenSize.width - pipWidth);
    final clampedY = _position.dy.clamp(
      MediaQuery.of(context).padding.top,
      screenSize.height -
          pipHeight -
          MediaQuery.of(context).padding.bottom -
          80,
    );

    return Positioned(
      left: clampedX,
      top: clampedY,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              _position.dx + details.delta.dx,
              _position.dy + details.delta.dy,
            );
          });
        },
        onPanEnd: (_) {
          setState(() => _isDragging = false);
          // 吸附到最近的边缘
          _snapToEdge(screenSize, pipWidth);
        },
        child: AnimatedScale(
          scale: _isDragging ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            shadowColor: Colors.black54,
            child: Container(
              width: pipWidth,
              height: pipHeight + 40, // 额外空间给控制栏
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  // 视频画面
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    child: SizedBox(
                      width: pipWidth,
                      height: pipHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Video(
                            controller: controller,
                            controls: NoVideoControls,
                          ),
                          // 缓冲指示器
                          if (videoState.isBuffering)
                            Container(
                              color: Colors.black38,
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          // 点击展开全屏
                          Positioned.fill(
                            child: GestureDetector(
                              onTap: () {
                                videoService.exitPipMode();
                                videoService.enterFullscreen();
                              },
                              child: Container(color: Colors.transparent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 控制栏
                  SizedBox(
                    height: 40,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          // 文件名
                          Expanded(
                            child: Text(
                              videoState.currentFileName ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 播放/暂停
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 20,
                              icon: Icon(
                                videoState.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: colorScheme.primary,
                              ),
                              onPressed: () => videoService.togglePlayPause(),
                            ),
                          ),
                          // 关闭
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 18,
                              icon: Icon(
                                Icons.close_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              onPressed: () => videoService.stop(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _snapToEdge(Size screenSize, double pipWidth) {
    final centerX = _position.dx + pipWidth / 2;
    final targetX = centerX < screenSize.width / 2
        ? 8.0
        : screenSize.width - pipWidth - 8.0;

    setState(() {
      _position = Offset(targetX, _position.dy);
    });
  }
}
