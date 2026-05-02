import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/wallpaper_service.dart';

class GlassmorphicBackground extends ConsumerWidget {
  final Widget child;
  final double blurSigma;
  final double opacity;

  const GlassmorphicBackground({
    super.key,
    required this.child,
    this.blurSigma = 10.0,
    this.opacity = 0.3,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backgroundMode = ref.watch(backgroundModeProvider);
    final customWallpaperPath = ref.watch(customWallpaperPathProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // 背景层
        Positioned.fill(
          child: _buildBackground(
            backgroundMode,
            customWallpaperPath,
            colorScheme,
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: Container(
              color: colorScheme.surface.withValues(alpha: opacity),
            ),
          ),
        ),
        child,
      ],
    );
  }

  Widget _buildBackground(
    BackgroundMode mode,
    String? wallpaperPath,
    ColorScheme colorScheme,
  ) {
    if (mode == BackgroundMode.customWallpaper && wallpaperPath != null) {
      // 自定义壁纸模式
      return Image.file(
        File(wallpaperPath),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildGradientBackground(colorScheme);
        },
      );
    }

    // 默认模式 - 使用渐变背景
    return _buildGradientBackground(colorScheme);
  }

  Widget _buildGradientBackground(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer,
            colorScheme.tertiaryContainer,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

/// 简化版毛玻璃卡片
class GlassmorphicCard extends StatelessWidget {
  final Widget child;
  final double blurSigma;
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const GlassmorphicCard({
    super.key,
    required this.child,
    this.blurSigma = 10.0,
    this.opacity = 0.2,
    this.borderRadius,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(20);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: effectiveBorderRadius,
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: opacity),
              borderRadius: effectiveBorderRadius,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
