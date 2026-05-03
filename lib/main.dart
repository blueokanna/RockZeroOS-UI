import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'core/i18n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/services/device_discovery_service.dart';
import 'core/services/wallpaper_service.dart';
import 'core/services/media_kit_initializer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await MediaKitInitializer.initialize();

  if (kReleaseMode) {
    debugPrintRebuildDirtyWidgets = false;
  }

  await Hive.initFlutter();
  await Hive.openBox('settings');
  await Hive.openBox('cache');

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deviceDiscoveryServiceProvider).startDiscovery();

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

    final effectiveColor = blendedColor ??
        (dynamicColorEnabled && systemAccentColor != null
            ? systemAccentColor
            : seedColor);

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.tr('app.title'),
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(effectiveColor),
      darkTheme: AppTheme.dark(effectiveColor),
      routerConfig: router,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
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
