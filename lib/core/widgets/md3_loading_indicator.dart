import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

class MD3LoadingIndicator extends StatefulWidget {
  final double size;
  final Color? color;
  final Color? secondaryColor;
  final int pointCount;
  final double innerRadiusRatio;
  final double strokeWidth;
  final bool filled;
  final String? label;
  final Duration rotationDuration;
  final Duration morphDuration;

  const MD3LoadingIndicator({
    super.key,
    this.size = 48,
    this.color,
    this.secondaryColor,
    this.pointCount = 8,
    this.innerRadiusRatio = 0.55,
    this.strokeWidth = 2.5,
    this.filled = false,
    this.label,
    this.rotationDuration = const Duration(milliseconds: 2400),
    this.morphDuration = const Duration(milliseconds: 3200),
  });

  @override
  State<MD3LoadingIndicator> createState() => _MD3LoadingIndicatorState();
}

class _MD3LoadingIndicatorState extends State<MD3LoadingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _rotationController;
  late final AnimationController _morphController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _rotationController = AnimationController(
      vsync: this,
      duration: widget.rotationDuration,
    )..repeat();

    _morphController = AnimationController(
      vsync: this,
      duration: widget.morphDuration,
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _morphController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = widget.color ?? colorScheme.primary;
    final secondaryColor =
        widget.secondaryColor ?? colorScheme.tertiary.withValues(alpha: 0.6);

    Widget indicator = RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _rotationController,
          _morphController,
          _pulseController,
        ]),
        builder: (context, _) {
          final pulse = 1.0 + _pulseController.value * 0.08;
          return Transform.scale(
            scale: pulse,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _StarburstPainter(
                rotation: _rotationController.value * 2 * math.pi,
                morphPhase: _morphController.value,
                pointCount: widget.pointCount,
                innerRadiusRatio: widget.innerRadiusRatio,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                strokeWidth: widget.strokeWidth,
                filled: widget.filled,
              ),
            ),
          );
        },
      ),
    );

    if (widget.label != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(width: 12),
          Text(
            widget.label!,
            style: TextStyle(
              color: primaryColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return indicator;
  }
}

class _StarburstPainter extends CustomPainter {
  final double rotation;
  final double morphPhase;
  final int pointCount;
  final double innerRadiusRatio;
  final Color primaryColor;
  final Color secondaryColor;
  final double strokeWidth;
  final bool filled;

  _StarburstPainter({
    required this.rotation,
    required this.morphPhase,
    required this.pointCount,
    required this.innerRadiusRatio,
    required this.primaryColor,
    required this.secondaryColor,
    required this.strokeWidth,
    required this.filled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - strokeWidth;
    // morphPhase 让凹陷深度动态变化，形成 "呼吸" 效果
    final dynamicInnerRatio =
        innerRadiusRatio + (1.0 - innerRadiusRatio) * 0.3 * morphPhase;
    final innerRadius = outerRadius * dynamicInnerRatio;

    final path = Path();
    final angleStep = math.pi / pointCount;

    for (int i = 0; i < pointCount * 2; i++) {
      final angle = rotation + i * angleStep - math.pi / 2;
      final radius = i.isEven ? outerRadius : innerRadius;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    // 渐变色绘制
    final gradient = SweepGradient(
      center: Alignment.center,
      startAngle: rotation,
      endAngle: rotation + 2 * math.pi,
      colors: [
        primaryColor,
        secondaryColor,
        primaryColor,
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    if (filled) {
      final fillPaint = Paint()
        ..shader = gradient
            .createShader(Rect.fromCircle(center: center, radius: outerRadius))
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
    }

    final strokePaint = Paint()
      ..shader = gradient
          .createShader(Rect.fromCircle(center: center, radius: outerRadius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    // 中心圆点
    final dotRadius = outerRadius * 0.12;
    final dotPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.4 + 0.4 * morphPhase)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, dotRadius, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _StarburstPainter old) =>
      old.rotation != rotation ||
      old.morphPhase != morphPhase ||
      old.primaryColor != primaryColor;
}

// ============================================================================
// 波浪进度条
// ============================================================================

/// 波浪进度条 — Material Design 3 Expressive 风格
///
/// [progress] 0.0 ~ 1.0 表示进度（null 表示不确定进度，循环动画）。
/// [waveAmplitude] 波峰高度（像素），[waveFrequency] 波浪周期数。
class WavyProgressIndicator extends StatefulWidget {
  final double? progress;
  final double height;
  final double waveAmplitude;
  final double waveFrequency;
  final Color? activeColor;
  final Color? trackColor;
  final Duration waveDuration;
  final BorderRadius? borderRadius;

  const WavyProgressIndicator({
    super.key,
    this.progress,
    this.height = 6,
    this.waveAmplitude = 3,
    this.waveFrequency = 2,
    this.activeColor,
    this.trackColor,
    this.waveDuration = const Duration(milliseconds: 1600),
    this.borderRadius,
  });

  @override
  State<WavyProgressIndicator> createState() => _WavyProgressIndicatorState();
}

class _WavyProgressIndicatorState extends State<WavyProgressIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: widget.waveDuration,
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = widget.activeColor ?? colorScheme.primary;
    final trackColor = widget.trackColor ?? colorScheme.surfaceContainerHighest;
    final radius = widget.borderRadius ?? BorderRadius.circular(widget.height);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _waveController,
        builder: (context, _) {
          return ClipRRect(
            borderRadius: radius,
            child: CustomPaint(
              size: Size(
                  double.infinity, widget.height + widget.waveAmplitude * 2),
              painter: _WavyProgressPainter(
                progress: widget.progress,
                wavePhase: _waveController.value * 2 * math.pi,
                waveAmplitude: widget.waveAmplitude,
                waveFrequency: widget.waveFrequency,
                activeColor: activeColor,
                trackColor: trackColor,
                height: widget.height,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WavyProgressPainter extends CustomPainter {
  final double? progress;
  final double wavePhase;
  final double waveAmplitude;
  final double waveFrequency;
  final Color activeColor;
  final Color trackColor;
  final double height;

  _WavyProgressPainter({
    required this.progress,
    required this.wavePhase,
    required this.waveAmplitude,
    required this.waveFrequency,
    required this.activeColor,
    required this.trackColor,
    required this.height,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    // 绘制轨道（灰色波浪线）
    _drawWavyLine(
      canvas,
      size,
      0,
      size.width,
      centerY,
      trackColor,
      waveAmplitude * 0.5,
      wavePhase * 0.3,
      height * 0.8,
    );

    // 绘制活动进度（彩色波浪线）
    final double activeWidth;
    final double activePhase;

    if (progress != null) {
      // 确定进度模式
      activeWidth = size.width * progress!.clamp(0.0, 1.0);
      activePhase = wavePhase;
    } else {
      // 不确定进度：波浪在轨道上来回运动
      final shuttle = (math.sin(wavePhase * 0.5) + 1) / 2;
      final barWidth = size.width * 0.35;
      activeWidth = barWidth;
      final startX = shuttle * (size.width - barWidth);
      _drawWavyLine(
        canvas,
        size,
        startX,
        startX + barWidth,
        centerY,
        activeColor,
        waveAmplitude,
        wavePhase,
        height,
      );
      return;
    }

    if (activeWidth > 0) {
      _drawWavyLine(
        canvas,
        size,
        0,
        activeWidth,
        centerY,
        activeColor,
        waveAmplitude,
        activePhase,
        height,
      );
    }
  }

  void _drawWavyLine(
    Canvas canvas,
    Size size,
    double startX,
    double endX,
    double centerY,
    Color color,
    double amplitude,
    double phase,
    double thickness,
  ) {
    final path = Path();
    final halfThickness = thickness / 2;

    // 上边界（波浪）
    path.moveTo(startX, centerY - halfThickness);
    for (double x = startX; x <= endX; x += 1.0) {
      final t = (x - startX) / (endX - startX == 0 ? 1 : (endX - startX));
      final waveY = amplitude *
          math.sin(phase + t * waveFrequency * 2 * math.pi) *
          _edgeFade(t);
      path.lineTo(x, centerY - halfThickness + waveY);
    }

    // 下边界（反向波浪）
    for (double x = endX; x >= startX; x -= 1.0) {
      final t = (x - startX) / (endX - startX == 0 ? 1 : (endX - startX));
      final waveY = amplitude *
          math.sin(phase + t * waveFrequency * 2 * math.pi) *
          _edgeFade(t);
      path.lineTo(x, centerY + halfThickness + waveY);
    }

    path.close();

    // 渐变填充
    final gradient = LinearGradient(
      colors: [
        color.withValues(alpha: 0.7),
        color,
        color.withValues(alpha: 0.8),
      ],
    ).createShader(Rect.fromLTRB(startX, 0, endX, size.height));

    canvas.drawPath(
      path,
      Paint()
        ..shader = gradient
        ..style = PaintingStyle.fill,
    );
  }

  /// 边缘淡出系数（头尾柔和衰减）
  double _edgeFade(double t) {
    if (t < 0.1) return t / 0.1;
    if (t > 0.9) return (1.0 - t) / 0.1;
    return 1.0;
  }

  @override
  bool shouldRepaint(covariant _WavyProgressPainter old) =>
      old.wavePhase != wavePhase ||
      old.progress != progress ||
      old.activeColor != activeColor;
}

// ============================================================================
// 脉冲点加载指示器
// ============================================================================

/// 三点脉冲加载指示器 — MD3 风格
class MD3PulsingDots extends StatefulWidget {
  final double dotSize;
  final Color? color;
  final int dotCount;

  const MD3PulsingDots({
    super.key,
    this.dotSize = 10,
    this.color,
    this.dotCount = 3,
  });

  @override
  State<MD3PulsingDots> createState() => _MD3PulsingDotsState();
}

class _MD3PulsingDotsState extends State<MD3PulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(widget.dotCount, (i) {
              final delay = i / widget.dotCount;
              final phase = ((_controller.value + delay) % 1.0 * 2 * math.pi);
              final scale = 0.5 + 0.5 * ((math.sin(phase) + 1) / 2);
              final alpha = 0.3 + 0.7 * scale;

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.dotSize * 0.3),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: widget.dotSize,
                    height: widget.dotSize,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: alpha),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ============================================================================
// 分段弧线旋转指示器
// ============================================================================

/// 多段弧线旋转加载指示器 — MD3 Expressive
class MD3SegmentedSpinner extends StatefulWidget {
  final double size;
  final Color? color;
  final double strokeWidth;
  final int segmentCount;

  const MD3SegmentedSpinner({
    super.key,
    this.size = 48,
    this.color,
    this.strokeWidth = 3,
    this.segmentCount = 3,
  });

  @override
  State<MD3SegmentedSpinner> createState() => _MD3SegmentedSpinnerState();
}

class _MD3SegmentedSpinnerState extends State<MD3SegmentedSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _SegmentedSpinnerPainter(
              rotation: _controller.value * 4 * math.pi,
              sweepPhase: _controller.value,
              color: color,
              strokeWidth: widget.strokeWidth,
              segmentCount: widget.segmentCount,
            ),
          );
        },
      ),
    );
  }
}

class _SegmentedSpinnerPainter extends CustomPainter {
  final double rotation;
  final double sweepPhase;
  final Color color;
  final double strokeWidth;
  final int segmentCount;

  _SegmentedSpinnerPainter({
    required this.rotation,
    required this.sweepPhase,
    required this.color,
    required this.strokeWidth,
    required this.segmentCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final gapAngle = math.pi / 12; // gap between segments
    final totalGap = gapAngle * segmentCount;
    final totalSweep = 2 * math.pi - totalGap;
    final segmentSweep = totalSweep / segmentCount;

    for (int i = 0; i < segmentCount; i++) {
      final startAngle = rotation + i * (segmentSweep + gapAngle);
      // 每段弧长度随 phase 波动（呼吸效果）
      final phase = (sweepPhase + i / segmentCount) % 1.0;
      final breathe = 0.6 + 0.4 * math.sin(phase * 2 * math.pi);
      final actualSweep = segmentSweep * breathe;

      final alpha = 0.4 + 0.6 * breathe;
      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, startAngle, actualSweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedSpinnerPainter old) =>
      old.rotation != rotation || old.sweepPhase != sweepPhase;
}

// ============================================================================
// 全屏加载遮罩
// ============================================================================

/// MD3 风格带模糊背景的加载遮罩
class MD3LoadingOverlay extends StatelessWidget {
  final String? message;
  final String? submessage;
  final Widget? indicator;
  final Color? backgroundColor;

  const MD3LoadingOverlay({
    super.key,
    this.message,
    this.submessage,
    this.indicator,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: backgroundColor ?? Colors.black.withValues(alpha: 0.6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              indicator ??
                  MD3LoadingIndicator(
                    size: 56,
                    color: colorScheme.primary,
                    secondaryColor: colorScheme.tertiary,
                  ),
              if (message != null) ...[
                const SizedBox(height: 24),
                Text(
                  message!,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (submessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  submessage!,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 安全连接动画指示器（用于视频/音频播放器的安全握手阶段）
// ============================================================================

/// 安全连接建立动画 — 盾牌 + 波浪 + 状态文字
class SecureConnectionIndicator extends StatefulWidget {
  final String statusText;
  final String? detailText;

  const SecureConnectionIndicator({
    super.key,
    required this.statusText,
    this.detailText,
  });

  @override
  State<SecureConnectionIndicator> createState() =>
      _SecureConnectionIndicatorState();
}

class _SecureConnectionIndicatorState extends State<SecureConnectionIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _shieldPulse;
  late final AnimationController _ringRotation;
  late final AnimationController _fadeIn;

  @override
  void initState() {
    super.initState();
    _shieldPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _ringRotation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _fadeIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _shieldPulse.dispose();
    _ringRotation.dispose();
    _fadeIn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _fadeIn,
        curve: Curves.easeOutCubic,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 动画盾牌
            SizedBox(
              width: 96,
              height: 96,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_shieldPulse, _ringRotation]),
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _SecureShieldPainter(
                        pulsePhase: _shieldPulse.value,
                        ringRotation: _ringRotation.value * 2 * math.pi,
                        primaryColor: Colors.greenAccent,
                        ringColor: colorScheme.primary,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.shield_rounded,
                          size: 36,
                          color: Colors.greenAccent.withValues(
                              alpha: 0.8 + _shieldPulse.value * 0.2),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 28),
            // 波浪进度条
            SizedBox(
              width: 200,
              child: WavyProgressIndicator(
                activeColor: Colors.greenAccent,
                trackColor: Colors.white.withValues(alpha: 0.1),
                waveAmplitude: 2.5,
                waveFrequency: 3,
                height: 4,
              ),
            ),
            const SizedBox(height: 24),
            // 状态文字
            Text(
              widget.statusText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (widget.detailText != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.detailText!,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SecureShieldPainter extends CustomPainter {
  final double pulsePhase;
  final double ringRotation;
  final Color primaryColor;
  final Color ringColor;

  _SecureShieldPainter({
    required this.pulsePhase,
    required this.ringRotation,
    required this.primaryColor,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // 外圈脉冲光环
    final pulseRadius = maxRadius * (0.85 + pulsePhase * 0.15);
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.1 + pulsePhase * 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center, pulseRadius, glowPaint);

    // 旋转虚线环
    final dashRect = Rect.fromCircle(center: center, radius: maxRadius * 0.92);
    const dashCount = 12;
    const dashGap = math.pi / 30;
    final dashSweep = (2 * math.pi - dashCount * dashGap) / dashCount;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = ringRotation + i * (dashSweep + dashGap);
      final alpha = 0.15 + 0.25 * ((math.sin(startAngle * 2) + 1) / 2);
      final arcPaint = Paint()
        ..color = ringColor.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(dashRect, startAngle, dashSweep, false, arcPaint);
    }

    // 内圈实线
    final innerPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.2 + pulsePhase * 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, maxRadius * 0.65, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _SecureShieldPainter old) =>
      old.pulsePhase != pulsePhase || old.ringRotation != ringRotation;
}

// ============================================================================
// 视频/音频缓冲动画
// ============================================================================

/// 优雅的缓冲指示器 — 替代默认 CircularProgressIndicator
class MD3BufferingIndicator extends StatefulWidget {
  final double size;
  final Color? color;
  final String? text;

  const MD3BufferingIndicator({
    super.key,
    this.size = 56,
    this.color,
    this.text,
  });

  @override
  State<MD3BufferingIndicator> createState() => _MD3BufferingIndicatorState();
}

class _MD3BufferingIndicatorState extends State<MD3BufferingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Colors.white;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _BufferingRingPainter(
                    phase: _controller.value,
                    color: color,
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.text != null) ...[
          const SizedBox(height: 12),
          Text(
            widget.text!,
            style: TextStyle(
              color: color.withValues(alpha: 0.8),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _BufferingRingPainter extends CustomPainter {
  final double phase;
  final Color color;

  _BufferingRingPainter({required this.phase, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, bgPaint);

    final sweep = 0.5 + 0.8 * ((math.sin(phase * 2 * math.pi) + 1) / 2);
    final startAngle = phase * 4 * math.pi;

    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweep * math.pi, false, arcPaint);

    final secondArc = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      startAngle + math.pi,
      sweep * math.pi * 0.6,
      false,
      secondArc,
    );
  }

  @override
  bool shouldRepaint(covariant _BufferingRingPainter old) => old.phase != phase;
}
