import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/api_service.dart';
import '../../../../core/services/wallpaper_service.dart';
import '../../../files/presentation/pages/lan_transfer_page.dart';
import '../widgets/platform_game_tab.dart';
import 'in_app_browser_page.dart';

// ============================================================================
// Providers
// ============================================================================

final wasmStoreOverviewProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  try {
    return await api
        .getWasmStoreOverview()
        .timeout(const Duration(seconds: 30));
  } catch (e) {
    if (e is DioException && e.response?.statusCode == 401) rethrow;
    return {
      'featured_games': <dynamic>[],
      'free_games': <dynamic>[],
      'wasm_apps': <dynamic>[],
      'available_plugins': <dynamic>[],
      'categories': <dynamic>[],
    };
  }
});

final steamFeaturedProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  try {
    return await api.getSteamFeatured().timeout(const Duration(seconds: 20));
  } catch (e) {
    return {'items': <dynamic>[], 'total': 0};
  }
});

final epicFreeProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  try {
    return await api.getEpicFreeGames().timeout(const Duration(seconds: 20));
  } catch (e) {
    return {'items': <dynamic>[], 'total': 0};
  }
});

final gameSearchProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, query) async {
  final api = ref.read(apiServiceProvider);
  try {
    return await api
        .searchGames(query: query)
        .timeout(const Duration(seconds: 15));
  } catch (e) {
    return {'items': <dynamic>[], 'total': 0};
  }
});

/// Steam 用户游戏库 Provider
final steamLibraryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String steamId, String? apiKey})>(
        (ref, params) async {
  final api = ref.read(apiServiceProvider);
  try {
    return await api
        .getSteamUserLibrary(steamId: params.steamId, apiKey: params.apiKey)
        .timeout(const Duration(seconds: 20));
  } catch (e) {
    return {'games': <dynamic>[], 'total': 0, 'steam_id': params.steamId};
  }
});

/// Steam 用户资料 Provider
final steamPlayerProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String steamId, String? apiKey})>(
        (ref, params) async {
  final api = ref.read(apiServiceProvider);
  try {
    return await api
        .getSteamPlayerSummary(steamId: params.steamId, apiKey: params.apiKey)
        .timeout(const Duration(seconds: 10));
  } catch (e) {
    return <String, dynamic>{};
  }
});

/// 每日 Top 30 推荐 Provider
final dailyRecommendationsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  try {
    return await api
        .getDailyRecommendations()
        .timeout(const Duration(seconds: 20));
  } catch (e) {
    return {'items': <dynamic>[], 'total': 0};
  }
});

// ============================================================================
// WASM Store Page - 游戏中心 (Gaming Hub like 小黑盒)
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

  // Steam settings
  String? _steamId;
  String? _steamApiKey;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 10, vsync: this);
    _loadSteamSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadSteamSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _steamId = prefs.getString('steam_id');
        _steamApiKey = prefs.getString('steam_api_key');
      });
    }
  }

  Future<void> _saveSteamSettings(String steamId, String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('steam_id', steamId);
    await prefs.setString('steam_api_key', apiKey);
    if (mounted) {
      setState(() {
        _steamId = steamId;
        _steamApiKey = apiKey;
      });
    }
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
    final hasWallpaper =
        ref.watch(backgroundModeProvider) == BackgroundMode.customWallpaper &&
            ref.watch(customWallpaperPathProvider) != null;

    return Scaffold(
      backgroundColor: hasWallpaper ? Colors.transparent : null,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            floating: true,
            snap: true,
            pinned: true,
            expandedHeight: 110,
            toolbarHeight: 56,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 60),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sports_esports_rounded,
                      size: 22, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '游戏中心',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              collapseMode: CollapseMode.pin,
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
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: '更多',
                onSelected: (value) {
                  switch (value) {
                    case 'lan_transfer':
                      LanTransferPage.open(context);
                    case 'github_import':
                      _showGitHubImportDialog();
                    case 'wasm_script':
                      _showRunScriptDialog();
                    case 'steam_settings':
                      _showSteamSettingsDialog();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'lan_transfer',
                    child: ListTile(
                      leading: Icon(Icons.swap_horiz_rounded),
                      title: Text('局域网传输'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'github_import',
                    child: ListTile(
                      leading: Icon(Icons.download_rounded),
                      title: Text('GitHub 导入'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'wasm_script',
                    child: ListTile(
                      leading: Icon(Icons.terminal_rounded),
                      title: Text('WASM 脚本执行'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'steam_settings',
                    child: ListTile(
                      leading: Icon(Icons.person_search_rounded),
                      title: Text('Steam 账号设置'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(108),
              child: Material(
                color: hasWallpaper
                    ? colorScheme.surface.withValues(alpha: 0.65)
                    : colorScheme.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 搜索栏
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: SizedBox(
                        height: 44,
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: '搜索游戏、应用、插件...',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            prefixIcon: Icon(Icons.search_rounded,
                                size: 20, color: colorScheme.onSurfaceVariant),
                            suffixIcon: _searchQuery != null
                                ? IconButton(
                                    icon: Icon(Icons.clear_rounded,
                                        size: 18,
                                        color: colorScheme.onSurfaceVariant),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = null);
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 0),
                          ),
                        ),
                      ),
                    ),
                    // Tab 栏
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                      tabs: const [
                        Tab(text: '推荐'),
                        Tab(text: '每日Top30'),
                        Tab(text: '我的游戏库'),
                        Tab(text: 'Steam'),
                        Tab(text: 'Epic Game'),
                        Tab(text: 'WeGame'),
                        Tab(text: 'Ubisoft'),
                        Tab(text: 'Xbox'),
                        Tab(text: 'WASM 应用'),
                        Tab(text: '插件'),
                      ],
                    ),
                  ],
                ),
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
                  _buildRecommendationsTab(),
                  _buildMyLibraryTab(),
                  _buildSteamTab(),
                  _buildEpicTab(),
                  const PlatformGameTab(platform: GamePlatform.wegame),
                  const PlatformGameTab(platform: GamePlatform.ubisoft),
                  const PlatformGameTab(platform: GamePlatform.xbox),
                  _buildWasmAppsTab(),
                  _buildPluginsTab(),
                ],
              ),
      ),
    );
  }

  // ============================================================================
  // Steam 设置对话框
  // ============================================================================

  void _showSteamSettingsDialog() {
    final steamIdCtrl = TextEditingController(text: _steamId ?? '');
    final apiKeyCtrl = TextEditingController(text: _steamApiKey ?? '');
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.settings_rounded, color: colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Steam 账号设置'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '绑定你的 Steam 账号以查看游戏库和游玩时间',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: steamIdCtrl,
                decoration: InputDecoration(
                  labelText: 'Steam ID (64位)',
                  hintText: '76561198xxxxxxxxx',
                  prefixIcon: const Icon(Icons.person_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apiKeyCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Steam Web API Key',
                  hintText: '从 steamcommunity.com/dev/apikey 获取',
                  prefixIcon: const Icon(Icons.key_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => launchUrl(
                  Uri.parse('https://steamcommunity.com/dev/apikey'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(
                  '获取 Steam API Key →',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final id = steamIdCtrl.text.trim();
              final key = apiKeyCtrl.text.trim();
              if (id.isNotEmpty && key.isNotEmpty) {
                _saveSteamSettings(id, key);
                Navigator.pop(ctx);
                ref.invalidate(wasmStoreOverviewProvider);
              }
            },
            child: const Text('保存'),
          ),
        ],
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

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(wasmStoreOverviewProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Hero Banner
              _buildHeroBanner(),
              const SizedBox(height: 20),

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
  // Hero Banner
  // ============================================================================

  Widget _buildHeroBanner() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.tertiaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '游戏中心',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '浏览 Steam / Epic 游戏资讯\n查看你的游戏库和游玩时间',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onPrimaryContainer.withAlpha(180),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                if (_steamId == null)
                  FilledButton.tonalIcon(
                    onPressed: _showSteamSettingsDialog,
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label:
                        const Text('绑定 Steam', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          Icon(
            Icons.sports_esports_rounded,
            size: 80,
            color: colorScheme.onPrimaryContainer.withAlpha(40),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(
          begin: const Offset(0.95, 0.95),
          duration: 400.ms,
          curve: Curves.easeOutCubic,
        );
  }

  // ============================================================================
  // 我的游戏库 Tab — 多平台游戏库
  // ============================================================================

  Widget _buildMyLibraryTab() {
    final colorScheme = Theme.of(context).colorScheme;
    final hasSteam = _steamId != null && _steamApiKey != null;

    return CustomScrollView(
      slivers: [
        // 多平台快捷入口
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '游戏平台账号',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '登录各平台账号查看游戏库和管理游戏',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _PlatformLoginCard(
                  name: 'Steam',
                  icon: Icons.games_rounded,
                  color: const Color(0xFF1B2838),
                  isConnected: hasSteam,
                  onTap: hasSteam
                      ? () => _tabController.animateTo(3)
                      : _showSteamSettingsDialog,
                ),
                _PlatformLoginCard(
                  name: 'Epic Game',
                  icon: Icons.sports_esports_rounded,
                  color: const Color(0xFF2A2A2A),
                  isConnected: false,
                  onTap: () => InAppBrowserPage.open(
                    context,
                    url: 'https://store.epicgames.com/',
                    title: 'Epic Games',
                  ),
                ),
                _PlatformLoginCard(
                  name: 'WeGame',
                  icon: Icons.videogame_asset_rounded,
                  color: const Color(0xFFFF6600),
                  isConnected: false,
                  onTap: () => InAppBrowserPage.open(
                    context,
                    url: 'https://www.wegame.com.cn/store',
                    title: 'WeGame',
                  ),
                ),
                _PlatformLoginCard(
                  name: 'Ubisoft',
                  icon: Icons.gamepad_rounded,
                  color: const Color(0xFF0070FF),
                  isConnected: false,
                  onTap: () => InAppBrowserPage.open(
                    context,
                    url: 'https://store.ubisoft.com/sea/home',
                    title: 'Ubisoft Connect',
                  ),
                ),
                _PlatformLoginCard(
                  name: 'Xbox',
                  icon: Icons.sports_esports_outlined,
                  color: const Color(0xFF107C10),
                  isConnected: false,
                  onTap: () => InAppBrowserPage.open(
                    context,
                    url: 'https://www.xbox.com/zh-CN/games/browse',
                    title: 'Xbox',
                  ),
                ),
              ],
            ),
          ),
        ),

        // Steam 游戏库区域
        if (hasSteam) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.games_rounded,
                      size: 20, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Steam 游戏库',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ..._buildSteamLibrarySection(),
        ] else ...[
          SliverFillRemaining(
            child: _buildSteamSetupPrompt(),
          ),
        ],
      ],
    );
  }

  /// Steam 游戏库详细内容（profile + stats + game list）
  List<Widget> _buildSteamLibrarySection() {
    final params = (steamId: _steamId!, apiKey: _steamApiKey);
    final libraryAsync = ref.watch(steamLibraryProvider(params));
    final playerAsync = ref.watch(steamPlayerProvider(params));

    return [
      // Player profile header
      SliverToBoxAdapter(
        child: playerAsync.when(
          data: (player) => _buildPlayerProfileCard(player),
          loading: () => _buildPlayerProfileSkeleton(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ),

      // Game library stats
      SliverToBoxAdapter(
        child: libraryAsync.when(
          data: (data) {
            final games = (data['games'] as List?) ?? [];
            return _buildLibraryStats(games);
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ),

      // Game list
      libraryAsync.when(
        data: (data) {
          final games = (data['games'] as List?) ?? [];
          if (games.isEmpty) {
            return SliverFillRemaining(
              child: _buildEmptyState(
                '游戏库为空\n请检查 Steam ID 和 API Key 是否正确',
                Icons.sports_esports_outlined,
              ),
            );
          }
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: games.length,
              itemBuilder: (context, index) {
                final game = games[index] as Map<String, dynamic>;
                return _LibraryGameTile(game: game).animate().fadeIn(
                      delay: Duration(
                          milliseconds: (index * 30).clamp(0, 500)),
                      duration: 200.ms,
                    );
              },
            ),
          );
        },
        loading: () => const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => SliverFillRemaining(
          child: _buildErrorState('加载游戏库失败: $e'),
        ),
      ),
    ];
  }

  Widget _buildSteamSetupPrompt() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withAlpha(50),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.sports_esports_rounded,
                size: 64,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '绑定 Steam 账号',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '绑定你的 Steam 账号后，可以查看：\n\n'
              '🎮  你的完整游戏库\n'
              '⏱️  每款游戏的游玩时间\n'
              '📊  游戏时间统计和排行\n'
              '🕐  最近游玩的游戏',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _showSteamSettingsDialog,
              icon: const Icon(Icons.link_rounded),
              label: const Text('绑定 Steam 账号'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerProfileCard(Map<String, dynamic> player) {
    if (player.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final name = player['personaname'] ?? 'Unknown';
    final avatar = player['avatarfull'] ?? player['avatar'] ?? '';
    final profileUrl = player['profileurl'] ?? '';
    final personaState = player['personastate'] ?? 0;

    String statusText;
    Color statusColor;
    switch (personaState) {
      case 1:
        statusText = '在线';
        statusColor = Colors.green;
        break;
      case 2:
        statusText = '忙碌';
        statusColor = Colors.red;
        break;
      case 3:
        statusText = '离开';
        statusColor = Colors.amber;
        break;
      case 4:
        statusText = '打盹';
        statusColor = Colors.amber.shade700;
        break;
      case 5:
        statusText = '想交易';
        statusColor = Colors.cyan;
        break;
      case 6:
        statusText = '想玩';
        statusColor = Colors.lightGreen;
        break;
      default:
        statusText = '离线';
        statusColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: statusColor, width: 3),
            ),
            child: CircleAvatar(
              radius: 32,
              backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
              child: avatar.isEmpty
                  ? const Icon(Icons.person_rounded, size: 32)
                  : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 13,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (profileUrl.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              onPressed: () => InAppBrowserPage.open(
                context,
                url: profileUrl,
                title: 'Steam Profile',
              ),
              tooltip: '打开 Steam 主页',
            ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, size: 20),
            onPressed: _showSteamSettingsDialog,
            tooltip: '更改账号',
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1);
  }

  Widget _buildPlayerProfileSkeleton() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      height: 100,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildLibraryStats(List<dynamic> games) {
    final colorScheme = Theme.of(context).colorScheme;

    int totalPlaytime = 0;
    int recentlyPlayed = 0;
    int neverPlayed = 0;

    for (final g in games) {
      final game = g as Map<String, dynamic>;
      final pt = (game['playtime_forever'] as num?)?.toInt() ?? 0;
      final pt2w = (game['playtime_2weeks'] as num?)?.toInt() ?? 0;
      totalPlaytime += pt;
      if (pt2w > 0) recentlyPlayed++;
      if (pt == 0) neverPlayed++;
    }

    final totalHours = (totalPlaytime / 60).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _StatCard(
            icon: Icons.games_rounded,
            label: '总游戏',
            value: '${games.length}',
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          _StatCard(
            icon: Icons.access_time_rounded,
            label: '总时长',
            value: '${totalHours}h',
            color: Colors.blue,
          ),
          const SizedBox(width: 8),
          _StatCard(
            icon: Icons.play_arrow_rounded,
            label: '最近游玩',
            value: '$recentlyPlayed',
            color: Colors.green,
          ),
          const SizedBox(width: 8),
          _StatCard(
            icon: Icons.not_started_outlined,
            label: '未游玩',
            value: '$neverPlayed',
            color: Colors.orange,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 300.ms);
  }

  // ============================================================================
  // 每日 Top 30 推荐 Tab
  // ============================================================================

  Widget _buildRecommendationsTab() {
    final recAsync = ref.watch(dailyRecommendationsProvider);

    return recAsync.when(
      data: (data) {
        final items = (data['items'] as List?) ?? [];
        if (items.isEmpty) {
          return _buildEmptyState('暂无推荐\n请等待数据同步', Icons.recommend_rounded);
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(dailyRecommendationsProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildRecommendationHeader(items.length);
              }
              final game = items[index - 1] as Map<String, dynamic>;
              return _RecommendationTile(
                game: game,
                rank: index,
              ).animate().fadeIn(
                    delay: Duration(milliseconds: index * 40),
                    duration: 250.ms,
                  );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildErrorState('加载推荐失败: $e'),
    );
  }

  Widget _buildRecommendationHeader(int total) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepOrange.shade700,
            Colors.orange.shade500,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department_rounded,
              size: 48, color: Colors.white),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '每日 Top 30 推荐',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '综合 Steam 精选 · Epic 限免 · WASM 应用 · 共 $total 款',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withAlpha(200),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

  // ============================================================================
  // GitHub 导入对话框
  // ============================================================================

  void _showGitHubImportDialog() {
    final repoUrlCtrl = TextEditingController();
    final tagCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.code_rounded, color: colorScheme.primary),
              const SizedBox(width: 8),
              const Text('从 GitHub 导入'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '从 GitHub 仓库的 Release 下载 .wasm 文件',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: repoUrlCtrl,
                  decoration: InputDecoration(
                    labelText: '仓库地址',
                    hintText: 'https://github.com/user/repo',
                    prefixIcon: const Icon(Icons.link_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tagCtrl,
                  decoration: InputDecoration(
                    labelText: 'Release Tag（可选，默认 latest）',
                    hintText: 'v1.0.0',
                    prefixIcon: const Icon(Icons.sell_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: '应用名称（可选）',
                    hintText: '默认使用仓库名',
                    prefixIcon: const Icon(Icons.label_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: isLoading
                  ? null
                  : () async {
                      final url = repoUrlCtrl.text.trim();
                      if (url.isEmpty) return;
                      setDialogState(() => isLoading = true);
                      try {
                        final api = ref.read(apiServiceProvider);
                        final result = await api.importFromGitHub(
                          repoUrl: url,
                          tag: tagCtrl.text.trim().isEmpty
                              ? null
                              : tagCtrl.text.trim(),
                          name: nameCtrl.text.trim().isEmpty
                              ? null
                              : nameCtrl.text.trim(),
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '导入成功: ${result['name']} v${result['version']}'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          ref.invalidate(wasmStoreOverviewProvider);
                        }
                      } catch (e) {
                        setDialogState(() => isLoading = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('导入失败: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(isLoading ? '导入中...' : '导入'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // WASM 脚本执行对话框
  // ============================================================================

  void _showRunScriptDialog() {
    final sourceCtrl = TextEditingController();
    final funcCtrl = TextEditingController(text: '_start');
    final argsCtrl = TextEditingController();
    final stdinCtrl = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;
    bool isRunning = false;
    String? stdout;
    String? stderr;
    int? elapsedMs;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.terminal_rounded, color: colorScheme.primary),
              const SizedBox(width: 8),
              const Text('WASM 脚本执行'),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '执行已安装的 WASM 应用或远程 WASM URL',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: sourceCtrl,
                    decoration: InputDecoration(
                      labelText: 'WASM 源（app_id 或 URL）',
                      hintText: 'github-user-repo 或 https://...wasm',
                      prefixIcon: const Icon(Icons.source_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: funcCtrl,
                          decoration: InputDecoration(
                            labelText: '入口函数',
                            hintText: '_start',
                            prefixIcon: const Icon(Icons.functions_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: argsCtrl,
                          decoration: InputDecoration(
                            labelText: '参数（空格分隔）',
                            hintText: 'arg1 arg2',
                            prefixIcon: const Icon(Icons.list_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: stdinCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'stdin 输入（可选）',
                      hintText: '传递给 WASM 的标准输入数据',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (stdout != null || stderr != null) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        Text(
                          '执行完成 (${elapsedMs}ms)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    if (stdout != null && stdout!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('stdout:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          )),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          stdout!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ),
                    ],
                    if (stderr != null && stderr!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('stderr:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          )),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          stderr!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
            FilledButton.icon(
              onPressed: isRunning
                  ? null
                  : () async {
                      final source = sourceCtrl.text.trim();
                      if (source.isEmpty) return;
                      setDialogState(() {
                        isRunning = true;
                        stdout = null;
                        stderr = null;
                        elapsedMs = null;
                      });
                      try {
                        final api = ref.read(apiServiceProvider);
                        final argsText = argsCtrl.text.trim();
                        final result = await api.runWasmScript(
                          source: source,
                          function: funcCtrl.text.trim().isEmpty
                              ? null
                              : funcCtrl.text.trim(),
                          args: argsText.isEmpty
                              ? null
                              : argsText.split(RegExp(r'\s+')),
                          stdinData:
                              stdinCtrl.text.isEmpty ? null : stdinCtrl.text,
                        );
                        setDialogState(() {
                          isRunning = false;
                          stdout = result['stdout'] as String? ?? '';
                          stderr = result['stderr'] as String? ?? '';
                          elapsedMs = result['elapsed_ms'] as int? ?? 0;
                        });
                      } catch (e) {
                        setDialogState(() {
                          isRunning = false;
                          stderr = e.toString();
                          elapsedMs = 0;
                        });
                      }
                    },
              icon: isRunning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(isRunning ? '执行中...' : '执行'),
            ),
          ],
        ),
      ),
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
          return _buildEmptyState(
              '暂无 Steam 精选游戏\n可能是网络原因，请稍后重试', Icons.games_rounded);
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
          return _buildEmptyState(
              '暂无 Epic 免费游戏\n可能是网络原因，请稍后重试', Icons.card_giftcard_rounded);
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
              return _WasmAppTile(
                app: app,
                onTap: () => _openBuiltinApp(app),
              ).animate().fadeIn(
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

  /// 打开内置 WASM 应用的交互界面
  void _openBuiltinApp(Map<String, dynamic> app) {
    final appId = app['id'] as String? ?? '';
    switch (appId) {
      case 'steamdb-viewer':
        _showSteamDbDialog();
        break;
      case 'm3u8-downloader':
        _showM3u8DownloaderDialog();
        break;
      case 'steam-p2p-info':
        _showSteamP2PInfoDialog();
        break;
    }
  }

  /// SteamDB 数据查看器对话框
  void _showSteamDbDialog() {
    final appIdCtrl = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;
    Map<String, dynamic>? data;
    bool isLoading = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.storage_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text('SteamDB 数据查看器'),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.85,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: appIdCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Steam App ID',
                      hintText: '例如: 730 (CS2), 570 (Dota 2)',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isLoading) const LinearProgressIndicator(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!,
                          style: TextStyle(color: colorScheme.error)),
                    ),
                  if (data != null) ...[
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        child: _SteamDbResultCard(data: data!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
              FilledButton.icon(
                onPressed: isLoading
                    ? null
                    : () async {
                        final id = appIdCtrl.text.trim();
                        if (id.isEmpty) return;
                        setDialogState(() {
                          isLoading = true;
                          error = null;
                          data = null;
                        });
                        try {
                          final api = ref.read(apiServiceProvider);
                          final response = await api.get(
                            '/api/v1/wasm-store/builtin/steamdb-viewer/run?app_id=$id',
                          );
                          setDialogState(() {
                            isLoading = false;
                            data = response.data is Map<String, dynamic>
                                ? response.data as Map<String, dynamic>
                                : null;
                          });
                        } catch (e) {
                          setDialogState(() {
                            isLoading = false;
                            error = e.toString();
                          });
                        }
                      },
                icon: const Icon(Icons.search_rounded),
                label: const Text('查询'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// M3U8 下载器对话框
  void _showM3u8DownloaderDialog() {
    final urlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;
    Map<String, dynamic>? parseResult;
    bool isParsing = false;
    bool isDownloading = false;
    String? error;
    String? downloadStatus;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.download_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text('M3U8 视频下载器'),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.85,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: urlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'M3U8 URL',
                        hintText: 'https://example.com/video/index.m3u8',
                        prefixIcon: Icon(Icons.link_rounded),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '输出文件名（可选）',
                        hintText: 'video.ts',
                        prefixIcon: Icon(Icons.drive_file_rename_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isParsing || isDownloading)
                      const LinearProgressIndicator(),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(error!,
                            style: TextStyle(color: colorScheme.error)),
                      ),
                    if (downloadStatus != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(downloadStatus!,
                            style: TextStyle(color: colorScheme.primary)),
                      ),
                    if (parseResult != null) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('解析结果',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary)),
                              const SizedBox(height: 8),
                              Text(
                                  '分片数: ${parseResult!['total_segments'] ?? 0}'),
                              Text(
                                  '总时长: ${(parseResult!['total_duration'] as num?)?.toStringAsFixed(1) ?? '0'} 秒'),
                              if (parseResult!['encryption'] != null &&
                                  parseResult!['encryption']['encrypted'] ==
                                      true)
                                Text(
                                    '加密: ${parseResult!['encryption']['method']}',
                                    style: TextStyle(color: colorScheme.error)),
                              if (parseResult!['is_master_playlist'] == true)
                                Text(
                                    '变体流: ${(parseResult!['variant_streams'] as List?)?.length ?? 0} 个',
                                    style:
                                        TextStyle(color: colorScheme.tertiary)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
              OutlinedButton.icon(
                onPressed: isParsing
                    ? null
                    : () async {
                        final url = urlCtrl.text.trim();
                        if (url.isEmpty) return;
                        setDialogState(() {
                          isParsing = true;
                          error = null;
                          parseResult = null;
                        });
                        try {
                          final api = ref.read(apiServiceProvider);
                          final response = await api.get(
                            '/api/v1/wasm-store/builtin/m3u8-downloader/run?url=${Uri.encodeComponent(url)}',
                          );
                          setDialogState(() {
                            isParsing = false;
                            parseResult = response.data is Map<String, dynamic>
                                ? response.data as Map<String, dynamic>
                                : null;
                          });
                        } catch (e) {
                          setDialogState(() {
                            isParsing = false;
                            error = e.toString();
                          });
                        }
                      },
                icon: const Icon(Icons.analytics_rounded),
                label: const Text('解析'),
              ),
              FilledButton.icon(
                onPressed: isDownloading
                    ? null
                    : () async {
                        final url = urlCtrl.text.trim();
                        if (url.isEmpty) return;
                        setDialogState(() {
                          isDownloading = true;
                          error = null;
                          downloadStatus = '正在下载分片...';
                        });
                        try {
                          final api = ref.read(apiServiceProvider);
                          final response = await api.post(
                            '/api/v1/wasm-store/builtin/m3u8-downloader/download',
                            data: {
                              'url': url,
                              if (nameCtrl.text.trim().isNotEmpty)
                                'output_name': nameCtrl.text.trim(),
                            },
                          );
                          final result =
                              response.data as Map<String, dynamic>? ?? {};
                          setDialogState(() {
                            isDownloading = false;
                            downloadStatus =
                                '下载完成: ${result['downloaded_segments']}/${result['total_segments']} 分片\n'
                                '文件大小: ${_formatFileSize(result['file_size'] ?? 0)}';
                          });
                        } catch (e) {
                          setDialogState(() {
                            isDownloading = false;
                            error = e.toString();
                            downloadStatus = null;
                          });
                        }
                      },
                icon: const Icon(Icons.download_rounded),
                label: const Text('下载'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Steam P2P 连接信息对话框
  void _showSteamP2PInfoDialog() {
    final steamIdCtrl = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;
    Map<String, dynamic>? data;
    bool isLoading = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.lan_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Steam P2P 信息'),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.85,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: steamIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Steam ID',
                      hintText: '例如: 76561198000000000',
                      prefixIcon: Icon(Icons.person_search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isLoading) const LinearProgressIndicator(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!,
                          style: TextStyle(color: colorScheme.error)),
                    ),
                  if (data != null) ...[
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        child: _SteamP2PResultCard(data: data!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
              FilledButton.icon(
                onPressed: isLoading
                    ? null
                    : () async {
                        final id = steamIdCtrl.text.trim();
                        if (id.isEmpty) return;
                        setDialogState(() {
                          isLoading = true;
                          error = null;
                          data = null;
                        });
                        try {
                          final api = ref.read(apiServiceProvider);
                          final response = await api.get(
                            '/api/v1/wasm-store/builtin/steam-p2p-info/run?steam_id=$id',
                          );
                          setDialogState(() {
                            isLoading = false;
                            data = response.data is Map<String, dynamic>
                                ? response.data as Map<String, dynamic>
                                : null;
                          });
                        } catch (e) {
                          setDialogState(() {
                            isLoading = false;
                            error = e.toString();
                          });
                        }
                      },
                icon: const Icon(Icons.search_rounded),
                label: const Text('查询'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
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

/// 统计卡片
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            Text(
              label,
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

/// 游戏库列表项 (like 小黑盒 style)
class _LibraryGameTile extends StatelessWidget {
  final Map<String, dynamic> game;

  const _LibraryGameTile({required this.game});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = game['name'] ?? '';
    final headerImage = game['header_image'] ?? '';
    final playtimeFormatted = game['playtime_formatted'] ?? '0m';
    final playtimeHours = (game['playtime_hours'] as num?)?.toDouble() ?? 0;
    final playtime2weeks = (game['playtime_2weeks'] as num?)?.toInt() ?? 0;
    final lastPlayed = (game['rtime_last_played'] as num?)?.toInt() ?? 0;
    final playtimeWindows = (game['playtime_windows'] as num?)?.toInt() ?? 0;
    final playtimeLinux = (game['playtime_linux'] as num?)?.toInt() ?? 0;
    final playtimeMac = (game['playtime_mac'] as num?)?.toInt() ?? 0;

    // Last played time formatting
    String lastPlayedText = '';
    if (lastPlayed > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(lastPlayed * 1000);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) {
        lastPlayedText = '今天';
      } else if (diff.inDays == 1) {
        lastPlayedText = '昨天';
      } else if (diff.inDays < 7) {
        lastPlayedText = '${diff.inDays}天前';
      } else if (diff.inDays < 30) {
        lastPlayedText = '${(diff.inDays / 7).floor()}周前';
      } else if (diff.inDays < 365) {
        lastPlayedText = '${(diff.inDays / 30).floor()}个月前';
      } else {
        lastPlayedText = '${(diff.inDays / 365).floor()}年前';
      }
    }

    // Platform breakdown
    final platforms = <String>[];
    if (playtimeWindows > 0) {
      platforms.add('Win: ${_formatMinutes(playtimeWindows)}');
    }
    if (playtimeLinux > 0) {
      platforms.add('Linux: ${_formatMinutes(playtimeLinux)}');
    }
    if (playtimeMac > 0) {
      platforms.add('Mac: ${_formatMinutes(playtimeMac)}');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          final url = game['store_url'] ?? '';
          if (url.isNotEmpty) {
            InAppBrowserPage.open(
              context,
              url: url,
              title: game['name'] ?? '',
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Game header image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 100,
                  height: 47,
                  child: headerImage.isNotEmpty
                      ? Image.network(
                          headerImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: colorScheme.surfaceContainerLow,
                            child: const Icon(Icons.games_rounded, size: 20),
                          ),
                        )
                      : Container(
                          color: colorScheme.surfaceContainerLow,
                          child: const Icon(Icons.games_rounded, size: 20),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Game info
              Expanded(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded,
                            size: 12, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          playtimeFormatted,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: playtimeHours > 100
                                ? Colors.amber
                                : playtimeHours > 10
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (playtime2weeks > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '近2周 ${_formatMinutes(playtime2weeks)}',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.green),
                            ),
                          ),
                        ],
                        if (lastPlayedText.isNotEmpty) ...[
                          const Spacer(),
                          Text(
                            lastPlayedText,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (platforms.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        platforms.join(' | '),
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }
}

/// 平台登录卡片 — 多平台游戏库入口
class _PlatformLoginCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final bool isConnected;
  final VoidCallback onTap;

  const _PlatformLoginCard({
    required this.name,
    required this.icon,
    required this.color,
    required this.isConnected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isConnected
                ? Colors.greenAccent.withValues(alpha: 0.5)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: isConnected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 28, color: color),
                if (isConnected)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 10,
                          color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              isConnected ? '已连接' : '登录',
              style: TextStyle(
                fontSize: 9,
                color: isConnected ? Colors.green : colorScheme.onSurfaceVariant,
                fontWeight: isConnected ? FontWeight.w600 : FontWeight.normal,
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
    final isOwned = game['owned'] == true;

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
            // 封面图（带已拥有角标）
            Stack(
              children: [
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
                if (isOwned)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(50),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded,
                              size: 12, color: Colors.white),
                          SizedBox(width: 3),
                          Text(
                            '已拥有',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
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
                        _PlatformBadge(platform: platform),
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
      InAppBrowserPage.open(
        context,
        url: url,
        title: game['name'] ?? '',
      );
    }
  }
}

/// 推荐列表项（带排名编号和推荐来源）
class _RecommendationTile extends StatelessWidget {
  final Map<String, dynamic> game;
  final int rank;

  const _RecommendationTile({required this.game, required this.rank});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = game['name'] ?? '';
    final headerImage = game['header_image'] ?? '';
    final shortDesc = game['short_description'] ?? '';
    final price = game['price'] as Map<String, dynamic>?;
    final isFree = game['is_free'] == true;
    final platform = game['platform'] ?? '';
    final isOwned = game['owned'] == true;
    final source = game['recommendation_source'] ?? '';

    Color rankColor;
    if (rank <= 3) {
      rankColor = Colors.deepOrange;
    } else if (rank <= 10) {
      rankColor = Colors.orange;
    } else {
      rankColor = colorScheme.onSurfaceVariant;
    }

    String sourceLabel;
    Color sourceColor;
    IconData sourceIcon;
    switch (source) {
      case 'steam_featured':
        sourceLabel = 'Steam 精选';
        sourceColor = Colors.blue;
        sourceIcon = Icons.star_rounded;
        break;
      case 'epic_free':
        sourceLabel = 'Epic 限免';
        sourceColor = Colors.purple;
        sourceIcon = Icons.card_giftcard_rounded;
        break;
      case 'wasm_store':
        sourceLabel = 'WASM 应用';
        sourceColor = Colors.teal;
        sourceIcon = Icons.web_asset_rounded;
        break;
      default:
        sourceLabel = '推荐';
        sourceColor = colorScheme.primary;
        sourceIcon = Icons.recommend_rounded;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          final url = game['store_url'] ?? '';
          if (url.isNotEmpty) {
            InAppBrowserPage.open(
              context,
              url: url,
              title: game['name'] ?? '',
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 排名编号
              SizedBox(
                width: 32,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: rank <= 3 ? 22 : 16,
                    fontWeight: FontWeight.bold,
                    color: rankColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 缩略图
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 100,
                  height: 56,
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isOwned)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                              border:
                                  Border.all(color: Colors.green.withAlpha(80)),
                            ),
                            child: const Text(
                              '已拥有',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (shortDesc.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        shortDesc,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // 平台标签
                        _PlatformBadge(platform: platform),
                        const SizedBox(width: 6),
                        // 推荐来源
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: sourceColor.withAlpha(20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(sourceIcon, size: 10, color: sourceColor),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    sourceLabel,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: sourceColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 价格
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

/// 平台标签组件（统一样式 Steam / Epic / WASM）
class _PlatformBadge extends StatelessWidget {
  final String platform;

  const _PlatformBadge({required this.platform});

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    IconData icon;

    switch (platform.toLowerCase()) {
      case 'steam':
        label = 'Steam';
        color = const Color(0xFF1B2838);
        icon = Icons.videogame_asset_rounded;
        break;
      case 'epic':
        label = 'Epic';
        color = Colors.deepPurple;
        icon = Icons.gamepad_rounded;
        break;
      case 'wasm':
        label = 'WASM';
        color = Colors.teal;
        icon = Icons.web_asset_rounded;
        break;
      default:
        label = platform;
        color = Colors.grey;
        icon = Icons.apps_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 游戏列表项（带平台标签和已拥有标记）
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
    final isOwned = game['owned'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          final url = game['store_url'] ?? '';
          if (url.isNotEmpty) {
            InAppBrowserPage.open(
              context,
              url: url,
              title: game['name'] ?? '',
            );
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isOwned)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                              border:
                                  Border.all(color: Colors.green.withAlpha(80)),
                            ),
                            child: const Text(
                              '已拥有',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
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
                        _PlatformBadge(platform: platform),
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
  final VoidCallback? onTap;

  const _WasmAppTile({required this.app, this.onTap});

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
        onTap: onTap,
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
    switch (category.toString().toLowerCase()) {
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
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
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

/// SteamDB 查询结果展示卡片
class _SteamDbResultCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _SteamDbResultCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = data['name'] as String? ?? '未知';
    final headerImage = data['header_image'] as String? ?? '';
    final shortDesc = data['short_description'] as String? ?? '';
    final isFree = data['is_free'] == true;
    final currentPlayers = data['current_players'];
    final reviewDesc = data['review_score_desc'] as String?;
    final totalPositive = data['total_positive'] as int? ?? 0;
    final totalNegative = data['total_negative'] as int? ?? 0;
    final totalReviews = data['total_reviews'] as int? ?? 0;
    final dlcCount = data['dlc_count'] as int? ?? 0;
    final developers =
        (data['developers'] as List?)?.cast<String>().join(', ') ?? '';
    final publishers =
        (data['publishers'] as List?)?.cast<String>().join(', ') ?? '';
    final metacritic = data['metacritic'] as Map<String, dynamic>?;
    final releaseDate = data['release_date'] as Map<String, dynamic>?;
    final platforms = data['platforms'] as Map<String, dynamic>?;
    final price = data['price'] as Map<String, dynamic>?;
    final genres = data['genres'] as List?;
    final categories = data['categories'] as List?;

    // 好评率
    final positiveRate =
        totalReviews > 0 ? (totalPositive * 100 ~/ totalReviews) : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部图片
        if (headerImage.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              headerImage,
              width: double.infinity,
              height: 120,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 120,
                color: colorScheme.surfaceContainerLow,
                child: const Center(child: Icon(Icons.image_not_supported)),
              ),
            ),
          ),
        const SizedBox(height: 12),

        // 游戏名称
        Text(
          name,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),

        // 简介
        if (shortDesc.isNotEmpty)
          Text(
            shortDesc,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 12),

        // 核心数据网格
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatChip(
              icon: Icons.people_alt_rounded,
              label: '在线',
              value: currentPlayers != null
                  ? _formatNumber(currentPlayers as int)
                  : 'N/A',
              color: Colors.blue,
            ),
            if (reviewDesc != null)
              _StatChip(
                icon: Icons.thumb_up_rounded,
                label: reviewDesc,
                value: '$positiveRate%',
                color: positiveRate >= 70
                    ? Colors.green
                    : positiveRate >= 40
                        ? Colors.orange
                        : Colors.red,
              ),
            if (metacritic != null && metacritic['score'] != null)
              _StatChip(
                icon: Icons.star_rounded,
                label: 'Metacritic',
                value: '${metacritic['score']}',
                color: Colors.amber,
              ),
            _StatChip(
              icon: Icons.monetization_on_rounded,
              label: '价格',
              value: isFree
                  ? '免费'
                  : price?['final_formatted'] as String? ??
                      (price != null
                          ? '¥${((price['final'] as int? ?? 0) / 100).toStringAsFixed(0)}'
                          : 'N/A'),
              color: isFree ? Colors.green : colorScheme.primary,
            ),
            if (dlcCount > 0)
              _StatChip(
                icon: Icons.extension_rounded,
                label: 'DLC',
                value: '$dlcCount',
                color: Colors.purple,
              ),
          ],
        ),
        const SizedBox(height: 12),

        // 平台支持
        if (platforms != null)
          Row(
            children: [
              Text('平台: ',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface)),
              if (platforms['windows'] == true)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.desktop_windows_rounded,
                      size: 16, color: colorScheme.primary),
                ),
              if (platforms['mac'] == true)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.laptop_mac_rounded,
                      size: 16, color: colorScheme.primary),
                ),
              if (platforms['linux'] == true)
                Icon(Icons.computer_rounded,
                    size: 16, color: colorScheme.primary),
            ],
          ),
        const SizedBox(height: 8),

        // 开发者/发行商
        if (developers.isNotEmpty) _InfoRow(label: '开发', value: developers),
        if (publishers.isNotEmpty) _InfoRow(label: '发行', value: publishers),
        if (releaseDate != null)
          _InfoRow(label: '发售', value: releaseDate['date'] as String? ?? ''),

        // 类别标签
        if (genres != null && genres.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: genres.take(6).map((g) {
              final desc =
                  g is Map<String, dynamic> ? (g['description'] ?? '') : '$g';
              return Chip(
                label:
                    Text(desc.toString(), style: const TextStyle(fontSize: 10)),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],

        // 功能特性标签
        if (categories != null && categories.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('功能',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: categories.take(8).map((c) {
              final desc =
                  c is Map<String, dynamic> ? (c['description'] ?? '') : '$c';
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withAlpha(100),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(desc.toString(),
                    style: TextStyle(
                        fontSize: 10, color: colorScheme.onSecondaryContainer)),
              );
            }).toList(),
          ),
        ],

        // 评价详情
        if (totalReviews > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.thumb_up_alt_rounded,
                  size: 14, color: Colors.green.shade700),
              const SizedBox(width: 4),
              Text('$totalPositive',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
              const SizedBox(width: 12),
              Icon(Icons.thumb_down_alt_rounded,
                  size: 14, color: Colors.red.shade700),
              const SizedBox(width: 4),
              Text('$totalNegative',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              const SizedBox(width: 12),
              Text('共 $totalReviews 条评价',
                  style: TextStyle(
                      fontSize: 11, color: colorScheme.onSurfaceVariant)),
            ],
          ),
        ],
      ],
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Steam P2P 连接信息结果卡片
class _SteamP2PResultCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _SteamP2PResultCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final player = data['player'] as Map<String, dynamic>?;
    final friendsCount = data['friends_count'] as int?;
    final recentGames = data['recent_games'] as List?;
    final p2pInfo = data['p2p_info'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 玩家信息卡
        if (player != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // 头像
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: player['avatar'] != null
                        ? NetworkImage(player['avatar'] as String)
                        : null,
                    child: player['avatar'] == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  // 信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player['name'] as String? ?? '未知玩家',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              _getStatusIcon(player['status']),
                              size: 12,
                              color: _getStatusColor(player['status']),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getStatusText(player['status']),
                              style: TextStyle(
                                fontSize: 12,
                                color: _getStatusColor(player['status']),
                              ),
                            ),
                          ],
                        ),
                        if (player['game_name'] != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.sports_esports_rounded,
                                  size: 12, color: Colors.green),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '正在玩: ${player['game_name']}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.green),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 好友数
                  if (friendsCount != null)
                    Column(
                      children: [
                        Text(
                          '$friendsCount',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                        Text(
                          '好友',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 最近游戏
        if (recentGames != null && recentGames.isNotEmpty) ...[
          Text(
            '最近游玩',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ...recentGames.take(5).map((game) {
            final g = game as Map<String, dynamic>;
            final gameName = g['name'] as String? ?? '未知游戏';
            final playtime2w = g['playtime_2weeks'] as int? ?? 0;
            final playtimeForever = g['playtime_forever'] as int? ?? 0;
            final hasP2p = g['has_p2p'] == true;
            final appid = g['appid'] as int? ?? 0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  // 游戏图标
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: g['img_icon_url'] != null
                          ? Image.network(
                              'https://media.steampowered.com/steamcommunity/public/images/apps/$appid/${g['img_icon_url']}.jpg',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: colorScheme.surfaceContainerLow,
                                child: const Icon(Icons.sports_esports_rounded,
                                    size: 16),
                              ),
                            )
                          : Container(
                              color: colorScheme.surfaceContainerLow,
                              child: const Icon(Icons.sports_esports_rounded,
                                  size: 16),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 游戏名和时长
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gameName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Text(
                              '近2周 ${(playtime2w / 60).toStringAsFixed(1)}h',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '总计 ${(playtimeForever / 60).toStringAsFixed(1)}h',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // P2P 标记
                  if (hasP2p)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.teal.withAlpha(25),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.teal.withAlpha(80)),
                      ),
                      child: const Text(
                        'P2P',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.teal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
        ],

        // P2P 连接类型
        if (p2pInfo != null) ...[
          Text(
            'P2P 连接模式',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          if (p2pInfo['connection_types'] is List)
            ...((p2pInfo['connection_types'] as List).map((ct) {
              final c = ct as Map<String, dynamic>;
              final type_ = c['type'] as String? ?? '';
              final desc = c['description'] as String? ?? '';
              IconData icon;
              Color color;
              switch (type_) {
                case 'lan':
                  icon = Icons.lan_rounded;
                  color = Colors.green;
                  break;
                case 'direct':
                  icon = Icons.swap_horiz_rounded;
                  color = Colors.blue;
                  break;
                case 'relay':
                  icon = Icons.cloud_rounded;
                  color = Colors.orange;
                  break;
                default:
                  icon = Icons.help_outline;
                  color = Colors.grey;
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 8),
                    Text(
                      type_.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        desc,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            })),
          const SizedBox(height: 8),
          // 提示
          if (p2pInfo['note'] != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withAlpha(80),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: colorScheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p2pInfo['note'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  IconData _getStatusIcon(dynamic status) {
    switch (status) {
      case 1:
        return Icons.circle;
      case 2:
        return Icons.do_not_disturb_on_rounded;
      case 3:
        return Icons.access_time_rounded;
      case 4:
        return Icons.snooze_rounded;
      default:
        return Icons.circle_outlined;
    }
  }

  Color _getStatusColor(dynamic status) {
    switch (status) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.red;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(dynamic status) {
    switch (status) {
      case 0:
        return '离线';
      case 1:
        return '在线';
      case 2:
        return '忙碌';
      case 3:
        return '离开';
      case 4:
        return '打盹';
      case 5:
        return '想交易';
      case 6:
        return '想玩';
      default:
        return '离线';
    }
  }
}

/// 数据统计小标签
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: color.withAlpha(180),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 信息行（标签 + 值）
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
