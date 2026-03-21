import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/wallpaper_service.dart';

/// 壁纸背景组件 - 支持自定义壁纸和 Material You 动态配色
class WallpaperBackground extends ConsumerWidget {
  final Widget child;
  final double opacity;
  final BlendMode blendMode;

  const WallpaperBackground({
    super.key,
    required this.child,
    this.opacity = 0.85,
    this.blendMode = BlendMode.srcOver,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backgroundMode = ref.watch(backgroundModeProvider);
    final wallpaperPath = ref.watch(customWallpaperPathProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 基础背景色
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.surface,
                colorScheme.surfaceContainerLow,
              ],
            ),
          ),
        ),

        // 壁纸层
        if (backgroundMode == BackgroundMode.customWallpaper &&
            wallpaperPath != null)
          _WallpaperLayer(
            imagePath: wallpaperPath,
            opacity: opacity,
            blendMode: blendMode,
          ),

        // Material You 渐变层
        if (backgroundMode == BackgroundMode.customWallpaper)
          _MaterialYouGradient(opacity: opacity * 0.5),

        // 内容层
        child,
      ],
    );
  }
}

/// 壁纸图层
class _WallpaperLayer extends StatelessWidget {
  final String imagePath;
  final double opacity;
  final BlendMode blendMode;

  const _WallpaperLayer({
    required this.imagePath,
    required this.opacity,
    required this.blendMode,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('❌ Failed to load wallpaper: $error');
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

/// Material You 渐变层
class _MaterialYouGradient extends ConsumerWidget {
  final double opacity;

  const _MaterialYouGradient({required this.opacity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallpaperColor = ref.watch(wallpaperColorProvider);
    final colorScheme = Theme.of(context).colorScheme;

    if (wallpaperColor == null) {
      return const SizedBox.shrink();
    }

    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.5,
            colors: [
              wallpaperColor.withValues(alpha: 0.3),
              colorScheme.primary.withValues(alpha: 0.2),
              Colors.transparent,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

/// 毛玻璃效果背景
class GlassmorphicBackground extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final Color? color;
  final BorderRadius? borderRadius;

  const GlassmorphicBackground({
    super.key,
    required this.child,
    this.blur = 20.0,
    this.opacity = 0.15,
    this.color,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = color ?? (isDark ? Colors.black : Colors.white);
    final br = borderRadius ?? BorderRadius.circular(20);

    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor.withValues(alpha: opacity),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : colorScheme.outline.withValues(alpha: 0.15),
              width: 0.5,
            ),
            borderRadius: br,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 动态颜色卡片 - 根据壁纸颜色自动调整
/// 壁纸模式下使用毛玻璃效果（高对比度模糊透明背景）
/// 默认模式下使用普通 Card 样式
class DynamicColorCard extends ConsumerWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? elevation;
  final BorderRadius? borderRadius;
  final double blurAmount;

  const DynamicColorCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.elevation,
    this.borderRadius,
    this.blurAmount = 20.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundMode = ref.watch(backgroundModeProvider);
    final blendedColor = ref.watch(blendedThemeColorProvider);
    final br = borderRadius ?? BorderRadius.circular(20);
    final isWallpaperMode = backgroundMode == BackgroundMode.customWallpaper;

    if (isWallpaperMode) {
      // 壁纸模式 — 毛玻璃效果：透明背景 + 高对比度模糊
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final baseColor = isDark
          ? Colors.black.withValues(alpha: 0.35)
          : Colors.white.withValues(alpha: 0.45);
      final borderColor = isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.08);

      return Padding(
        padding: margin ?? EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: br,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: blurAmount,
              sigmaY: blurAmount,
            ),
            child: Container(
              padding: padding ?? const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: br,
                border: Border.all(color: borderColor, width: 0.5),
                gradient: blendedColor != null
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          baseColor,
                          blendedColor.withValues(alpha: isDark ? 0.08 : 0.06),
                        ],
                      )
                    : null,
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    // 默认模式 — 普通 Card 样式
    return Card(
      margin: margin,
      elevation: elevation,
      shape: RoundedRectangleBorder(borderRadius: br),
      child: Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: br,
          gradient: blendedColor != null
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.surface,
                    blendedColor.withValues(alpha: 0.05),
                  ],
                )
              : null,
        ),
        child: child,
      ),
    );
  }
}

/// 壁纸预览组件
class WallpaperPreview extends StatelessWidget {
  final String imagePath;
  final VoidCallback? onTap;
  final bool selected;

  const WallpaperPreview({
    super.key,
    required this.imagePath,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outline,
            width: selected ? 3 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: colorScheme.errorContainer,
                    child: Icon(
                      Icons.broken_image_rounded,
                      color: colorScheme.onErrorContainer,
                      size: 48,
                    ),
                  );
                },
              ),
              if (selected)
                Container(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  child: Center(
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: colorScheme.onPrimary,
                      size: 48,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
