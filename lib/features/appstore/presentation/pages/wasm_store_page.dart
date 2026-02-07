import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/api_service.dart';

// ============================================================================
// Providers
// ============================================================================

final wasmStoreOverviewProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return await api.getWasmStoreOverview().timeout(const Duration(seconds: 30));
});

final steamFeaturedProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return await api.getSteamFeatured().timeout(const Duration(seconds: 20));
});

final epicFreeProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  return await api.getEpicFreeGames().timeout(const Duration(seconds: 20));
});

final gameSearchProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, query) async {
  final api = ref.read(apiServiceProvider);
  return await api
      .searchGames(query: query)
      .timeout(const Duration(seconds: 15));
});

// ============================================================================
// WASM Store Page
// ============================================================================

class WasmStorePage extends ConsumerStatefulWidget {
  const WasmStorePage({super.key});

  @override
  ConsumerState<WasmStorePage> createState() => _WasmStorePageState();
}

class _WasmStorePageState extends ConsumerState<WasmStorePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String? _searchQuery;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _searchQuery = value.isEmpty ? null : value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar.large(
            title: Row(
              children: [
                Icon(Icons.games_rounded, size: 28, color: colorScheme.primary),
                const SizedBox(width: 12),
                const Text('游戏商店'),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '刷新',
                onPressed: () {
                  ref.invalidate(wasmStoreOverviewProvider);
                  ref.invalidate(steamFeaturedProvider);
                  ref.invalidate(epicFreeProvider);
                },
              ),
              const SizedBox(width: 8),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(100),
              child: Column(
                children: [
                  // 搜索栏
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: '搜索游戏、应用、插件...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchQuery != null
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = null);
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  // Tab 栏
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: const [
                      Tab(text: '推荐'),
                      Tab(text: 'Steam'),
                      Tab(text: 'Epic 免费'),
                      Tab(text: 'WASM 应用'),
                      Tab(text: '插件'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        body: _searchQuery != null
            ? _buildSearchResults()
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(),
                  _buildSteamTab(),
                  _buildEpicTab(),
                  _buildWasmAppsTab(),
                  _buildPluginsTab(),
                ],
              ),
      ),
    );
  }

  // ============================================================================
  // 搜索结果
  // ============================================================================

  Widget _buildSearchResults() {
    final searchAsync = ref.watch(gameSearchProvider(_searchQuery!));

    return searchAsync.when(
      data: (data) {
        final items = (data['items'] as List?) ?? [];
        if (items.isEmpty) {
          return _buildEmptyState('没有找到相关结果', Icons.search_off_rounded);
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final game = items[index] as Map<String, dynamic>;
            return _GameListTile(game: game).animate().fadeIn(
                  delay: Duration(milliseconds: index * 50),
                  duration: 300.ms,
                );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildErrorState('搜索失败: $e'),
    );
  }

  // ============================================================================
  // 推荐 Tab
  // ============================================================================

  Widget _buildOverviewTab() {
    final overviewAsync = ref.watch(wasmStoreOverviewProvider);

    return overviewAsync.when(
      data: (data) {
        final featured = (data['featured_games'] as List?) ?? [];
        final freeGames = (data['free_games'] as List?) ?? [];
        final wasmApps = (data['wasm_apps'] as List?) ?? [];
        final plugins = (data['available_plugins'] as List?) ?? [];
        final categories = (data['categories'] as List?) ?? [];

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(wasmStoreOverviewProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 分类卡片
              if (categories.isNotEmpty) ...[
                _buildSectionTitle('分类', Icons.category_rounded),
                const SizedBox(height: 8),
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final cat = categories[index] as Map<String, dynamic>;
                      return _CategoryChip(
                        icon: cat['icon'] ?? '📦',
                        name: cat['name'] ?? '',
                        count: cat['count'] ?? 0,
                        onTap: () {
                          final id = cat['id'] ?? '';
                          if (id == 'steam') {
                            _tabController.animateTo(1);
                          } else if (id == 'epic_free') {
                            _tabController.animateTo(2);
                          } else if (id == 'wasm_apps') {
                            _tabController.animateTo(3);
                          } else if (id == 'plugins') {
                            _tabController.animateTo(4);
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Steam 精选
              if (featured.isNotEmpty) ...[
                _buildSectionTitle('Steam 精选', Icons.star_rounded),
                const SizedBox(height: 8),
                SizedBox(
                  height: 220,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: featured.length.clamp(0, 10),
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final game = featured[index] as Map<String, dynamic>;
                      return _GameCard(game: game, width: 280);
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Epic 免费游戏
              if (freeGames.isNotEmpty) ...[
                _buildSectionTitle('Epic 免费领取', Icons.card_giftcard_rounded),
                const SizedBox(height: 8),
                SizedBox(
                  height: 220,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: freeGames.length.clamp(0, 10),
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final game = freeGames[index] as Map<String, dynamic>;
                      return _GameCard(game: game, width: 280);
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // WASM 应用
              if (wasmApps.isNotEmpty) ...[
                _buildSectionTitle('WASM 应用', Icons.web_asset_rounded),
                const SizedBox(height: 8),
                ...wasmApps.take(5).map((app) {
                  final a = app as Map<String, dynamic>;
                  return _WasmAppTile(app: a);
                }),
                const SizedBox(height: 24),
              ],

              // 插件
              if (plugins.isNotEmpty) ...[
                _buildSectionTitle('扩展插件', Icons.extension_rounded),
                const SizedBox(height: 8),
                ...plugins.take(5).map((plugin) {
                  final p = plugin as Map<String, dynamic>;
                  return _PluginTile(plugin: p);
                }),
              ],

              // 空状态
              if (featured.isEmpty &&
                  freeGames.isEmpty &&
                  wasmApps.isEmpty &&
                  plugins.isEmpty)
                _buildEmptyState('暂无内容，请检查网络连接', Icons.cloud_off_rounded),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildErrorState('加载失败: $e'),
    );
  }

  // ============================================================================
  // Steam Tab
  // ============================================================================

  Widget _buildSteamTab() {
    final steamAsync = ref.watch(steamFeaturedProvider);

    return steamAsync.when(
      data: (data) {
        final items = (data['items'] as List?) ?? [];
        if (items.isEmpty) {
          return _buildEmptyState('暂无 Steam 精选游戏', Icons.games_rounded);
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(steamFeaturedProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final game = items[index] as Map<String, dynamic>;
              return _GameListTile(game: game).animate().fadeIn(
                    delay: Duration(milliseconds: index * 30),
                    duration: 200.ms,
                  );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildErrorState('加载 Steam 数据失败: $e'),
    );
  }

  // ============================================================================
  // Epic Tab
  // ============================================================================

  Widget _buildEpicTab() {
    final epicAsync = ref.watch(epicFreeProvider);

    return epicAsync.when(
      data: (data) {
        final items = (data['items'] as List?) ?? [];
        if (items.isEmpty) {
          return _buildEmptyState('暂无 Epic 免费游戏', Icons.card_giftcard_rounded);
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(epicFreeProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final game = items[index] as Map<String, dynamic>;
              return _GameListTile(game: game).animate().fadeIn(
                    delay: Duration(milliseconds: index * 30),
                    duration: 200.ms,
                  );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildErrorState('加载 Epic 数据失败: $e'),
    );
  }

  // ============================================================================
  // WASM Apps Tab
  // ============================================================================

  Widget _buildWasmAppsTab() {
    final overviewAsync = ref.watch(wasmStoreOverviewProvider);

    return overviewAsync.when(
      data: (data) {
        final wasmApps = (data['wasm_apps'] as List?) ?? [];
        if (wasmApps.isEmpty) {
          return _buildEmptyState(
            '暂无 WASM 应用\n可通过插件系统扩展功能',
            Icons.web_asset_rounded,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(wasmStoreOverviewProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: wasmApps.length,
            itemBuilder: (context, index) {
              final app = wasmApps[index] as Map<String, dynamic>;
              return _WasmAppTile(app: app).animate().fadeIn(
                    delay: Duration(milliseconds: index * 30),
                    duration: 200.ms,
                  );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildErrorState('加载 WASM 应用失败: $e'),
    );
  }

  // ============================================================================
  // Plugins Tab
  // ============================================================================

  Widget _buildPluginsTab() {
    final overviewAsync = ref.watch(wasmStoreOverviewProvider);

    return overviewAsync.when(
      data: (data) {
        final plugins = (data['available_plugins'] as List?) ?? [];
        if (plugins.isEmpty) {
          return _buildEmptyState(
            '暂无扩展插件\n插件系统支持自定义功能扩展',
            Icons.extension_rounded,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(wasmStoreOverviewProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: plugins.length,
            itemBuilder: (context, index) {
              final plugin = plugins[index] as Map<String, dynamic>;
              return _PluginTile(plugin: plugin).animate().fadeIn(
                    delay: Duration(milliseconds: index * 30),
                    duration: 200.ms,
                  );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildErrorState('加载插件列表失败: $e'),
    );
  }

  // ============================================================================
  // 通用组件
  // ============================================================================

  Widget _buildSectionTitle(String title, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 64, color: colorScheme.error),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: colorScheme.error),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              ref.invalidate(wasmStoreOverviewProvider);
              ref.invalidate(steamFeaturedProvider);
              ref.invalidate(epicFreeProvider);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 子组件
// ============================================================================

/// 分类标签
class _CategoryChip extends StatelessWidget {
  final String icon;
  final String name;
  final int count;
  final VoidCallback? onTap;

  const _CategoryChip({
    required this.icon,
    required this.name,
    required this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(
              name,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 游戏卡片（横向滚动用）
class _GameCard extends StatelessWidget {
  final Map<String, dynamic> game;
  final double width;

  const _GameCard({required this.game, this.width = 280});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = game['name'] ?? '';
    final headerImage = game['header_image'] ?? '';
    final price = game['price'] as Map<String, dynamic>?;
    final isFree = game['is_free'] == true;
    final platform = game['platform'] ?? '';

    return InkWell(
      onTap: () => _openStoreUrl(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图
            SizedBox(
              height: 130,
              width: double.infinity,
              child: headerImage.isNotEmpty
                  ? Image.network(
                      headerImage,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: colorScheme.surfaceContainerLow,
                        child: Icon(Icons.image_not_supported_rounded,
                            color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  : Container(
                      color: colorScheme.surfaceContainerLow,
                      child: Icon(Icons.games_rounded,
                          size: 48, color: colorScheme.onSurfaceVariant),
                    ),
            ),
            // 信息
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        // 平台标签
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: platform == 'steam'
                                ? Colors.blue.withAlpha(30)
                                : Colors.purple.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            platform == 'steam' ? 'Steam' : 'Epic',
                            style: TextStyle(
                              fontSize: 10,
                              color: platform == 'steam'
                                  ? Colors.blue
                                  : Colors.purple,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // 价格
                        Text(
                          isFree ? '免费' : price?['formatted'] ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color:
                                isFree ? Colors.green : colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openStoreUrl(BuildContext context) {
    final url = game['store_url'] ?? '';
    if (url.isNotEmpty) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}

/// 游戏列表项
class _GameListTile extends StatelessWidget {
  final Map<String, dynamic> game;

  const _GameListTile({required this.game});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = game['name'] ?? '';
    final headerImage = game['header_image'] ?? '';
    final shortDesc = game['short_description'] ?? '';
    final price = game['price'] as Map<String, dynamic>?;
    final isFree = game['is_free'] == true;
    final platform = game['platform'] ?? '';
    final genres = (game['genres'] as List?)?.take(3).join(', ') ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          final url = game['store_url'] ?? '';
          if (url.isNotEmpty) {
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 缩略图
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 120,
                  height: 68,
                  child: headerImage.isNotEmpty
                      ? Image.network(
                          headerImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: colorScheme.surfaceContainerLow,
                            child: const Icon(Icons.games_rounded),
                          ),
                        )
                      : Container(
                          color: colorScheme.surfaceContainerLow,
                          child: const Icon(Icons.games_rounded),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (shortDesc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        shortDesc,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: platform == 'steam'
                                ? Colors.blue.withAlpha(30)
                                : Colors.purple.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            platform == 'steam' ? 'Steam' : 'Epic',
                            style: TextStyle(
                              fontSize: 10,
                              color: platform == 'steam'
                                  ? Colors.blue
                                  : Colors.purple,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (genres.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              genres,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          isFree ? '免费' : price?['formatted'] ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isFree ? Colors.green : colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// WASM 应用列表项
class _WasmAppTile extends StatelessWidget {
  final Map<String, dynamic> app;

  const _WasmAppTile({required this.app});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = app['name'] ?? '';
    final description = app['description'] ?? '';
    final version = app['version'] ?? '';
    final category = app['category'] ?? 'other';
    final installed = app['installed'] == true;
    final sizeBytes = app['size_bytes'] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getCategoryIcon(category),
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description.isNotEmpty)
              Text(description, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('v$version',
                    style: TextStyle(
                        fontSize: 11, color: colorScheme.onSurfaceVariant)),
                const SizedBox(width: 8),
                if (sizeBytes > 0)
                  Text(_formatBytes(sizeBytes),
                      style: TextStyle(
                          fontSize: 11, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
        trailing: installed
            ? Chip(
                label: const Text('已安装', style: TextStyle(fontSize: 11)),
                backgroundColor: Colors.green.withAlpha(30),
                side: BorderSide.none,
                padding: EdgeInsets.zero,
              )
            : const Icon(Icons.download_rounded),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'game':
        return Icons.sports_esports_rounded;
      case 'tool':
        return Icons.build_rounded;
      case 'media':
        return Icons.play_circle_rounded;
      case 'web3':
        return Icons.link_rounded;
      case 'social':
        return Icons.people_rounded;
      case 'productivity':
        return Icons.work_rounded;
      default:
        return Icons.web_asset_rounded;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 插件列表项
class _PluginTile extends StatelessWidget {
  final Map<String, dynamic> plugin;

  const _PluginTile({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = plugin['name'] ?? '';
    final description = plugin['description'] ?? '';
    final version = plugin['version'] ?? '';
    final author = plugin['author'] ?? '';
    final capabilities = (plugin['capabilities'] as List?)?.join(', ') ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.extension_rounded,
            color: colorScheme.onTertiaryContainer,
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description.isNotEmpty)
              Text(description, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('v$version',
                    style: TextStyle(
                        fontSize: 11, color: colorScheme.onSurfaceVariant)),
                if (author.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text('by $author',
                      style: TextStyle(
                          fontSize: 11, color: colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
            if (capabilities.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                capabilities,
                style: TextStyle(
                    fontSize: 10, color: colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
