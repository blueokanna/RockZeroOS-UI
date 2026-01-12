import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/services/device_discovery_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();
  await Hive.openBox('settings');
  await Hive.openBox('cache');

  runApp(const ProviderScope(child: RockZeroApp()));
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final seedColor = ref.watch(seedColorProvider);

    return MaterialApp.router(
      title: 'RockZero',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(seedColor),
      darkTheme: AppTheme.dark(seedColor),
      routerConfig: router,
    );
  }
}
