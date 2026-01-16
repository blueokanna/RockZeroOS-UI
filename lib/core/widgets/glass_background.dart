import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/wallpaper_service.dart';

/// Aero Glass style background widget with blur effect
class GlassBackground extends ConsumerWidget {
  final Widget child;
  final double blurAmount;
  final double opacity;

  const GlassBackground({
    super.key,
    required this.child,
    this.blurAmount = 20.0,
    this.opacity = 0.7,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backgroundMode = ref.watch(backgroundModeProvider);
    final wallpaperPath = ref.watch(customWallpaperPathProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // If custom wallpaper is set, show it with glass effect
    if (backgroundMode == BackgroundMode.customWallpaper &&
        wallpaperPath != null &&
        wallpaperPath.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Wallpaper image
          Image.file(
            File(wallpaperPath),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildDefaultBackground(colorScheme);
            },
          ),
          // Glass overlay with blur
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blurAmount,
                sigmaY: blurAmount,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: opacity),
                ),
                child: child,
              ),
            ),
          ),
        ],
      );
    }

    // Default background without wallpaper
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surface,
            colorScheme.surface.withValues(alpha: 0.95),
          ],
        ),
      ),
      child: child,
    );
  }

  Widget _buildDefaultBackground(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.3),
            colorScheme.secondaryContainer.withValues(alpha: 0.3),
          ],
        ),
      ),
    );
  }
}

/// Glass card with frosted effect
class GlassCard extends StatelessWidget {
  final Widget child;
  final double blurAmount;
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const GlassCard({
    super.key,
    required this.child,
    this.blurAmount = 10.0,
    this.opacity = 0.6,
    this.borderRadius,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = borderRadius ?? BorderRadius.circular(16);

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blurAmount,
            sigmaY: blurAmount,
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: opacity),
              borderRadius: radius,
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Glass container for pages
class GlassScaffold extends ConsumerWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool extendBodyBehindAppBar;
  final double blurAmount;
  final double opacity;

  const GlassScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.extendBodyBehindAppBar = false,
    this.blurAmount = 15.0,
    this.opacity = 0.75,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backgroundMode = ref.watch(backgroundModeProvider);
    final wallpaperPath = ref.watch(customWallpaperPathProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final hasWallpaper = backgroundMode == BackgroundMode.customWallpaper &&
        wallpaperPath != null &&
        wallpaperPath.isNotEmpty;

    if (!hasWallpaper) {
      return Scaffold(
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        extendBodyBehindAppBar: extendBodyBehindAppBar,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Wallpaper
        Image.file(
          File(wallpaperPath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(color: colorScheme.surface);
          },
        ),
        // Glass overlay
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: blurAmount,
              sigmaY: blurAmount,
            ),
            child: Container(
              color: colorScheme.surface.withValues(alpha: opacity),
            ),
          ),
        ),
        // Scaffold content
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: appBar,
          body: body,
          floatingActionButton: floatingActionButton,
          bottomNavigationBar: bottomNavigationBar,
          extendBodyBehindAppBar: extendBodyBehindAppBar,
        ),
      ],
    );
  }
}
