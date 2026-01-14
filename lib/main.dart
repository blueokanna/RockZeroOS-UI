import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/services/device_discovery_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();
  await Hive.openBox('settings');
  await Hive.openBox('cache');

  // Set window size for desktop platforms
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

    // Use system accent color if dynamic color is enabled and available
    final effectiveColor = dynamicColorEnabled && systemAccentColor != null
        ? systemAccentColor
        : seedColor;

    return MaterialApp.router(
      title: 'RockZero',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(effectiveColor),
      darkTheme: AppTheme.dark(effectiveColor),
      routerConfig: router,
    );
  }
}
