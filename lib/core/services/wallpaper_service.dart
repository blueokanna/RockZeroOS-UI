import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/app_theme.dart';

enum BackgroundMode {
  defaultMode,
  customWallpaper,
}

class WallpaperService {
  static const _channel = MethodChannel('rockzero/wallpaper');

  static bool get isPlatformSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  static Future<Color?> getSystemWallpaperColor() async {
    if (!isPlatformSupported) return null;

    try {
      final int? colorValue = await _channel.invokeMethod('getWallpaperColor');
      if (colorValue != null) {
        return Color(colorValue);
      }
    } on PlatformException catch (e) {
      debugPrint('Get wallpaper color failed: ${e.message}');
    } catch (e) {
      debugPrint('Get wallpaper color failed: $e');
    }
    return null;
  }

  static Future<Color?> extractDominantColor(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: 100,
        targetHeight: 100,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;

      final pixels = byteData.buffer.asUint8List();

      final colorCounts = <int, int>{};
      for (var i = 0; i < pixels.length; i += 4) {
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        final a = pixels[i + 3];

        if (a < 128) continue;
        if ((r > 240 && g > 240 && b > 240) || (r < 15 && g < 15 && b < 15)) {
          continue;
        }

        final quantizedR = (r ~/ 32) * 32;
        final quantizedG = (g ~/ 32) * 32;
        final quantizedB = (b ~/ 32) * 32;

        final colorKey = (quantizedR << 16) | (quantizedG << 8) | quantizedB;
        colorCounts[colorKey] = (colorCounts[colorKey] ?? 0) + 1;
      }

      if (colorCounts.isEmpty) return null;

      int? bestColor;
      double bestScore = 0;

      for (final entry in colorCounts.entries) {
        final r = (entry.key >> 16) & 0xFF;
        final g = (entry.key >> 8) & 0xFF;
        final b = entry.key & 0xFF;

        final maxC = [r, g, b].reduce((a, b) => a > b ? a : b);
        final minC = [r, g, b].reduce((a, b) => a < b ? a : b);
        final saturation = maxC > 0 ? (maxC - minC) / maxC.toDouble() : 0.0;

        final score = entry.value * (1 + saturation);

        if (score > bestScore) {
          bestScore = score;
          bestColor = entry.key;
        }
      }

      if (bestColor == null) return null;

      return Color.fromARGB(
        255,
        (bestColor >> 16) & 0xFF,
        (bestColor >> 8) & 0xFF,
        bestColor & 0xFF,
      );
    } catch (e) {
      debugPrint('Extract color failed: $e');
      return null;
    }
  }

  static Future<Color?> extractColorFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      return extractDominantColor(bytes);
    } catch (e) {
      debugPrint('Extract color from file failed: $e');
      return null;
    }
  }

  static Color blendColors(Color color1, Color color2, double ratio) {
    final r = (color1.r * ratio + color2.r * (1 - ratio)).round();
    final g = (color1.g * ratio + color2.g * (1 - ratio)).round();
    final b = (color1.b * ratio + color2.b * (1 - ratio)).round();
    return Color.fromARGB(255, r, g, b);
  }
}

final backgroundModeProvider =
    NotifierProvider<BackgroundModeNotifier, BackgroundMode>(
  BackgroundModeNotifier.new,
);

class BackgroundModeNotifier extends Notifier<BackgroundMode> {
  @override
  BackgroundMode build() {
    final box = Hive.box('settings');
    final mode = box.get('backgroundMode', defaultValue: 'default');
    return mode == 'custom'
        ? BackgroundMode.customWallpaper
        : BackgroundMode.defaultMode;
  }

  Future<void> setMode(BackgroundMode mode) async {
    state = mode;
    final box = Hive.box('settings');
    await box.put('backgroundMode',
        mode == BackgroundMode.customWallpaper ? 'custom' : 'default');
  }
}

final customWallpaperPathProvider =
    NotifierProvider<CustomWallpaperPathNotifier, String?>(
  CustomWallpaperPathNotifier.new,
);

class CustomWallpaperPathNotifier extends Notifier<String?> {
  @override
  String? build() {
    final box = Hive.box('settings');
    return box.get('customWallpaperPath');
  }

  Future<void> setPath(String? path) async {
    state = path;
    final box = Hive.box('settings');
    if (path != null) {
      await box.put('customWallpaperPath', path);
    } else {
      await box.delete('customWallpaperPath');
    }
  }

  Future<String?> pickAndSaveWallpaper() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return null;

      final appDir = await getApplicationDocumentsDirectory();
      final wallpaperDir = Directory('${appDir.path}/wallpapers');
      if (!await wallpaperDir.exists()) {
        await wallpaperDir.create(recursive: true);
      }

      final fileName =
          'custom_wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${wallpaperDir.path}/$fileName';

      final bytes = await image.readAsBytes();
      await File(savedPath).writeAsBytes(bytes);

      if (state != null && state != savedPath) {
        try {
          await File(state!).delete();
        } catch (_) {}
      }

      await setPath(savedPath);
      return savedPath;
    } catch (e) {
      debugPrint('Pick wallpaper failed: $e');
      return null;
    }
  }

  Future<void> clearWallpaper() async {
    if (state != null) {
      try {
        await File(state!).delete();
      } catch (_) {}
    }
    await setPath(null);
  }
}

final wallpaperColorProvider = NotifierProvider<WallpaperColorNotifier, Color?>(
  WallpaperColorNotifier.new,
);

class WallpaperColorNotifier extends Notifier<Color?> {
  @override
  Color? build() {
    final box = Hive.box('settings');
    final colorValue = box.get('wallpaperColor');
    if (colorValue != null) {
      return Color(colorValue);
    }
    return null;
  }

  Future<void> setColor(Color? color) async {
    state = color;
    final box = Hive.box('settings');
    if (color != null) {
      await box.put('wallpaperColor', color.toARGB32());
    } else {
      await box.delete('wallpaperColor');
    }
  }

  Future<void> extractFromWallpaper(String filePath) async {
    final color = await WallpaperService.extractColorFromFile(filePath);
    if (color != null) {
      await setColor(color);

      ref.invalidate(blendedThemeColorProvider);
    }
  }
}

final wallpaperBlurAmountProvider =
    NotifierProvider<WallpaperBlurAmountNotifier, double>(
  WallpaperBlurAmountNotifier.new,
);

class WallpaperBlurAmountNotifier extends Notifier<double> {
  @override
  double build() {
    final box = Hive.box('settings');
    return box.get('wallpaperBlurAmount', defaultValue: 25.0) as double;
  }

  Future<void> setBlurAmount(double amount) async {
    state = amount;
    final box = Hive.box('settings');
    await box.put('wallpaperBlurAmount', amount);
  }
}

final blendedThemeColorProvider = Provider<Color?>((ref) {
  final backgroundMode = ref.watch(backgroundModeProvider);
  final wallpaperColor = ref.watch(wallpaperColorProvider);
  final systemColor = ref.watch(systemAccentColorProvider);

  if (backgroundMode == BackgroundMode.customWallpaper) {
    if (wallpaperColor != null && systemColor != null) {
      return WallpaperService.blendColors(wallpaperColor, systemColor, 0.8);
    } else if (wallpaperColor != null) {
      return wallpaperColor;
    } else if (systemColor != null) {
      return systemColor;
    }
  }

  return null;
});
