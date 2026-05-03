import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/download_manager.dart';

class UploadProgressSheet extends ConsumerStatefulWidget {
  const UploadProgressSheet({super.key});

  @override
  ConsumerState<UploadProgressSheet> createState() =>
      _UploadProgressSheetState();
}

class _UploadProgressSheetState extends ConsumerState<UploadProgressSheet>
    with TickerProviderStateMixin {
  late final AnimationController _waveController;
  late final AnimationController _pulseController;
  late final AnimationController _particleController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transportState = ref.watch(downloadManagerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final dedupedUploadsByTarget = <String, UploadTask>{};
    for (final upload in transportState.uploads) {
      final key = '${upload.uploadUrl}|${upload.filePath}';
      final existing = dedupedUploadsByTarget[key];
      if (existing == null || upload.createdAt.isAfter(existing.createdAt)) {
        dedupedUploadsByTarget[key] = upload;
      }
    }

    final allUploads = dedupedUploadsByTarget.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final activeUploads = allUploads
        .where((u) =>
            u.status == DownloadStatus.downloading ||
            u.status == DownloadStatus.pending)
        .toList();
    final completedUploads =
        allUploads.where((u) => u.status == DownloadStatus.completed).toList();
    final failedUploads =
        allUploads.where((u) => u.status == DownloadStatus.failed).toList();

    double overallProgress = 0;
    if (allUploads.isNotEmpty) {
      final total = allUploads.length;
      final done = completedUploads.length;
      final activeProgress =
          activeUploads.fold<double>(0.0, (sum, u) => sum + u.progress);
      overallProgress = (done + activeProgress) / total;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 600;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF0D0D1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isDesktop)
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 8, bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 12),
                _buildHeader(
                    colorScheme, activeUploads.length, overallProgress),
                SizedBox(height: isDesktop ? 8 : 12),
                if (isDesktop) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _WaveProgressBar(
                            progress: overallProgress,
                            color: colorScheme.primary,
                            waveController: _waveController,
                            height: 22,
                          ),
                        ),
                        const SizedBox(width: 16),
                        _StatChip(
                          label: '进行中',
                          count: activeUploads.length,
                          color: Colors.orangeAccent,
                        ),
                        const SizedBox(width: 12),
                        _StatChip(
                          label: '已完成',
                          count: completedUploads.length,
                          color: Colors.greenAccent,
                        ),
                        const SizedBox(width: 12),
                        _StatChip(
                          label: '失败',
                          count: failedUploads.length,
                          color: Colors.redAccent,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildEncryptionPipeline(colorScheme),
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _WaveProgressBar(
                      progress: overallProgress,
                      color: colorScheme.primary,
                      waveController: _waveController,
                      height: 28,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _StatChip(
                          label: '进行中',
                          count: activeUploads.length,
                          color: Colors.orangeAccent,
                        ),
                        _StatChip(
                          label: '已完成',
                          count: completedUploads.length,
                          color: Colors.greenAccent,
                        ),
                        _StatChip(
                          label: '失败',
                          count: failedUploads.length,
                          color: Colors.redAccent,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildEncryptionPipeline(colorScheme),
                  ),
                ],
                SizedBox(height: isDesktop ? 8 : 16),
                Flexible(
                  child: allUploads.isEmpty
                      ? _buildEmptyState(colorScheme)
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: allUploads.length,
                          itemBuilder: (context, index) {
                            return _buildUploadItem(
                                allUploads[index], colorScheme, index);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(
      ColorScheme colorScheme, int activeCount, double progress) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = _pulseController.value;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent
                          .withValues(alpha: 0.2 + pulse * 0.3),
                      blurRadius: 10 + pulse * 8,
                      spreadRadius: pulse * 3,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.cloud_upload_rounded,
                  color: Colors.cyanAccent,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '安全上传',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activeCount > 0
                          ? 'SAE + AES-256-GCM · ${(progress * 100).toInt()}%'
                          : '所有文件已安全上传',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEncryptionPipeline(ColorScheme colorScheme) {
    const steps = [
      _PipeStep(Icons.vpn_key_rounded, 'SAE 握手', Colors.orangeAccent),
      _PipeStep(Icons.lock_rounded, 'AES-256', Colors.cyanAccent),
      _PipeStep(Icons.fingerprint_rounded, 'BLAKE3', Colors.tealAccent),
      _PipeStep(Icons.cloud_upload_rounded, '安全传输', Colors.greenAccent),
    ];

    return AnimatedBuilder(
      animation: _particleController,
      builder: (context, _) {
        final t = _particleController.value;

        return Row(
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          steps[i - 1]
                              .color
                              .withValues(alpha: 0.3 + 0.4 * _flowPulse(t, i)),
                          steps[i]
                              .color
                              .withValues(alpha: 0.3 + 0.4 * _flowPulse(t, i)),
                        ],
                      ),
                    ),
                  ),
                ),
              _PipeStepChip(step: steps[i], pulse: _flowPulse(t, i)),
            ],
          ],
        );
      },
    );
  }

  double _flowPulse(double t, int index) {
    final shifted = (t - index * 0.2) % 1.0;
    return (math.sin(shifted * math.pi * 2) * 0.5 + 0.5).clamp(0.0, 1.0);
  }

  Widget _buildUploadItem(
      UploadTask upload, ColorScheme colorScheme, int index) {
    final isActive = upload.status == DownloadStatus.downloading ||
        upload.status == DownloadStatus.pending;
    final isDone = upload.status == DownloadStatus.completed;
    final isFailed = upload.status == DownloadStatus.failed;

    final statusColor = isDone
        ? Colors.greenAccent
        : isFailed
            ? Colors.redAccent
            : Colors.cyanAccent;

    final statusIcon = isDone
        ? Icons.check_circle_rounded
        : isFailed
            ? Icons.error_rounded
            : Icons.cloud_upload_rounded;

    final speed = upload.uploadSpeed;
    final speedStr = speed > 0 && isActive ? '${_formatBytes(speed)}/s' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      upload.fileName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isDone
                          ? '上传完成'
                          : isFailed
                              ? upload.error ?? '上传失败'
                              : '${(upload.progress * 100).toInt()}%${speedStr.isNotEmpty ? ' · $speedStr' : ''}',
                      style: TextStyle(
                        color: statusColor.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (isActive)
                Text(
                  '${(upload.progress * 100).toInt()}%',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
          if (isActive) ...[
            const SizedBox(height: 8),
            _WaveProgressBar(
              progress: upload.progress,
              color: Colors.cyanAccent,
              waveController: _waveController,
              height: 10,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            const Text(
              '暂无上传任务',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)}MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)}GB';
  }
}

class _WaveProgressBar extends StatelessWidget {
  final double progress;
  final Color color;
  final AnimationController waveController;
  final double height;

  const _WaveProgressBar({
    required this.progress,
    required this.color,
    required this.waveController,
    this.height = 16,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: waveController,
          builder: (context, _) {
            return CustomPaint(
              painter: _WaveProgressPainter(
                progress: progress,
                wavePhase: waveController.value * 2 * math.pi,
                color: color,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WaveProgressPainter extends CustomPainter {
  final double progress;
  final double wavePhase;
  final Color color;

  _WaveProgressPainter({
    required this.progress,
    required this.wavePhase,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(size.height / 2)),
      bgPaint,
    );

    if (progress <= 0) return;

    final fillWidth = size.width * progress.clamp(0.0, 1.0);

    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, fillWidth, size.height),
        Radius.circular(size.height / 2),
      ),
    );

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.8),
          color.withValues(alpha: 0.5),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, fillPaint);

    final wavePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final wavePath = Path();
    wavePath.moveTo(0, size.height);

    for (double x = 0; x <= size.width; x += 1) {
      final y = size.height * 0.5 +
          math.sin(x / size.width * 4 * math.pi + wavePhase) *
              size.height *
              0.18 +
          math.sin(x / size.width * 6 * math.pi + wavePhase * 1.3) *
              size.height *
              0.08;
      wavePath.lineTo(x, y);
    }
    wavePath.lineTo(size.width, size.height);
    wavePath.close();

    canvas.drawPath(wavePath, wavePaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WaveProgressPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.wavePhase != wavePhase;
}

class _PipeStep {
  final IconData icon;
  final String label;
  final Color color;

  const _PipeStep(this.icon, this.label, this.color);
}

class _PipeStepChip extends StatelessWidget {
  final _PipeStep step;
  final double pulse;

  const _PipeStepChip({required this.step, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: step.color.withValues(alpha: 0.08 + pulse * 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: step.color.withValues(alpha: 0.2 + pulse * 0.15),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(step.icon, size: 16, color: step.color),
          const SizedBox(height: 2),
          Text(
            step.label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: step.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label $count',
          style: TextStyle(
            color: color.withValues(alpha: 0.8),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
