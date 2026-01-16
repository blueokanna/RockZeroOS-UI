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

/// 背景设置模式
enum BackgroundMode {
  /// 默认 - 从系统取色
  defaultMode,

  /// 自定义壁纸
  customWallpaper,
}

/// 壁纸服务 - 处理背景图片和取色
class WallpaperService {
  static const _channel = MethodChannel('rockzero/wallpaper');

  static bool get isPlatformSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// 获取系统壁纸的主色调
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

  /// 从图片提取主色调 (使用 Flutter 内置方法)
  static Future<Color?> extractDominantColor(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: 100, // 缩小图片加快处理
        targetHeight: 100,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      // 获取像素数据
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;

      final pixels = byteData.buffer.asUint8List();

      // 统计颜色频率
      final colorCounts = <int, int>{};
      for (var i = 0; i < pixels.length; i += 4) {
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        final a = pixels[i + 3];

        // 跳过透明像素和接近白色/黑色的像素
        if (a < 128) continue;
        if ((r > 240 && g > 240 && b > 240) || (r < 15 && g < 15 && b < 15)) {
          continue;
        }

        // 量化颜色以减少变体
        final quantizedR = (r ~/ 32) * 32;
        final quantizedG = (g ~/ 32) * 32;
        final quantizedB = (b ~/ 32) * 32;

        final colorKey = (quantizedR << 16) | (quantizedG << 8) | quantizedB;
        colorCounts[colorKey] = (colorCounts[colorKey] ?? 0) + 1;
      }

      if (colorCounts.isEmpty) return null;

      // 找出最常见的颜色，优先选择饱和度较高的
      int? bestColor;
      double bestScore = 0;

      for (final entry in colorCounts.entries) {
        final r = (entry.key >> 16) & 0xFF;
        final g = (entry.key >> 8) & 0xFF;
        final b = entry.key & 0xFF;

        // 计算饱和度
        final maxC = [r, g, b].reduce((a, b) => a > b ? a : b);
        final minC = [r, g, b].reduce((a, b) => a < b ? a : b);
        final saturation = maxC > 0 ? (maxC - minC) / maxC.toDouble() : 0.0;

        // 分数 = 频率 * (1 + 饱和度)
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

  /// 从图片文件提取主色调
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

  /// 混合两种颜色
  static Color blendColors(Color color1, Color color2, double ratio) {
    final r = (color1.r * ratio + color2.r * (1 - ratio)).round();
    final g = (color1.g * ratio + color2.g * (1 - ratio)).round();
    final b = (color1.b * ratio + color2.b * (1 - ratio)).round();
    return Color.fromARGB(255, r, g, b);
  }
}

/// 背景模式 Provider
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

/// 自定义壁纸路径 Provider
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

  /// 选择并保存壁纸
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

      // 保存到应用目录
      final appDir = await getApplicationDocumentsDirectory();
      final wallpaperDir = Directory('${appDir.path}/wallpapers');
      if (!await wallpaperDir.exists()) {
        await wallpaperDir.create(recursive: true);
      }

      final fileName =
          'custom_wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${wallpaperDir.path}/$fileName';

      // 复制文件
      final bytes = await image.readAsBytes();
      await File(savedPath).writeAsBytes(bytes);

      // 删除旧壁纸
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

  /// 清除自定义壁纸
  Future<void> clearWallpaper() async {
    if (state != null) {
      try {
        await File(state!).delete();
      } catch (_) {}
    }
    await setPath(null);
  }
}

/// 壁纸颜色 Provider - 从壁纸提取的颜色
final wallpaperColorProvider = NotifierProvider<WallpaperColorNotifier, Color?>(
  WallpaperColorNotifier.new,
);

class WallpaperColorNotifier extends Notifier<Color?> {
  @override
  Color? build() {
    _loadColor();
    return null;
  }

  Future<void> _loadColor() async {
    final box = Hive.box('settings');
    final colorValue = box.get('wallpaperColor');
    if (colorValue != null) {
      state = Color(colorValue);
    }
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

  /// 从壁纸文件提取颜色
  Future<void> extractFromWallpaper(String filePath) async {
    final color = await WallpaperService.extractColorFromFile(filePath);
    if (color != null) {
      await setColor(color);
    }
  }
}

/// 混合后的主题色 Provider
/// 默认模式: 70% 系统色 + 30% 壁纸色
/// 自定义壁纸模式: 100% 壁纸色
final blendedThemeColorProvider = Provider<Color?>((ref) {
  final backgroundMode = ref.watch(backgroundModeProvider);
  final wallpaperColor = ref.watch(wallpaperColorProvider);
  final systemColor = ref.watch(systemAccentColorProvider);
  final seedColor = ref.watch(seedColorProvider);

  if (backgroundMode == BackgroundMode.customWallpaper &&
      wallpaperColor != null) {
    // 自定义壁纸模式 - 使用壁纸颜色
    return wallpaperColor;
  }

  if (backgroundMode == BackgroundMode.defaultMode) {
    // 默认模式 - 混合系统色和壁纸色
    final baseColor = systemColor ?? seedColor;

    if (wallpaperColor != null) {
      // 70% 系统色 + 30% 壁纸色
      return WallpaperService.blendColors(baseColor, wallpaperColor, 0.7);
    }

    return baseColor;
  }

  return systemColor ?? seedColor;
});
