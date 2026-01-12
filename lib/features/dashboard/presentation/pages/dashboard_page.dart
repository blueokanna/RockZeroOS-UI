import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';
import '../widgets/system_status_card.dart';
import '../widgets/storage_card.dart';
import '../widgets/quick_actions_card.dart';
import '../widgets/recent_files_card.dart';

// Dashboard data providers
final hardwareInfoProvider = FutureProvider.autoDispose<HardwareInfo?>((
  ref,
) async {
  try {
    final api = ref.read(apiServiceProvider);
    return await api.getHardwareInfo();
  } catch (_) {
    return null;
  }
});

final storageInfoProvider = FutureProvider.autoDispose<StorageInfo?>((
  ref,
) async {
  try {
    final api = ref.read(apiServiceProvider);
    return await api.getStorageInfo();
  } catch (_) {
    return null;
  }
});

final recentFilesProvider = FutureProvider.autoDispose<FileListResponse?>((
  ref,
) async {
  try {
    final api = ref.read(apiServiceProvider);
    return await api.listFiles();
  } catch (_) {
    return null;
  }
});

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hardwareInfo = ref.watch(hardwareInfoProvider);
    final storageInfo = ref.watch(storageInfoProvider);
    final recentFiles = ref.watch(recentFilesProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(hardwareInfoProvider);
          ref.invalidate(storageInfoProvider);
          ref.invalidate(recentFilesProvider);
        },
        child: CustomScrollView(
          slivers: [
            // App Bar
            SliverAppBar.large(
              title: const Text('Dashboard'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    ref.invalidate(hardwareInfoProvider);
                    ref.invalidate(storageInfoProvider);
                    ref.invalidate(recentFilesProvider);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () {},
                ),
              ],
            ),

            // Content
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 800;

                    if (isWide) {
                      return _buildWideLayout(
                        context,
                        hardwareInfo,
                        storageInfo,
                        recentFiles,
                      );
                    } else {
                      return _buildNarrowLayout(
                        context,
                        hardwareInfo,
                        storageInfo,
                        recentFiles,
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
    AsyncValue<StorageInfo?> storageInfo,
    AsyncValue<FileListResponse?> recentFiles,
  ) {
    return Column(
      children: [
        // Top row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: SystemStatusCard(
                hardwareInfo: hardwareInfo,
              ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.05),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: StorageCard(
                storageInfo: storageInfo,
              ).animate().fadeIn(delay: 200.ms).slideX(begin: 0.05),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Bottom row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: QuickActionsCard()
                  .animate()
                  .fadeIn(delay: 300.ms)
                  .slideY(begin: 0.05),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: RecentFilesCard(
                filesResponse: recentFiles,
              ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.05),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(
    BuildContext context,
    AsyncValue<HardwareInfo?> hardwareInfo,
    AsyncValue<StorageInfo?> storageInfo,
    AsyncValue<FileListResponse?> recentFiles,
  ) {
    return Column(
      children: [
        SystemStatusCard(
          hardwareInfo: hardwareInfo,
        ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05),
        const SizedBox(height: 16),
        StorageCard(
          storageInfo: storageInfo,
        ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.05),
        const SizedBox(height: 16),
        QuickActionsCard().animate().fadeIn(delay: 300.ms).slideY(begin: 0.05),
        const SizedBox(height: 16),
        RecentFilesCard(
          filesResponse: recentFiles,
        ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.05),
      ],
    );
  }
}
