import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

// Theme mode provider (Riverpod 3.x Notifier API)
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final box = Hive.box('settings');
    final mode = box.get('themeMode', defaultValue: 'system');
    return switch (mode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    final box = Hive.box('settings');
    box.put('themeMode', mode.name);
  }
}

// Seed color provider for dynamic theming
final seedColorProvider =
    NotifierProvider<SeedColorNotifier, Color>(SeedColorNotifier.new);

class SeedColorNotifier extends Notifier<Color> {
  @override
  Color build() {
    final box = Hive.box('settings');
    final colorValue = box.get('seedColor', defaultValue: 0xFF6750A4);
    return Color(colorValue);
  }

  void setSeedColor(Color color) {
    state = color;
    final box = Hive.box('settings');
    box.put('seedColor', color.toARGB32());
  }
}

final dynamicColorEnabledProvider =
    NotifierProvider<DynamicColorNotifier, bool>(DynamicColorNotifier.new);

class DynamicColorNotifier extends Notifier<bool> {
  @override
  bool build() {
    final box = Hive.box('settings');
    return box.get('dynamicColorEnabled', defaultValue: false);
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      final available = await DynamicColorService.isDynamicColorAvailable();
      if (!available) {
        return;
      }
      final systemColor = await DynamicColorService.getAccentColor();
      if (systemColor != null) {
        ref.read(systemAccentColorProvider.notifier).setColor(systemColor);
      }
    }
    state = enabled;
    final box = Hive.box('settings');
    await box.put('dynamicColorEnabled', enabled);
  }
}

final systemAccentColorProvider =
    NotifierProvider<SystemAccentColorNotifier, Color?>(
        SystemAccentColorNotifier.new);

class SystemAccentColorNotifier extends Notifier<Color?> {
  @override
  Color? build() {
    _fetchSystemColor();
    return null;
  }

  Future<void> _fetchSystemColor() async {
    final color = await DynamicColorService.getAccentColor();
    if (color != null) {
      state = color;
    }
  }

  void setColor(Color? color) {
    state = color;
  }

  Future<void> refresh() async {
    await _fetchSystemColor();
  }
}

// Dynamic Color Service - handles platform communication
class DynamicColorService {
  static const _channel = MethodChannel('rockzero/system_colors');

  static bool get isPlatformSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  static Future<bool> isDynamicColorAvailable() async {
    if (!isPlatformSupported) return false;

    try {
      final result =
          await _channel.invokeMethod<bool>('isDynamicColorAvailable');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Dynamic color availability check failed: ${e.message}');
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<Color?> getAccentColor() async {
    if (!isPlatformSupported) return null;

    try {
      final int? colorValue = await _channel.invokeMethod('getAccentColor');
      if (colorValue != null) {
        return Color(colorValue);
      }
    } on PlatformException catch (e) {
      debugPrint('Get accent color failed: ${e.message}');
    } catch (e) {
      debugPrint('Get accent color failed: $e');
    }
    return null;
  }

  static Future<Map<String, Color>?> getSystemColors() async {
    if (!isPlatformSupported) return null;

    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getSystemColors');
      if (result != null) {
        return result
            .map((key, value) => MapEntry(key.toString(), Color(value as int)));
      }
    } on PlatformException catch (e) {
      debugPrint('Get system colors failed: ${e.message}');
    } catch (e) {
      debugPrint('Get system colors failed: $e');
    }
    return null;
  }
}

class AppTheme {
  AppTheme._();

  // Material Design 3 预设颜色
  static const List<Color> presetColors = [
    Color(0xFF6750A4), // Material Purple (默认)
    Color(0xFF006C4C), // Green
    Color(0xFF0061A4), // Blue
    Color(0xFF9C4234), // Red
    Color(0xFF7D5260), // Pink
    Color(0xFF006874), // Teal
    Color(0xFF6B5778), // Violet
    Color(0xFF855318), // Orange
    Color(0xFF4A6267), // Slate
  ];

  static ThemeData light(Color seedColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    return _buildTheme(colorScheme);
  }

  static ThemeData dark(Color seedColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    return _buildTheme(colorScheme);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    final textTheme = GoogleFonts.interTextTheme().apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: colorScheme.surfaceTint,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: colorScheme.surfaceContainerLow,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 80,
        indicatorColor: colorScheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        indicatorColor: colorScheme.secondaryContainer,
        selectedIconTheme:
            IconThemeData(color: colorScheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      drawerTheme: DrawerThemeData(
        elevation: 0,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
      ),
      dialogTheme: DialogThemeData(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 1,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        dragHandleColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      ),
      chipTheme: ChipThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        highlightElevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: colorScheme.surfaceContainerHighest,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return colorScheme.outline;
        }),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

// Material Design 3 Expressive 动画曲线
class M3Curves {
  M3Curves._();

  // 标准缓动 - 用于大多数动画
  static const Curve standard = Curves.easeInOutCubicEmphasized;

  // 强调缓动 - 用于需要强调的动画
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  // 强调减速 - 用于进入动画
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

  // 强调加速 - 用于退出动画
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  // 标准减速 - 用于简单进入
  static const Curve standardDecelerate = Cubic(0.0, 0.0, 0.0, 1.0);

  // 标准加速 - 用于简单退出
  static const Curve standardAccelerate = Cubic(0.3, 0.0, 1.0, 1.0);

  // 弹性曲线 - 用于有趣的交互 (M3 Expressive)
  static const Curve expressive = Cubic(0.0, 0.0, 0.0, 1.0);

  // 弹跳效果 - 用于强调性动画
  static const Curve bounce = Curves.elasticOut;

  // 快速出慢速入 - 用于列表项动画
  static const Curve fastOutSlowIn = Curves.fastOutSlowIn;

  // 容器变换曲线
  static const Curve containerTransform = Cubic(0.05, 0.7, 0.1, 1.0);
}

// Material Design 3 动画时长
class M3Durations {
  M3Durations._();

  // 短动画 - 简单状态变化
  static const Duration short1 = Duration(milliseconds: 50);
  static const Duration short2 = Duration(milliseconds: 100);
  static const Duration short3 = Duration(milliseconds: 150);
  static const Duration short4 = Duration(milliseconds: 200);

  // 中等动画 - 复杂状态变化
  static const Duration medium1 = Duration(milliseconds: 250);
  static const Duration medium2 = Duration(milliseconds: 300);
  static const Duration medium3 = Duration(milliseconds: 350);
  static const Duration medium4 = Duration(milliseconds: 400);

  // 长动画 - 页面转换
  static const Duration long1 = Duration(milliseconds: 450);
  static const Duration long2 = Duration(milliseconds: 500);
  static const Duration long3 = Duration(milliseconds: 550);
  static const Duration long4 = Duration(milliseconds: 600);

  // 超长动画 - 复杂页面转换
  static const Duration extraLong1 = Duration(milliseconds: 700);
  static const Duration extraLong2 = Duration(milliseconds: 800);
  static const Duration extraLong3 = Duration(milliseconds: 900);
  static const Duration extraLong4 = Duration(milliseconds: 1000);
}

// M3 Expressive Animation Extensions
extension M3AnimationExtension on Widget {
  Widget m3FadeIn({
    Duration delay = Duration.zero,
    Duration duration = M3Durations.medium2,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: duration,
      curve: M3Curves.emphasizedDecelerate,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: this,
    );
  }

  Widget m3ScaleIn({
    Duration delay = Duration.zero,
    Duration duration = M3Durations.medium2,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1.0),
      duration: duration,
      curve: M3Curves.emphasized,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: this,
    );
  }
}
