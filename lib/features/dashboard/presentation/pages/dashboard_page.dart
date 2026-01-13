import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/system_status_card.dart';
import '../widgets/storage_card.dart';
import '../widgets/network_status_card.dart';

// Auto-refresh providers with timers
final hardwareInfoProvider =
    FutureProvider.autoDispose<HardwareInfo?>((ref) async {
  try {
    final api = ref.read(apiServiceProvider);
    return await api.getHardwareInfo();
  } catch (_) {
    return null;
  }
});

final totalStorageInfoProvider =
    FutureProvider.autoDispose<TotalStorageInfo?>((ref) async {
  try {
    final api = ref.read(apiServiceProvider);
    final disks = await api.getDiskInfo();

    // Calculate total storage from ALL disks
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
  } catch (_) {
    return null;
  }
});

final networkInfoProvider =
    FutureProvider.autoDispose<NetworkInfo?>((ref) async {
  try {
    final api = ref.read(apiServiceProvider);
    final hardware = await api.getHardwareInfo();
    final interfaces = hardware.networkInterfaces ?? [];

    return NetworkInfo(
      interfaces: interfaces,
      totalRxBytes: interfaces.fold<int>(0, (sum, i) => sum + i.rxBytes),
      totalTxBytes: interfaces.fold<int>(0, (sum, i) => sum + i.txBytes),
    );
  } catch (_) {
    return null;
  }
});

// Total storage info model
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

// Network info model
class NetworkInfo {
  final List<NetworkInterfaceInfo> interfaces;
  final int totalRxBytes;
  final int totalTxBytes;

  NetworkInfo({
    required this.interfaces,
    required this.totalRxBytes,
    required this.totalTxBytes,
  });
}

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
    // System status & storage refresh every 3 seconds
    _systemTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        ref.invalidate(hardwareInfoProvider);
        ref.invalidate(totalStorageInfoProvider);
      }
    });

    // Network status refresh every 1 second
    _networkTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        ref.invalidate(networkInfoProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hardwareInfo = ref.watch(hardwareInfoProvider);
    final storageInfo = ref.watch(totalStorageInfoProvider);
    final networkInfo = ref.watch(networkInfoProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(hardwareInfoProvider);
          ref.invalidate(totalStorageInfoProvider);
          ref.invalidate(networkInfoProvider);
        },
        child: CustomScrollView(
          slivers: [
            // App Bar
            SliverAppBar.large(
              title: Row(
                children: [
                  Icon(Icons.dashboard_rounded, size: 28),
                  const SizedBox(width: 12),
                  const Text('Dashboard'),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () {
                    ref.invalidate(hardwareInfoProvider);
                    ref.invalidate(totalStorageInfoProvider);
                    ref.invalidate(networkInfoProvider);
                  },
                  tooltip: 'Refresh',
                ),
                IconButton(
                  icon: const Icon(Icons.notifications_rounded),
                  onPressed: () {},
                  tooltip: 'Notifications',
                ),
              ],
            ),

            // Content
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
                        storageInfo,
                        networkInfo,
                      );
                    } else if (isMedium) {
                      return _buildMediumLayout(
                        context,
                        hardwareInfo,
                        storageInfo,
                        networkInfo,
                      );
                    } else {
                      return _buildNarrowLayout(
                        context,
                        hardwareInfo,
                        storageInfo,
                        networkInfo,
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
              child: SystemStatusCard(hardwareInfo: hardwareInfo)
                  .animate()
                  .fadeIn(delay: 100.ms, curve: M3Curves.emphasizedDecelerate)
                  .slideX(begin: -0.03, curve: M3Curves.emphasized),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  TotalStorageCard(storageInfo: storageInfo)
                      .animate()
                      .fadeIn(
                          delay: 150.ms, curve: M3Curves.emphasizedDecelerate)
                      .slideX(begin: 0.03, curve: M3Curves.emphasized),
                  const SizedBox(height: 16),
                  NetworkStatusCard(networkInfo: networkInfo)
                      .animate()
                      .fadeIn(
                          delay: 200.ms, curve: M3Curves.emphasizedDecelerate)
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
    AsyncValue<TotalStorageInfo?> storageInfo,
    AsyncValue<NetworkInfo?> networkInfo,
  ) {
    return Column(
      children: [
        SystemStatusCard(hardwareInfo: hardwareInfo)
            .animate()
            .fadeIn(delay: 100.ms, curve: M3Curves.emphasizedDecelerate)
            .slideY(begin: 0.03, curve: M3Curves.emphasized),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TotalStorageCard(storageInfo: storageInfo)
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
    AsyncValue<TotalStorageInfo?> storageInfo,
    AsyncValue<NetworkInfo?> networkInfo,
  ) {
    return Column(
      children: [
        SystemStatusCard(hardwareInfo: hardwareInfo)
            .animate()
            .fadeIn(delay: 100.ms, curve: M3Curves.emphasizedDecelerate)
            .slideY(begin: 0.03, curve: M3Curves.emphasized),
        const SizedBox(height: 16),
        TotalStorageCard(storageInfo: storageInfo)
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
