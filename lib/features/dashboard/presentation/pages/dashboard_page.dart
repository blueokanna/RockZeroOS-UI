import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/services/wallpaper_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../storage/presentation/providers/disk_platform_capabilities_provider.dart';
import '../widgets/system_status_card.dart';
import '../widgets/storage_card.dart';
import '../widgets/network_status_card.dart';

final hardwareInfoProvider = FutureProvider.autoDispose<HardwareInfo?>((
  ref,
) async {
  try {
    final api = ref.read(apiServiceProvider);
    final result = await api.getHardwareInfo();
    return result;
  } catch (e, stackTrace) {
    debugPrint('❌ [Dashboard] Hardware info error: $e');
    debugPrint('📚 [Dashboard] Stack trace: $stackTrace');

    return null;
  }
});

final totalStorageInfoProvider = FutureProvider.autoDispose<TotalStorageInfo?>((
  ref,
) async {
  try {
    final api = ref.read(apiServiceProvider);
    final disks = await api.getDiskInfo();

    int totalSpace = 0;
    int usedSpace = 0;
    int availableSpace = 0;

    for (final disk in disks) {
      totalSpace += disk.totalSpace;
      usedSpace += disk.usedSpace;
      availableSpace += disk.availableSpace;
    }

    final usagePercentage =
        totalSpace > 0 ? (usedSpace / totalSpace) * 100 : 0.0;

    return TotalStorageInfo(
      totalSpace: totalSpace,
      usedSpace: usedSpace,
      availableSpace: availableSpace,
      usagePercentage: usagePercentage,
      diskCount: disks.length,
      disks: disks,
    );
  } catch (e, stackTrace) {
    debugPrint('❌ [Dashboard] Storage info error: $e');
    debugPrint('📚 [Dashboard] Stack trace: $stackTrace');
    return null;
  }
});

final networkInfoProvider = FutureProvider.autoDispose<NetworkInfo?>((
  ref,
) async {
  try {
    final api = ref.read(apiServiceProvider);
    final hardware = await api.getHardwareInfo();

    if (hardware.networkInterfaces == null ||
        hardware.networkInterfaces!.isEmpty) {
      debugPrint('⚠️ [Dashboard] No network interfaces found');
      return NetworkInfo(
        interfaces: [],
        totalRxBytes: 0,
        totalTxBytes: 0,
      );
    }

    final interfaces = hardware.networkInterfaces!;

    return NetworkInfo(
      interfaces: interfaces,
      totalRxBytes: interfaces.fold<int>(0, (sum, i) => sum + i.rxBytes),
      totalTxBytes: interfaces.fold<int>(0, (sum, i) => sum + i.txBytes),
    );
  } catch (e, stackTrace) {
    debugPrint('❌ [Dashboard] Network info error: $e');
    debugPrint('📚 [Dashboard] Stack trace: $stackTrace');

    return NetworkInfo(
      interfaces: [],
      totalRxBytes: 0,
      totalTxBytes: 0,
    );
  }
});

final publicIpProvider = FutureProvider.autoDispose<String?>((ref) async {
  try {
    final api = ref.read(apiServiceProvider);
    return await api.getPublicIp();
  } catch (_) {
    return null;
  }
});

class TotalStorageInfo {
  final int totalSpace;
  final int usedSpace;
  final int availableSpace;
  final double usagePercentage;
  final int diskCount;
  final List<DiskInfo> disks;

  TotalStorageInfo({
    required this.totalSpace,
    required this.usedSpace,
    required this.availableSpace,
    required this.usagePercentage,
    required this.diskCount,
    required this.disks,
  });
}

class NetworkInfo {
  final List<NetworkInterfaceInfo> interfaces;
  final int totalRxBytes;
  final int totalTxBytes;
  final int rxSpeed;
  final int txSpeed;

  NetworkInfo({
    required this.interfaces,
    required this.totalRxBytes,
    required this.totalTxBytes,
    this.rxSpeed = 0,
    this.txSpeed = 0,
  });

  NetworkInfo copyWithSpeed({required int rxSpeed, required int txSpeed}) {
    return NetworkInfo(
      interfaces: interfaces,
      totalRxBytes: totalRxBytes,
      totalTxBytes: totalTxBytes,
      rxSpeed: rxSpeed,
      txSpeed: txSpeed,
    );
  }
}

class NetworkSpeedNotifier extends Notifier<NetworkInfo?> {
  int _lastRxBytes = 0;
  int _lastTxBytes = 0;
  DateTime _lastUpdate = DateTime.now();

  @override
  NetworkInfo? build() => null;

  void updateFromHardware(NetworkInfo? info) {
    if (info == null) {
      state = null;
      return;
    }

    final now = DateTime.now();
    final elapsed = now.difference(_lastUpdate).inMilliseconds;

    if (elapsed > 0 && _lastRxBytes > 0) {
      final rxDiff = info.totalRxBytes - _lastRxBytes;
      final txDiff = info.totalTxBytes - _lastTxBytes;

      final rxSpeed = (rxDiff * 1000 / elapsed).round();
      final txSpeed = (txDiff * 1000 / elapsed).round();

      state = info.copyWithSpeed(
        rxSpeed: rxSpeed > 0 ? rxSpeed : 0,
        txSpeed: txSpeed > 0 ? txSpeed : 0,
      );
    } else {
      state = info;
    }

    _lastRxBytes = info.totalRxBytes;
    _lastTxBytes = info.totalTxBytes;
    _lastUpdate = now;
  }
}

final networkSpeedProvider =
    NotifierProvider<NetworkSpeedNotifier, NetworkInfo?>(
  NetworkSpeedNotifier.new,
);

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  Timer? _systemTimer;
  Timer? _networkTimer;

  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _systemTimer?.cancel();
    _networkTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _systemTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        ref.invalidate(hardwareInfoProvider);
        ref.invalidate(totalStorageInfoProvider);
      }
    });

    _networkTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (mounted) {
        try {
          final api = ref.read(apiServiceProvider);
          final hardware = await api.getHardwareInfo();
          final interfaces = hardware.networkInterfaces ?? [];

          final networkInfo = NetworkInfo(
            interfaces: interfaces,
            totalRxBytes: interfaces.fold<int>(0, (sum, i) => sum + i.rxBytes),
            totalTxBytes: interfaces.fold<int>(0, (sum, i) => sum + i.txBytes),
          );

          ref
              .read(networkSpeedProvider.notifier)
              .updateFromHardware(networkInfo);
        } catch (_) {}
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hardwareInfo = ref.watch(hardwareInfoProvider);
    final storageInfo = ref.watch(totalStorageInfoProvider);
    final networkInfo = ref.watch(networkSpeedProvider);
    final diskCapabilities = ref.watch(diskPlatformCapabilitiesProvider);

    final networkInfoAsync = networkInfo != null
        ? AsyncValue.data(networkInfo)
        : const AsyncValue<NetworkInfo?>.loading();

    final hasWallpaper =
        ref.watch(backgroundModeProvider) == BackgroundMode.customWallpaper &&
            (ref.watch(customWallpaperPathProvider)?.isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: hasWallpaper ? Colors.transparent : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(hardwareInfoProvider);
          ref.invalidate(totalStorageInfoProvider);

          try {
            final api = ref.read(apiServiceProvider);
            final hardware = await api.getHardwareInfo();
            final interfaces = hardware.networkInterfaces ?? [];
            final netInfo = NetworkInfo(
              interfaces: interfaces,
              totalRxBytes: interfaces.fold<int>(
                0,
                (sum, i) => sum + i.rxBytes,
              ),
              totalTxBytes: interfaces.fold<int>(
                0,
                (sum, i) => sum + i.txBytes,
              ),
            );
            ref.read(networkSpeedProvider.notifier).updateFromHardware(netInfo);
          } catch (_) {}
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight:
                  MediaQuery.of(context).size.width <= 600 ? 80 : 120,
              floating: true,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.dashboard_rounded,
                        size: 22,
                        color: Theme.of(context).colorScheme.onSurface),
                    const SizedBox(width: 8),
                    Text(
                      'Dashboard',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 900;
                    final isMedium = constraints.maxWidth > 600;

                    if (isWide) {
                      return _buildWideLayout(
                        context,
                        hardwareInfo,
                        diskCapabilities,
                        storageInfo,
                        networkInfoAsync,
                      );
                    } else if (isMedium) {
                      return _buildMediumLayout(
                        context,
                        hardwareInfo,
                        diskCapabilities,
                        storageInfo,
                        networkInfoAsync,
                      );
                    } else {
                      return _buildNarrowLayout(
                        context,
                        hardwareInfo,
                        diskCapabilities,
                        storageInfo,
                        networkInfoAsync,
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideLayout(
    BuildContext context,
    AsyncValue<HardwareInfo?> hardwareInfo,
    AsyncValue<DiskPlatformCapabilities> diskCapabilities,
    AsyncValue<TotalStorageInfo?> storageInfo,
    AsyncValue<NetworkInfo?> networkInfo,
  ) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: SystemStatusCard(
                hardwareInfo: hardwareInfo,
                diskCapabilities: diskCapabilities,
              )
                  .animate()
                  .fadeIn(delay: 100.ms, curve: M3Curves.emphasizedDecelerate)
                  .slideX(begin: -0.03, curve: M3Curves.emphasized),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  TotalStorageCard(
                    storageInfo: storageInfo,
                    diskCapabilities: diskCapabilities,
                  )
                      .animate()
                      .fadeIn(
                        delay: 150.ms,
                        curve: M3Curves.emphasizedDecelerate,
                      )
                      .slideX(begin: 0.03, curve: M3Curves.emphasized),
                  const SizedBox(height: 16),
                  NetworkStatusCard(networkInfo: networkInfo)
                      .animate()
                      .fadeIn(
                        delay: 200.ms,
                        curve: M3Curves.emphasizedDecelerate,
                      )
                      .slideX(begin: 0.03, curve: M3Curves.emphasized),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMediumLayout(
    BuildContext context,
    AsyncValue<HardwareInfo?> hardwareInfo,
    AsyncValue<DiskPlatformCapabilities> diskCapabilities,
    AsyncValue<TotalStorageInfo?> storageInfo,
    AsyncValue<NetworkInfo?> networkInfo,
  ) {
    return Column(
      children: [
        SystemStatusCard(
          hardwareInfo: hardwareInfo,
          diskCapabilities: diskCapabilities,
        )
            .animate()
            .fadeIn(delay: 100.ms, curve: M3Curves.emphasizedDecelerate)
            .slideY(begin: 0.03, curve: M3Curves.emphasized),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TotalStorageCard(
                storageInfo: storageInfo,
                diskCapabilities: diskCapabilities,
              )
                  .animate()
                  .fadeIn(delay: 150.ms, curve: M3Curves.emphasizedDecelerate)
                  .slideX(begin: -0.03, curve: M3Curves.emphasized),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: NetworkStatusCard(networkInfo: networkInfo)
                  .animate()
                  .fadeIn(delay: 200.ms, curve: M3Curves.emphasizedDecelerate)
                  .slideX(begin: 0.03, curve: M3Curves.emphasized),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(
    BuildContext context,
    AsyncValue<HardwareInfo?> hardwareInfo,
    AsyncValue<DiskPlatformCapabilities> diskCapabilities,
    AsyncValue<TotalStorageInfo?> storageInfo,
    AsyncValue<NetworkInfo?> networkInfo,
  ) {
    return Column(
      children: [
        SystemStatusCard(
          hardwareInfo: hardwareInfo,
          diskCapabilities: diskCapabilities,
        )
            .animate()
            .fadeIn(delay: 100.ms, curve: M3Curves.emphasizedDecelerate)
            .slideY(begin: 0.03, curve: M3Curves.emphasized),
        const SizedBox(height: 16),
        TotalStorageCard(
          storageInfo: storageInfo,
          diskCapabilities: diskCapabilities,
        )
            .animate()
            .fadeIn(delay: 150.ms, curve: M3Curves.emphasizedDecelerate)
            .slideY(begin: 0.03, curve: M3Curves.emphasized),
        const SizedBox(height: 16),
        NetworkStatusCard(networkInfo: networkInfo)
            .animate()
            .fadeIn(delay: 200.ms, curve: M3Curves.emphasizedDecelerate)
            .slideY(begin: 0.03, curve: M3Curves.emphasized),
      ],
    );
  }
}
