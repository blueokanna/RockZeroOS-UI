import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class UploadProgressWidget extends StatefulWidget {
  final String filename;
  final int totalBytes;
  final int uploadedBytes;
  final double speedMbps;
  final VoidCallback? onCancel;

  const UploadProgressWidget({
    super.key,
    required this.filename,
    required this.totalBytes,
    required this.uploadedBytes,
    required this.speedMbps,
    this.onCancel,
  });

  @override
  State<UploadProgressWidget> createState() => _UploadProgressWidgetState();
}

class _UploadProgressWidgetState extends State<UploadProgressWidget>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _animationController;
  Timer? _scrollTimer;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // 如果文件名过长，启动滚动
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScrollingIfNeeded();
    });
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _startScrollingIfNeeded() {
    // 检查文本是否溢出
    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.filename,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);

    // 如果文本宽度超过容器宽度，启动滚动
    if (textPainter.width > 200) {
      _isScrolling = true;
      _startAutoScroll();
    }
  }

  void _startAutoScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 3000), (timer) {
      if (!mounted || !_isScrolling) {
        timer.cancel();
        return;
      }

      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;

      if (currentScroll < maxScroll) {
        // 向右滚动
        _scrollController.animateTo(
          maxScroll,
          duration: const Duration(milliseconds: 2000),
          curve: Curves.easeInOut,
        );
      } else {
        // 回到开始
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 2000),
              curve: Curves.easeInOut,
            );
          }
        });
      }
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatSpeed(double mbps) {
    if (mbps < 1) {
      return '${(mbps * 1000).toStringAsFixed(0)} Kbps';
    }
    return '${mbps.toStringAsFixed(2)} Mbps';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final percentage =
        (widget.uploadedBytes / widget.totalBytes * 100).clamp(0, 100);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 文件名（滚动显示）
          Row(
            children: [
              Icon(
                Icons.cloud_upload_rounded,
                color: colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 24,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      widget.filename,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
              if (widget.onCancel != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 20,
                  onPressed: widget.onCancel,
                  tooltip: 'Cancel upload',
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // 进度条
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: percentage / 100),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 统计信息
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 进度百分比
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),

              // 上传速度
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.speed_rounded,
                      size: 16,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatSpeed(widget.speedMbps),
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),

              // 文件大小
              Text(
                '${_formatBytes(widget.uploadedBytes)} / ${_formatBytes(widget.totalBytes)}',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, end: 0);
  }
}

/// 多文件上传进度列表
class UploadProgressList extends StatelessWidget {
  final List<UploadProgressData> uploads;
  final Function(String)? onCancelUpload;

  const UploadProgressList({
    super.key,
    required this.uploads,
    this.onCancelUpload,
  });

  @override
  Widget build(BuildContext context) {
    if (uploads.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: uploads.map((upload) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: UploadProgressWidget(
              filename: upload.filename,
              totalBytes: upload.totalBytes,
              uploadedBytes: upload.uploadedBytes,
              speedMbps: upload.speedMbps,
              onCancel: onCancelUpload != null
                  ? () => onCancelUpload!(upload.id)
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 上传进度数据模型
class UploadProgressData {
  final String id;
  final String filename;
  final int totalBytes;
  final int uploadedBytes;
  final double speedMbps;

  UploadProgressData({
    required this.id,
    required this.filename,
    required this.totalBytes,
    required this.uploadedBytes,
    required this.speedMbps,
  });

  double get percentage => (uploadedBytes / totalBytes * 100).clamp(0, 100);
}
