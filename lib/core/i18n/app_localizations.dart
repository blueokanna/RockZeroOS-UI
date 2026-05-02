import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh', 'CN'),
  ];

  static AppLocalizations of(BuildContext context) {
    final localizations = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    assert(localizations != null, 'AppLocalizations not found in context');
    return localizations!;
  }

  bool get isChinese => locale.languageCode.toLowerCase().startsWith('zh');

  String tr(String key, [Map<String, String> args = const {}]) {
    final languageCode = isChinese ? 'zh' : 'en';
    final template = _localizedValues[languageCode]?[key] ??
        _localizedValues['en']?[key] ??
        key;
    return args.entries.fold<String>(template, (value, entry) {
      return value.replaceAll('{${entry.key}}', entry.value);
    });
  }

  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'app.title': 'RockZero',
      'appstore.title': 'Game Hub',
      'appstore.refresh': 'Refresh',
      'appstore.more': 'More',
      'appstore.menu.lan_transfer': 'LAN Transfer',
      'appstore.menu.github_import': 'GitHub Import',
      'appstore.menu.wasm_script': 'Run WASM Script',
      'appstore.menu.steam_settings': 'Steam Settings',
      'appstore.hero.summary':
          '{games} games · {free} free · {saved} saved{live}',
      'appstore.hero.live': ' · Live',
      'appstore.search_hint': 'Search {platform} games...',
      'appstore.search_global_hint': 'Search games, apps, plugins...',
      'appstore.search_empty': 'No matching results for "{query}"',
      'appstore.category_empty': 'No games in this category yet',
      'appstore.section.featured': 'Featured Picks',
      'appstore.section.free': 'Free to Play',
      'appstore.section.saved': 'Saved Library',
      'appstore.section.all': 'All Games',
      'appstore.section.no_saved': 'No saved games yet',
      'appstore.action.save': 'Save',
      'appstore.action.saved': 'Saved',
      'appstore.action.details': 'Details',
      'appstore.action.open': 'Open',
      'appstore.action.play_free': 'Play Free',
      'appstore.action.get': 'Get',
      'appstore.price.free': 'Free',
      'appstore.price.unknown': 'Unknown',
      'appstore.saved.added': 'Saved {name}',
      'appstore.saved.removed': 'Removed {name}',
      'appstore.info.description': 'About This Game',
      'appstore.info.developer': 'Developer',
      'appstore.info.type': 'Genre',
      'appstore.info.price': 'Price',
      'appstore.info.platform': 'Platform',
      'appstore.info.rating': 'Rating',
      'appstore.info.store': 'Store',
      'appstore.info.source': 'Data Source',
      'appstore.info.live_api': 'Official live API feed',
      'appstore.category.action': 'Action',
      'appstore.category.adventure': 'Adventure',
      'appstore.category.shooter': 'Shooter',
      'appstore.category.open_world': 'Open World',
      'appstore.category.free': 'Free',
      'appstore.category.strategy': 'Strategy',
      'appstore.category.racing': 'Racing',
      'appstore.category.fighting': 'Fighting',
      'appstore.category.rpg': 'RPG',
      'appstore.category.moba': 'MOBA',
      'appstore.platform.epic.subtitle': 'Epic Games Store · Weekly free games',
      'appstore.platform.wegame.subtitle':
          'Tencent gaming platform · Premium catalog',
      'appstore.platform.ubisoft.subtitle': 'Ubisoft Connect · Ubisoft worlds',
      'appstore.platform.xbox.subtitle':
          'Xbox ecosystem · Console and cloud gaming',
      'appstore.tab.recommended': 'Recommended',
      'appstore.tab.daily_top': 'Daily Top 30',
      'appstore.tab.library': 'My Library',
      'appstore.tab.epic': 'Epic Games',
      'appstore.tab.wasm_apps': 'WASM Apps',
      'appstore.tab.plugins': 'Plugins',
      'speedtest.error.not_connected': 'Not connected to NAS',
      'speedtest.phase.latency': 'Measuring latency...',
      'speedtest.phase.download': 'Testing download...',
      'speedtest.phase.upload': 'Testing upload...',
      'speedtest.phase.complete': 'Complete',
      'speedtest.device.not_connected': 'NAS Not Connected',
      'speedtest.device.connected': 'Connected',
      'speedtest.metric.download': 'DOWNLOAD',
      'speedtest.metric.upload': 'UPLOAD',
      'speedtest.metric.ping': 'PING',
      'speedtest.metric.jitter': 'JITTER',
      'speedtest.action.testing': 'Testing...',
      'speedtest.action.start': 'Start Speed Test',
      'video.loading.connecting': 'Establishing secure connection...',
      'video.loading.fetch_credentials': 'Loading credentials...',
      'video.loading.retry_connecting':
          'Network unstable, retrying... ({attempt}/{total})',
      'video.loading.handshake': 'Performing SAE secure handshake...',
      'video.loading.starting_proxy': 'Starting secure proxy...',
      'video.loading.waiting_segments': 'Waiting for video segments...',
      'video.loading.waiting_segments_seconds':
          'Waiting for video segments... ({seconds}s)',
      'video.loading.initializing_player': 'Initializing player...',
      'video.loading.detail':
          'SAE secure handshake → AES-256 at-rest encryption → session authorization',
      'video.network.stable': 'Network stable',
      'video.network.fair': 'Network fair',
      'video.network.poor': 'Network poor',
      'video.network.summary': '{quality}  Buffer {seconds}s',
      'video.network.retry_up': 'Retry trend +{count}',
      'video.network.retry_steady': 'Retry trend steady',
      'video.error.not_logged_in': 'Not signed in. Please sign in first.',
      'video.error.missing_credentials':
          'Unable to load user credentials. Please sign in again.',
      'video.error.play_failed': 'Playback failed: {message}',
      'video.error.play_init_failed':
          'Playback initialization failed: {message}',
      'video.error.session_create_rejected':
          'Session creation was rejected because external cache is unavailable.\nCheck whether HLS_CACHE_PATH points to mounted external storage, or disable ROCKZERO_STRICT_EXTERNAL_HLS_CACHE.\nBackend message: {message}',
      'video.error.session_create_failed':
          'Session creation failed ({status}): {message}',
      'video.error.sae_stage_failed':
          'SAE secure handshake failed ({stage}/{status}): {message}',
      'video.error.sae_failed': 'SAE secure handshake failed: {message}',
      'video.error.session_rebuild_failed': 'Session rebuild failed: {message}',
      'video.error.proxy_start_failed':
          'Failed to start secure proxy: {message}',
      'video.error.playlist_auth_failed':
          'Playback authorization failed ({status}). Please sign in again and retry.',
      'video.error.segment_service_failed':
          'The server segment service returned an error ({status}). Please try again later.',
      'video.error.playlist_timeout':
          'Playlist generation timed out after 90 seconds. Check the video codec or server FFmpeg configuration.',
      'video.error.transcoding_failed':
          'Server transcoding failed. Please try again later.',
      'video.error.segment_unavailable':
          'Video segments are temporarily unavailable. Retry after the server finishes generating or rebuilding the cache.',
      'video.error.segment_generating':
          'Video segments are still being generated. Please try again shortly.',
      'video.error.connection_timeout':
          'Connection timed out. Check your network and try again.',
      'video.error.network_unstable':
          'Network connection is unstable. Check your network and retry.',
      'video.error.handshake_failed':
          'Secure handshake failed. Please sign in again.',
      'video.error.download_dir_unavailable':
          'Unable to resolve the download directory.',
      'video.error.unknown': 'Unknown error',
      'video.resume.prompt':
          'Detected a previous position at {position}. Resume playback?',
      'video.resume.continue': 'Resume',
      'video.permission.storage_required': 'Storage permission is required.',
      'video.download.completed': 'Downloaded to {path}',
      'video.download.failed': 'Download failed: {message}',
      'video.download.http_failed': 'Download failed: HTTP {status}',
      'video.download.recovered_task':
          'An incomplete download was detected and resumed automatically.',
      'video.download.recovered_done':
          'The previous incomplete download has been recovered and completed.',
      'video.download.recovered_failed':
          'Failed to resume the previous download: {message}',
      'video.download.progress': 'Downloading...',
      'video.action.download_original': 'Download original file',
      'video.action.retry': 'Retry',
      'video.action.back': 'Back',
      'video.runtime.rebuilding_session': 'Rebuilding session',
      'video.runtime.zkp_path': 'ZKP path',
      'video.runtime.session_path': 'Session path',
      'video.runtime.fallback_active': 'Fallback active',
      'video.runtime.direct_verified': 'Direct verification',
      'video.runtime.retries': 'Retries {count}',
      'video.runtime.proof_stats': 'Proof {requests}/{failures}',
      'video.control.playback_speed': 'Playback speed',
      'video.encryption.title': 'End-to-end encryption protection',
      'video.encryption.subtitle_verified':
          'SAE + AES-256-GCM + ZKP verified segment path + Blake3',
      'video.encryption.subtitle_fallback':
          'SAE + AES-256-GCM + encrypted GET fallback + Blake3',
      'video.encryption.session_info': 'Session Info',
      'video.encryption.session_label': 'Session: {sessionId}',
      'video.encryption.transport_mode': 'Transport mode: {mode}',
      'video.encryption.transport_mode_verified': 'ZKP POST + AES-256-GCM',
      'video.encryption.transport_mode_fallback':
          'ZKP + Encrypted GET Fallback',
      'video.status.enabled': 'Enabled',
      'video.encryption.node.key_exchange.title': 'Key Exchange',
      'video.encryption.node.key_exchange.detail':
          'Dragonfly key exchange resists offline dictionary attacks and establishes the secure session.',
      'video.encryption.node.at_rest.title': 'At-rest Encryption',
      'video.encryption.node.at_rest.detail':
          'Cached video segments on disk use AES-256-GCM, so physical access alone cannot reveal the content.',
      'video.encryption.node.segment_auth.title': 'Segment Authorization',
      'video.encryption.node.segment_auth.detail_verified':
          'Each segment request is validated with a ZKP proof. If validation fails, the session is rebuilt and retried automatically.',
      'video.encryption.node.segment_auth.detail_fallback':
          'Proof validation failed and switched to encrypted GET fallback. Segments are still transferred with AES-256-GCM protection.',
      'video.encryption.node.runtime.title': 'Runtime Status',
      'video.encryption.node.runtime.detail':
          'Proof requests: {requests}, failures: {failures}, segment retries: {retries}',
    },
    'zh': {
      'app.title': 'RockZero',
      'appstore.title': '游戏中心',
      'appstore.refresh': '刷新',
      'appstore.more': '更多',
      'appstore.menu.lan_transfer': '局域网传输',
      'appstore.menu.github_import': 'GitHub 导入',
      'appstore.menu.wasm_script': '运行 WASM 脚本',
      'appstore.menu.steam_settings': 'Steam 设置',
      'appstore.hero.summary': '{games} 款游戏 · {free} 款免费 · {saved} 款已收藏{live}',
      'appstore.hero.live': ' · 实时',
      'appstore.search_hint': '搜索 {platform} 游戏...',
      'appstore.search_global_hint': '搜索游戏、应用、插件...',
      'appstore.search_empty': '未找到匹配“{query}”的游戏',
      'appstore.category_empty': '该分类暂无游戏',
      'appstore.section.featured': '精选推荐',
      'appstore.section.free': '免费游戏',
      'appstore.section.saved': '已收藏',
      'appstore.section.all': '全部游戏',
      'appstore.section.no_saved': '还没有收藏的游戏',
      'appstore.action.save': '收藏',
      'appstore.action.saved': '已收藏',
      'appstore.action.details': '详情',
      'appstore.action.open': '打开',
      'appstore.action.play_free': '免费游玩',
      'appstore.action.get': '获取',
      'appstore.price.free': '免费',
      'appstore.price.unknown': '未知',
      'appstore.saved.added': '已收藏 {name}',
      'appstore.saved.removed': '已取消收藏 {name}',
      'appstore.info.description': '游戏简介',
      'appstore.info.developer': '开发商',
      'appstore.info.type': '类型',
      'appstore.info.price': '价格',
      'appstore.info.platform': '平台',
      'appstore.info.rating': '评分',
      'appstore.info.store': '商店',
      'appstore.info.source': '数据来源',
      'appstore.info.live_api': '官方 API 实时数据',
      'appstore.category.action': '动作',
      'appstore.category.adventure': '冒险',
      'appstore.category.shooter': '射击',
      'appstore.category.open_world': '开放世界',
      'appstore.category.free': '免费',
      'appstore.category.strategy': '策略',
      'appstore.category.racing': '竞速',
      'appstore.category.fighting': '格斗',
      'appstore.category.rpg': 'RPG',
      'appstore.category.moba': 'MOBA',
      'appstore.platform.epic.subtitle': 'Epic Games Store · 每周免费游戏',
      'appstore.platform.wegame.subtitle': '腾讯游戏平台 · 海量精品游戏',
      'appstore.platform.ubisoft.subtitle': 'Ubisoft Connect · 育碧世界',
      'appstore.platform.xbox.subtitle': 'Xbox 生态 · 主机与云游戏',
      'appstore.tab.recommended': '推荐',
      'appstore.tab.daily_top': '每日Top30',
      'appstore.tab.library': '我的游戏库',
      'appstore.tab.epic': 'Epic Game',
      'appstore.tab.wasm_apps': 'WASM 应用',
      'appstore.tab.plugins': '插件',
      'speedtest.error.not_connected': '未连接到 NAS',
      'speedtest.phase.latency': '正在测量延迟...',
      'speedtest.phase.download': '正在测试下载...',
      'speedtest.phase.upload': '正在测试上传...',
      'speedtest.phase.complete': '完成',
      'speedtest.device.not_connected': 'NAS 未连接',
      'speedtest.device.connected': '已连接',
      'speedtest.metric.download': '下载',
      'speedtest.metric.upload': '上传',
      'speedtest.metric.ping': '延迟',
      'speedtest.metric.jitter': '抖动',
      'speedtest.action.testing': '测试中...',
      'speedtest.action.start': '开始测速',
      'video.loading.connecting': '正在建立安全连接...',
      'video.loading.fetch_credentials': '正在获取凭据...',
      'video.loading.retry_connecting': '网络波动，正在重试连接... ({attempt}/{total})',
      'video.loading.handshake': '正在执行 SAE 安全握手...',
      'video.loading.starting_proxy': '正在启动安全代理...',
      'video.loading.waiting_segments': '正在等待视频分片...',
      'video.loading.waiting_segments_seconds': '正在等待视频分片... ({seconds}s)',
      'video.loading.initializing_player': '正在初始化播放器...',
      'video.loading.detail': 'SAE 安全握手 → AES-256 静态加密 → Session 鉴权',
      'video.network.stable': '网络稳定',
      'video.network.fair': '网络一般',
      'video.network.poor': '网络较差',
      'video.network.summary': '{quality}  缓冲 {seconds}s',
      'video.network.retry_up': '重试趋势 +{count}',
      'video.network.retry_steady': '重试趋势 平稳',
      'video.error.not_logged_in': '未登录，请先登录',
      'video.error.missing_credentials': '无法获取用户凭据，请重新登录',
      'video.error.play_failed': '播放失败: {message}',
      'video.error.play_init_failed': '播放初始化失败: {message}',
      'video.error.session_create_rejected':
          '会话创建被拒绝（外部缓存不可用）。\n请检查 HLS_CACHE_PATH 是否指向已挂载外部存储，或关闭 ROCKZERO_STRICT_EXTERNAL_HLS_CACHE。\n后端信息: {message}',
      'video.error.session_create_failed': '会话创建失败({status}): {message}',
      'video.error.sae_stage_failed': 'SAE 安全握手失败({stage}/{status}): {message}',
      'video.error.sae_failed': 'SAE 安全握手失败: {message}',
      'video.error.session_rebuild_failed': '会话重建失败: {message}',
      'video.error.proxy_start_failed': '安全代理启动失败: {message}',
      'video.error.playlist_auth_failed': '播放鉴权失败({status})，请重新登录后重试',
      'video.error.segment_service_failed': '服务器分片服务异常({status})，请稍后重试',
      'video.error.playlist_timeout':
          '播放列表生成超时（已等待 90 秒），请检查视频编码格式或服务器 ffmpeg 配置',
      'video.error.transcoding_failed': '服务器转码失败，请稍后重试',
      'video.error.segment_unavailable': '视频分片暂不可用，请重试（服务器正在生成或缓存已过期）',
      'video.error.segment_generating': '视频分片仍在生成中，请稍后重试',
      'video.error.connection_timeout': '连接超时，请检查网络',
      'video.error.network_unstable': '网络连接不稳定，请检查网络后重试',
      'video.error.handshake_failed': '安全握手失败，请重新登录',
      'video.error.download_dir_unavailable': '无法获取下载目录',
      'video.error.unknown': '未知错误',
      'video.resume.prompt': '检测到上次播放到 {position}，是否继续？',
      'video.resume.continue': '继续播放',
      'video.permission.storage_required': '需要存储权限',
      'video.download.completed': '已下载到 {path}',
      'video.download.failed': '下载失败: {message}',
      'video.download.http_failed': '下载失败: HTTP {status}',
      'video.download.recovered_task': '检测到未完成下载，已自动恢复任务',
      'video.download.recovered_done': '已恢复并完成上次未完成的下载',
      'video.download.recovered_failed': '恢复下载失败: {message}',
      'video.download.progress': '下载中...',
      'video.action.download_original': '下载原文件',
      'video.action.retry': '重试',
      'video.action.back': '返回',
      'video.runtime.rebuilding_session': '会话重建中',
      'video.runtime.zkp_path': 'ZKP 链路',
      'video.runtime.session_path': '会话链路',
      'video.runtime.fallback_active': 'Fallback 激活',
      'video.runtime.direct_verified': '直连验证',
      'video.runtime.retries': '重试 {count}',
      'video.runtime.proof_stats': 'proof {requests}/{failures}',
      'video.control.playback_speed': '播放速度',
      'video.encryption.title': '端到端加密保护',
      'video.encryption.subtitle_verified':
          'SAE + AES-256-GCM + ZKP 校验分片链路 + Blake3',
      'video.encryption.subtitle_fallback':
          'SAE + AES-256-GCM + 加密 GET 兜底链路 + Blake3',
      'video.encryption.session_info': '会话信息',
      'video.encryption.session_label': '会话: {sessionId}',
      'video.encryption.transport_mode': '传输模式: {mode}',
      'video.encryption.transport_mode_verified': 'ZKP POST + AES-256-GCM',
      'video.encryption.transport_mode_fallback':
          'ZKP + Encrypted GET Fallback',
      'video.status.enabled': '已启用',
      'video.encryption.node.key_exchange.title': '密钥交换',
      'video.encryption.node.key_exchange.detail':
          'Dragonfly 密钥交换协议可抵抗离线字典攻击，并建立安全会话。',
      'video.encryption.node.at_rest.title': '静态存储加密',
      'video.encryption.node.at_rest.detail':
          '磁盘上的缓存视频段使用 AES-256-GCM 加密，即使获得物理访问权限也无法直接读取。',
      'video.encryption.node.segment_auth.title': '分片访问鉴权',
      'video.encryption.node.segment_auth.detail_verified':
          '当前分片请求通过 ZKP proof 校验，失败时会自动重建会话并重试。',
      'video.encryption.node.segment_auth.detail_fallback':
          '检测到 proof 失败后已切换到加密 GET 兜底，分片传输仍保持 AES-256-GCM 保护。',
      'video.encryption.node.runtime.title': '链路运行状态',
      'video.encryption.node.runtime.detail':
          'proof 请求: {requests}，失败: {failures}，分片重试: {retries}',
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales.any(
      (supportedLocale) => supportedLocale.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsBuildContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
