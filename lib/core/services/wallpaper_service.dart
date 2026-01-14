import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:palette_generator/palette_generator.dart';

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

  /// 从图片提取主色调
  static Future<Color?> extractDominantColor(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final paletteGenerator = await PaletteGenerator.fromImage(
        image,
        maximumColorCount: 16,
      );

      // 优先使用 vibrant 颜色，其次是 dominant
      return paletteGenerator.vibrantColor?.color ??
          paletteGenerator.dominantColor?.color;
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
