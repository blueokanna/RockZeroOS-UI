import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/services/device_discovery_service.dart';
import 'core/services/wallpaper_service.dart';
import 'core/services/media_kit_initializer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 使用自定义初始化器，支持本地库加载
  await MediaKitInitializer.initialize();

  if (kReleaseMode) {
    debugPrintRebuildDirtyWidgets = false;
  }

  await Hive.initFlutter();
  await Hive.openBox('settings');
  await Hive.openBox('cache');

  // 设置 Android 全面屏手势导航 (edge-to-edge) 与透明系统栏
  if (!kIsWeb && Platform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ));
  }

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await _setupDesktopWindow();
  }

  runApp(const ProviderScope(child: RockZeroApp()));
}

Future<void> _setupDesktopWindow() async {
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(800, 600),
    minimumSize: Size(700, 700),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'RockZero',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

class RockZeroApp extends ConsumerStatefulWidget {
  const RockZeroApp({super.key});

  @override
  ConsumerState<RockZeroApp> createState() => _RockZeroAppState();
}

class _RockZeroAppState extends ConsumerState<RockZeroApp> {
  @override
  void initState() {
    super.initState();
    // Start device discovery on app launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deviceDiscoveryServiceProvider).startDiscovery();
      // Refresh system accent color if dynamic color is enabled
      if (ref.read(dynamicColorEnabledProvider)) {
        ref.read(systemAccentColorProvider.notifier).refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final seedColor = ref.watch(seedColorProvider);
    final dynamicColorEnabled = ref.watch(dynamicColorEnabledProvider);
    final systemAccentColor = ref.watch(systemAccentColorProvider);
    final blendedColor = ref.watch(blendedThemeColorProvider);

    // Priority: blended color > system color > seed color
    final effectiveColor = blendedColor ??
        (dynamicColorEnabled && systemAccentColor != null
            ? systemAccentColor
            : seedColor);

    return MaterialApp.router(
      title: 'RockZero',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(effectiveColor),
      darkTheme: AppTheme.dark(effectiveColor),
      routerConfig: router,
      builder: (context, child) {
        // 根据实际亮度更新系统栏图标颜色
        final brightness = Theme.of(context).brightness;
        final iconBrightness =
            brightness == Brightness.dark ? Brightness.light : Brightness.dark;
        if (!kIsWeb && Platform.isAndroid) {
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: iconBrightness,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: iconBrightness,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarContrastEnforced: false,
          ));
        }

        // Clamp text scale factor to prevent layout breakage
        final mediaQuery = MediaQuery.of(context);
        final clampedTextScaler = mediaQuery.textScaler.clamp(
          minScaleFactor: 0.8,
          maxScaleFactor: 1.3,
        );
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: clampedTextScaler),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
