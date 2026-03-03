import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// 平台配置 & 游戏数据模型
// ============================================================================

enum GamePlatform { wegame, ubisoft, xbox }

/// 游戏数据模型 — 包含完整的游戏信息用于原生展示
class GameData {
  final String id;
  final String name;
  final String developer;
  final String genre;
  final String? price; // null = 未知
  final bool isFree;
  final double rating; // 0.0 - 5.0
  final String description;
  final List<String> tags;
  final List<Color> coverGradient; // 封面渐变色
  final IconData coverIcon; // 封面图标
  final bool isFeatured;

  const GameData({
    required this.id,
    required this.name,
    required this.developer,
    required this.genre,
    this.price,
    this.isFree = false,
    required this.rating,
    required this.description,
    this.tags = const [],
    required this.coverGradient,
    required this.coverIcon,
    this.isFeatured = false,
  });
}

/// 平台配置（品牌色、图标、游戏目录等）
class PlatformConfig {
  final String name;
  final String subtitle;
  final Color brandColor;
  final Color brandColorLight;
  final IconData icon;
  final List<GameCategory> categories;
  final List<GameData> allGames;

  const PlatformConfig({
    required this.name,
    required this.subtitle,
    required this.brandColor,
    required this.brandColorLight,
    required this.icon,
    required this.categories,
    required this.allGames,
  });

  List<GameData> get featuredGames =>
      allGames.where((g) => g.isFeatured).toList();
  List<GameData> get freeGames => allGames.where((g) => g.isFree).toList();

  List<GameData> gamesInCategory(String category) =>
      allGames.where((g) => g.genre == category).toList();

  static PlatformConfig forPlatform(GamePlatform platform) {
    switch (platform) {
      case GamePlatform.wegame:
        return _wegameConfig;
      case GamePlatform.ubisoft:
        return _ubisoftConfig;
      case GamePlatform.xbox:
        return _xboxConfig;
    }
  }
}

class GameCategory {
  final String name;
  final IconData icon;
  const GameCategory(this.name, this.icon);
}

// ============================================================================
// WeGame 游戏数据
// ============================================================================

final PlatformConfig _wegameConfig = PlatformConfig(
  name: 'WeGame',
  subtitle: '腾讯游戏平台 · 海量精品游戏',
  brandColor: const Color(0xFFFF6A00),
  brandColorLight: const Color(0xFFFFB74D),
  icon: Icons.games_rounded,
  categories: const [
    GameCategory('MOBA', Icons.sports_esports_rounded),
    GameCategory('FPS', Icons.gps_fixed_rounded),
    GameCategory('RPG', Icons.person_rounded),
    GameCategory('策略', Icons.business_center_rounded),
    GameCategory('竞速', Icons.directions_car_rounded),
    GameCategory('格斗', Icons.sports_mma_rounded),
  ],
  allGames: const [
    GameData(
      id: 'wg_lol',
      name: '英雄联盟',
      developer: 'Riot Games',
      genre: 'MOBA',
      isFree: true,
      rating: 4.6,
      description: '全球最受欢迎的多人在线竞技游戏，5v5 团队对战，140+ 英雄可选。'
          '每局游戏约 30-45 分钟，考验团队配合与个人操作。赛季排位系统、'
          '英雄联盟职业联赛 (LPL) 与全球总决赛让竞技体验更加丰富。',
      tags: ['MOBA', '竞技', '5v5', '团队'],
      coverGradient: [Color(0xFF1A237E), Color(0xFF0D47A1)],
      coverIcon: Icons.shield_rounded,
      isFeatured: true,
    ),
    GameData(
      id: 'wg_val',
      name: '无畏契约',
      developer: 'Riot Games',
      genre: 'FPS',
      isFree: true,
      rating: 4.5,
      description: '5v5 战术竞技射击游戏。融合精准射击与独特的角色技能系统，'
          '每局 13 回合攻防对战，高度考验枪法、策略与团队配合。'
          '丰富的特工角色设计和精准的射击手感，带来全新的战术体验。',
      tags: ['FPS', '战术射击', '竞技', '免费'],
      coverGradient: [Color(0xFFB71C1C), Color(0xFFE53935)],
      coverIcon: Icons.gps_fixed_rounded,
      isFeatured: true,
    ),
    GameData(
      id: 'wg_cf',
      name: '穿越火线',
      developer: 'SmileGate',
      genre: 'FPS',
      isFree: true,
      rating: 4.2,
      description: '经典 FPS 射击网游，拥有多种游戏模式：爆破、团队竞技、生化模式、'
          '挑战模式等。操作简单易上手，丰富的武器和角色皮肤收集系统，'
          '长期运营的稳定更新让游戏始终保持活力。',
      tags: ['FPS', '射击', '竞技', '免费'],
      coverGradient: [Color(0xFF33691E), Color(0xFF558B2F)],
      coverIcon: Icons.local_fire_department_rounded,
    ),
    GameData(
      id: 'wg_dnf',
      name: '地下城与勇士',
      developer: 'Neople',
      genre: 'RPG',
      isFree: true,
      rating: 4.3,
      description: '2D 横版格斗网游 RPG，独特的格斗操作手感搭配丰富的角色养成系统。'
          '深渊派对、团队副本、超多装备和职业分化，是国内最受欢迎的'
          '动作网游之一。暗黑地下城风格的画面与爽快的连击操作。',
      tags: ['RPG', '动作', '格斗', '免费'],
      coverGradient: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
      coverIcon: Icons.flash_on_rounded,
      isFeatured: true,
    ),
    GameData(
      id: 'wg_pubg',
      name: 'PUBG: BATTLEGROUNDS',
      developer: 'Krafton',
      genre: 'FPS',
      isFree: true,
      rating: 4.1,
      description: '100 人空降战场，搜刮装备，在不断缩小的安全区中战斗，成为最后的幸存者。'
          '支持单排、双排、四人小队，多张大地图可选。战术竞技大逃杀的开创者，'
          '真实弹道物理系统和紧张刺激的生存对抗体验。',
      tags: ['大逃杀', 'FPS', '生存', '免费'],
      coverGradient: [Color(0xFFE65100), Color(0xFFF57C00)],
      coverIcon: Icons.military_tech_rounded,
    ),
    GameData(
      id: 'wg_mhw',
      name: '怪物猎人：世界',
      developer: 'Capcom',
      genre: 'RPG',
      price: '¥198',
      rating: 4.7,
      description: '全球销量超 2100 万份的动作 RPG。在广阔的开放世界中追踪并狩猎巨型怪物，'
          '制作装备、强化武器，与其他猎人组队挑战更强的怪物。14 种武器各具特色，'
          '每种都有独特的操作逻辑和战斗风格，提供数百小时的游戏内容。',
      tags: ['动作RPG', '开放世界', '合作', '狩猎'],
      coverGradient: [Color(0xFF1B5E20), Color(0xFF388E3C)],
      coverIcon: Icons.pets_rounded,
      isFeatured: true,
    ),
    GameData(
      id: 'wg_lark',
      name: '命运方舟',
      developer: 'SmileGate RPG',
      genre: 'RPG',
      isFree: true,
      rating: 4.0,
      description: 'MMORPG 大作，俯视角动作战斗，丰富的职业系统和副本挑战。'
          '广阔的开放世界探索，海量的剧情任务和收集要素。高品质的画面表现'
          '和流畅的战斗动作，打造沉浸式的 MMORPG 体验。',
      tags: ['MMORPG', '动作', '开放世界', '免费'],
      coverGradient: [Color(0xFF0D47A1), Color(0xFF1565C0)],
      coverIcon: Icons.anchor_rounded,
    ),
    GameData(
      id: 'wg_genshin',
      name: '原神',
      developer: '米哈游',
      genre: 'RPG',
      isFree: true,
      rating: 4.4,
      description: '开放世界冒险 RPG，四元素交互战斗系统。在提瓦特大陆探索七国，'
          '收集角色，挑战深渊，体验持续更新的精彩剧情。精美的二次元画风、'
          '高自由度的探索玩法和丰富的角色养成系统。',
      tags: ['开放世界', 'RPG', '冒险', '免费'],
      coverGradient: [Color(0xFF00695C), Color(0xFF00897B)],
      coverIcon: Icons.auto_awesome_rounded,
    ),
    GameData(
      id: 'wg_fifa',
      name: 'EA SPORTS FC',
      developer: 'EA Sports',
      genre: '竞速',
      price: '¥248',
      rating: 4.0,
      description: '全球最受欢迎的足球模拟游戏。真实球员数据和授权联赛，多种模式包括'
          '终极团队 (UT)、生涯模式和 Volta 街球。HyperMotion 技术带来更加真实的'
          '球员动作，让每场比赛都充满真实感。',
      tags: ['体育', '足球', '竞技', '模拟'],
      coverGradient: [Color(0xFF1A237E), Color(0xFF283593)],
      coverIcon: Icons.sports_soccer_rounded,
    ),
    GameData(
      id: 'wg_nw',
      name: '永劫无间',
      developer: '24 Entertainment',
      genre: '格斗',
      isFree: true,
      rating: 4.1,
      description: '60 人古风武侠大逃杀。近战格斗为核心，融合远程武器和勾锁机动系统，'
          '独特的铁与火系统提供多样化的战斗策略。东方美学画风与流畅的动作系统'
          '结合，打造独特的武侠大逃杀体验。',
      tags: ['大逃杀', '动作', '格斗', '免费'],
      coverGradient: [Color(0xFF263238), Color(0xFF455A64)],
      coverIcon: Icons.sports_martial_arts_rounded,
    ),
    GameData(
      id: 'wg_civ6',
      name: '文明VI',
      developer: 'Firaxis Games',
      genre: '策略',
      price: '¥199',
      rating: 4.5,
      description: '经典回合制策略游戏。从古代文明发展到太空时代，通过外交、科技、'
          '文化或军事手段征服世界。城区系统、间谍系统和丰富的 AI 领袖为每局'
          '游戏带来不同的体验。支持多人在线对战。',
      tags: ['策略', '回合制', '4X', '历史'],
      coverGradient: [Color(0xFF4E342E), Color(0xFF6D4C41)],
      coverIcon: Icons.public_rounded,
    ),
    GameData(
      id: 'wg_zzz',
      name: '绝区零',
      developer: '米哈游',
      genre: 'RPG',
      isFree: true,
      rating: 4.3,
      description: '都市幻想动作 RPG，快节奏的动作战斗系统。在新艾利都城中探索神秘的'
          '「空洞」，招募代理人组成团队，体验爽快的连招打击感和深度的角色养成。'
          '独特的潮流美术风格和沉浸式的都市剧情。',
      tags: ['动作RPG', '都市', '冒险', '免费'],
      coverGradient: [Color(0xFF311B92), Color(0xFF512DA8)],
      coverIcon: Icons.bolt_rounded,
    ),
  ],
);

// ============================================================================
// Ubisoft 游戏数据
// ============================================================================

final PlatformConfig _ubisoftConfig = PlatformConfig(
  name: 'Ubisoft Connect',
  subtitle: '育碧游戏平台 · 3A 大作云集',
  brandColor: const Color(0xFF0070FF),
  brandColorLight: const Color(0xFF64B5F6),
  icon: Icons.sports_esports_rounded,
  categories: const [
    GameCategory('动作冒险', Icons.directions_run_rounded),
    GameCategory('射击', Icons.gps_fixed_rounded),
    GameCategory('开放世界', Icons.landscape_rounded),
    GameCategory('潜行', Icons.visibility_off_rounded),
    GameCategory('竞速', Icons.directions_car_rounded),
    GameCategory('多人', Icons.group_rounded),
  ],
  allGames: const [
    GameData(
      id: 'ubi_acm',
      name: '刺客信条：幻景',
      developer: 'Ubisoft Bordeaux',
      genre: '动作冒险',
      price: '¥298',
      rating: 4.2,
      description: '回归经典潜行刺杀玩法。扮演巴格达街头少年巴辛姆，在阿拔斯帝国'
          '的黄金时代中揭开名为「隐匿者」组织的秘密。紧凑的线性关卡设计'
          '和精炼的潜行系统，致敬初代刺客信条的核心体验。',
      tags: ['刺客信条', '潜行', '动作', '历史'],
      coverGradient: [Color(0xFFBF360C), Color(0xFFE64A19)],
      coverIcon: Icons.security_rounded,
      isFeatured: true,
    ),
    GameData(
      id: 'ubi_acv',
      name: '刺客信条：英灵殿',
      developer: 'Ubisoft Montreal',
      genre: '开放世界',
      price: '¥298',
      rating: 4.3,
      description: '扮演维京战士带领部族从挪威横跨至英格兰。广阔的开放世界探索，'
          'RPG 养成系统，大规模攻城战和区域征服玩法。丰富的支线任务和'
          '神话元素融入，打造史诗级的维京冒险之旅。',
      tags: ['刺客信条', 'RPG', '开放世界', '维京'],
      coverGradient: [Color(0xFF1A237E), Color(0xFF303F9F)],
      coverIcon: Icons.shield_rounded,
      isFeatured: true,
    ),
    GameData(
      id: 'ubi_r6s',
      name: '彩虹六号：围攻',
      developer: 'Ubisoft Montreal',
      genre: '射击',
      price: '¥88',
      rating: 4.5,
      description: '5v5 战术射击对抗游戏，攻防对抗玩法。60+ 特勤干员各具独特装备技能，'
          '环境可破坏系统让每局游戏变化莫测。持续更新的电竞级射击游戏，'
          '拥有全球顶级的电竞联赛体系和庞大的竞技社区。',
      tags: ['FPS', '战术', '5v5', '电竞'],
      coverGradient: [Color(0xFF37474F), Color(0xFF546E7A)],
      coverIcon: Icons.security_rounded,
      isFeatured: true,
    ),
    GameData(
      id: 'ubi_fc6',
      name: '孤岛惊魂 6',
      developer: 'Ubisoft Toronto',
      genre: '射击',
      price: '¥248',
      rating: 4.1,
      description: '开放世界第一人称射击游戏。在热带的亚拉岛上发起游击革命，'
          '对抗独裁者安东·卡斯蒂罗。丰富的武器改装系统、可招募的动物同伴'
          '和多样化的载具战斗，带来自由度极高的开放世界冒险。',
      tags: ['FPS', '开放世界', '动作', '游击战'],
      coverGradient: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
      coverIcon: Icons.local_fire_department_rounded,
    ),
    GameData(
      id: 'ubi_wd',
      name: '看门狗：军团',
      developer: 'Ubisoft Toronto',
      genre: '开放世界',
      price: '¥198',
      rating: 3.9,
      description: '在近未来的伦敦，招募城市中的任何居民加入你的反抗军。每个角色'
          '都有独特的技能和背景。黑客入侵一切电子设备，利用城市基础设施'
          '对抗极权组织 Albion 的统治。',
      tags: ['开放世界', '黑客', '动作', 'RPG'],
      coverGradient: [Color(0xFF006064), Color(0xFF00838F)],
      coverIcon: Icons.remove_red_eye_rounded,
    ),
    GameData(
      id: 'ubi_td2',
      name: '全境封锁 2',
      developer: 'Massive Entertainment',
      genre: '射击',
      price: '¥98',
      rating: 4.2,
      description: '在线开放世界第三人称射击 RPG。在危机后的华盛顿特区重建秩序，'
          '丰富的 PvE 和 PvP 内容，装备驱动的刷装备体验。暗区 (Dark Zone) '
          'PvPvE 玩法和团队副本突袭带来持久的挑战。',
      tags: ['TPS', 'RPG', '合作', '刷装备'],
      coverGradient: [Color(0xFFE65100), Color(0xFFF57C00)],
      coverIcon: Icons.radar_rounded,
      isFeatured: true,
    ),
    GameData(
      id: 'ubi_grb',
      name: '幽灵行动：断点',
      developer: 'Ubisoft Paris',
      genre: '潜行',
      price: '¥198',
      rating: 3.8,
      description: '开放世界军事射击游戏。在神秘的极光岛上独行或组队执行任务，'
          '潜行渗透或火力压制，多样化的战术选择。沉浸模式提供更加真实的'
          '军事模拟体验，移除 HUD 元素和标记系统。',
      tags: ['TPS', '潜行', '军事', '合作'],
      coverGradient: [Color(0xFF263238), Color(0xFF37474F)],
      coverIcon: Icons.visibility_off_rounded,
    ),
    GameData(
      id: 'ubi_crew2',
      name: '飙酷车神 2',
      developer: 'Ivory Tower',
      genre: '竞速',
      price: '¥148',
      rating: 4.0,
      description: '开放世界竞速游戏，覆盖美国全境。超跑、越野、飞行、快艇四大赛事类型，'
          '无缝切换载具，自由探索美国地标。在线嘉年华活动和赛季更新'
          '持续带来新赛道、新载具和新挑战。',
      tags: ['竞速', '开放世界', '载具', '多人'],
      coverGradient: [Color(0xFFAD1457), Color(0xFFD81B60)],
      coverIcon: Icons.directions_car_rounded,
    ),
    GameData(
      id: 'ubi_xd2',
      name: 'XDefiant',
      developer: 'Ubisoft San Francisco',
      genre: '多人',
      isFree: true,
      rating: 3.7,
      description: '免费竞技 FPS 游戏。融合多个育碧宇宙的角色派系——'
          '幽灵行动、全境封锁、看门狗和孤岛惊魂。快节奏的 6v6 对战，'
          '经典模式与特殊技能相结合，带来爽快的射击体验。',
      tags: ['FPS', '竞技', '免费', '多人'],
      coverGradient: [Color(0xFF4A148C), Color(0xFF6A1B9A)],
      coverIcon: Icons.flash_on_rounded,
    ),
    GameData(
      id: 'ubi_sw',
      name: '星球大战：亡命之徒',
      developer: 'Massive Entertainment',
      genre: '动作冒险',
      price: '¥398',
      rating: 4.0,
      description: '首款星球大战开放世界游戏。扮演走私贩凯·维斯在银河系冒险，'
          '驾驶飞船穿越星际，接受悬赏任务，探索传奇星球。Massive 引擎'
          '打造的壮丽星球景观和沉浸式的太空探索体验。',
      tags: ['开放世界', '星球大战', '动作', '冒险'],
      coverGradient: [Color(0xFF1A237E), Color(0xFF0D47A1)],
      coverIcon: Icons.star_rounded,
      isFeatured: true,
    ),
    GameData(
      id: 'ubi_acs',
      name: '刺客信条：影',
      developer: 'Ubisoft Quebec',
      genre: '动作冒险',
      price: '¥448',
      rating: 4.4,
      description: '刺客信条系列最新作，背景设定在封建日本。双主角系统：'
          '非裔武士弥助和忍者奈绪江。开放世界探索、潜行暗杀和正面战斗'
          '三位一体的核心玩法。',
      tags: ['刺客信条', '日本', '动作', '开放世界'],
      coverGradient: [Color(0xFF880E4F), Color(0xFFC62828)],
      coverIcon: Icons.spa_rounded,
    ),
  ],
);

// ============================================================================
// Xbox 游戏数据
// ============================================================================

final PlatformConfig _xboxConfig = PlatformConfig(
  name: 'Xbox',
  subtitle: 'Xbox Game Studios · Game Pass 订阅畅玩',
  brandColor: const Color(0xFF107C10),
  brandColorLight: const Color(0xFF66BB6A),
  icon: Icons.gamepad_rounded,
  categories: const [
    GameCategory('Game Pass', Icons.all_inclusive_rounded),
    GameCategory('动作', Icons.directions_run_rounded),
    GameCategory('射击', Icons.gps_fixed_rounded),
    GameCategory('RPG', Icons.person_rounded),
    GameCategory('竞速', Icons.directions_car_rounded),
    GameCategory('独立', Icons.auto_awesome_rounded),
  ],
  allGames: const [
    GameData(
      id: 'xb_halo',
      name: 'Halo Infinite',
      developer: '343 Industries',
      genre: '射击',
      isFree: true, // 多人模式免费
      rating: 4.3,
      description: 'Halo 系列最新作，多人模式免费游玩。在广阔的 Zeta Halo 上展开战役，'
          '经典 Halo 竞技对战与全新钩锁机制的完美结合。赛季更新带来'
          '新地图、新模式和 Forge 创意工坊。',
      tags: ['FPS', '科幻', 'Game Pass', '免费多人'],
      coverGradient: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
      coverIcon: Icons.military_tech_rounded,
      isFeatured: true,
    ),
    GameData(
      id: 'xb_forza5',
      name: 'Forza Horizon 5',
      developer: 'Playground Games',
      genre: '竞速',
      price: '¥248',
      rating: 4.8,
      description: '在墨西哥的绚丽开放世界中体验终极公路旅行。数百款真实授权跑车、'
          '动态四季变化、在线嘉年华赛事和 EventLab 创意工具，'
          '公认的赛车游戏巅峰之作。',
      tags: ['竞速', '开放世界', 'Game Pass', '在线'],
      coverGradient: [Color(0xFFE65100), Color(0xFFF57C00)],
      coverIcon: Icons.directions_car_rounded,
      isFeatured: true,
    ),
    GameData(
      id: 'xb_starfield',
      name: 'Starfield',
      developer: 'Bethesda Game Studios',
      genre: 'RPG',
      price: '¥298',
      rating: 4.0,
      description: 'Bethesda 25 年来的全新 IP，太空 RPG 史诗巨作。探索超过 1000 颗星球，'
          '建造飞船、招募船员、加入各方势力，在浩瀚宇宙中书写你的银河传奇。'
          '模组工具 Creation Kit 释放无限创造潜力。',
      tags: ['RPG', '开放世界', '太空', 'Game Pass'],
      coverGradient: [Color(0xFF0D47A1), Color(0xFF1565C0)],
      coverIcon: Icons.rocket_launch_rounded,
      isFeatured: true,
    ),
    GameData(
      id: 'xb_gears5',
      name: 'Gears 5',
      developer: 'The Coalition',
      genre: '射击',
      price: '¥198',
      rating: 4.4,
      description: 'Gears of War 系列最新续作。凯特·迪亚兹探寻身世秘密的同时，'
          '对抗铺天盖地的兽族。爽快的掩体射击和标志性的电锯枪。'
          '战役、多人对战和 Horde 模式提供多样化的游戏内容。',
      tags: ['TPS', '动作', 'Game Pass', '合作'],
      coverGradient: [Color(0xFFB71C1C), Color(0xFFD32F2F)],
      coverIcon: Icons.construction_rounded,
    ),
    GameData(
      id: 'xb_sea',
      name: 'Sea of Thieves',
      developer: 'Rare',
      genre: '动作',
      price: '¥148',
      rating: 4.3,
      description: '开放世界海盗冒险游戏。与朋友组建海盗船队，挖掘宝藏、激战骷髅、'
          '击沉敌船，体验自由自在的海上冒险生活。持续更新的赛季内容'
          '带来全新的海域、任务和海盗传奇故事。',
      tags: ['冒险', '多人', 'Game Pass', '开放世界'],
      coverGradient: [Color(0xFF006064), Color(0xFF00838F)],
      coverIcon: Icons.sailing_rounded,
      isFeatured: true,
    ),
    GameData(
      id: 'xb_hifi',
      name: 'Hi-Fi Rush',
      developer: 'Tango Gameworks',
      genre: '独立',
      price: '¥198',
      rating: 4.6,
      description: '节奏动作游戏。一切战斗都与背景音乐节拍同步，独特的卡通渲染风格'
          '和爽快的连击系统。原创的音乐融合动作玩法，让每次攻击都踩在节拍上，'
          '带来前所未有的视听一体化战斗体验。',
      tags: ['动作', '节奏', 'Game Pass', '独立'],
      coverGradient: [Color(0xFFAD1457), Color(0xFFD81B60)],
      coverIcon: Icons.music_note_rounded,
    ),
    GameData(
      id: 'xb_fable',
      name: 'Fable',
      developer: 'Playground Games',
      genre: 'RPG',
      price: '¥398',
      rating: 4.5,
      description: '经典英式奇幻 RPG 系列重启之作。在充满魔法与幽默的阿尔比恩大陆冒险，'
          '选择塑造角色命运的道德抉择。Playground Games 以 Forza 引擎打造'
          '的精美奇幻世界和深度角色扮演体验。',
      tags: ['RPG', '奇幻', 'Game Pass', '开放世界'],
      coverGradient: [Color(0xFF4E342E), Color(0xFF6D4C41)],
      coverIcon: Icons.auto_awesome_rounded,
    ),
    GameData(
      id: 'xb_msfs',
      name: 'Microsoft Flight Simulator',
      developer: 'Asobo Studio',
      genre: 'Game Pass',
      price: '¥298',
      rating: 4.7,
      description: '最真实的飞行模拟器。基于必应地图的全球 3D 实景建模，'
          '数百款真实授权飞机，实时天气和空中交通系统。'
          '翱翔在整个地球上空，探索壮丽的自然景观和城市地标。',
      tags: ['模拟', '飞行', 'Game Pass', '真实'],
      coverGradient: [Color(0xFF1565C0), Color(0xFF42A5F5)],
      coverIcon: Icons.flight_rounded,
    ),
    GameData(
      id: 'xb_pal',
      name: 'Palworld',
      developer: 'Pocketpair',
      genre: '独立',
      price: '¥98',
      rating: 4.2,
      description: '开放世界生存制作游戏。捕获、培育「帕鲁」伙伴，建造基地、'
          '探索地下城、PvP 对战。独特的宝可梦 + 方舟生存融合玩法，'
          '支持多人在线合作，持续更新的大型 DLC 内容。',
      tags: ['生存', '开放世界', 'Game Pass', '合作'],
      coverGradient: [Color(0xFF00695C), Color(0xFF00897B)],
      coverIcon: Icons.pets_rounded,
    ),
    GameData(
      id: 'xb_avowed',
      name: 'Avowed',
      developer: 'Obsidian Entertainment',
      genre: 'RPG',
      price: '¥298',
      rating: 4.3,
      description: '第一人称奇幻 RPG。在永恒之柱宇宙的活石岛上展开冒险，'
          '双持武器和魔法的自由战斗系统、深度的同伴交互和分支剧情，'
          'Obsidian 招牌级的叙事 RPG 体验。',
      tags: ['RPG', '第一人称', 'Game Pass', '奇幻'],
      coverGradient: [Color(0xFF4A148C), Color(0xFF6A1B9A)],
      coverIcon: Icons.auto_fix_high_rounded,
    ),
    GameData(
      id: 'xb_hellblade2',
      name: "Senua's Saga: Hellblade II",
      developer: 'Ninja Theory',
      genre: '动作',
      price: '¥248',
      rating: 4.4,
      description: '以冰岛为背景的心理恐怖动作游戏。Unreal Engine 5 打造的'
          '次世代画面品质，沉浸式的双耳音频体验。赛娜面对内心恶魔'
          '的同时在维京荒野中战斗生存。',
      tags: ['动作', '冒险', 'Game Pass', '叙事'],
      coverGradient: [Color(0xFF263238), Color(0xFF455A64)],
      coverIcon: Icons.psychology_rounded,
    ),
  ],
);

// ============================================================================
// 收藏游戏（本地存储持久化）
// ============================================================================

class SavedGame {
  final String gameId;
  final String name;
  final DateTime addedAt;

  SavedGame({
    required this.gameId,
    required this.name,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'name': name,
        'addedAt': addedAt.toIso8601String(),
      };

  factory SavedGame.fromJson(Map<String, dynamic> json) => SavedGame(
        gameId: json['gameId'] ?? '',
        name: json['name'] ?? '',
        addedAt: DateTime.tryParse(json['addedAt'] ?? '') ?? DateTime.now(),
      );
}

// ============================================================================
// PlatformGameTab — 原生游戏展示标签页（无 WebView）
// ============================================================================

class PlatformGameTab extends StatefulWidget {
  final GamePlatform platform;

  const PlatformGameTab({super.key, required this.platform});

  @override
  State<PlatformGameTab> createState() => _PlatformGameTabState();
}

class _PlatformGameTabState extends State<PlatformGameTab>
    with AutomaticKeepAliveClientMixin {
  late final PlatformConfig _config;
  Set<String> _savedGameIds = {};
  bool _loading = true;
  String? _selectedCategory;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _config = PlatformConfig.forPlatform(widget.platform);
    _loadSavedGames();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedGames() async {
    final prefs = await SharedPreferences.getInstance();
    final gamesJson = prefs.getString('${widget.platform.name}_saved_games');
    if (gamesJson != null) {
      try {
        final list = jsonDecode(gamesJson) as List;
        _savedGameIds = list
            .map((e) => SavedGame.fromJson(e as Map<String, dynamic>))
            .map((g) => g.gameId)
            .toSet();
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleSave(GameData game) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${widget.platform.name}_saved_games';
    final gamesJson = prefs.getString(key);
    List<SavedGame> games = [];
    if (gamesJson != null) {
      try {
        final list = jsonDecode(gamesJson) as List;
        games = list
            .map((e) => SavedGame.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    final wasSaved = _savedGameIds.contains(game.id);
    if (wasSaved) {
      games.removeWhere((g) => g.gameId == game.id);
      _savedGameIds.remove(game.id);
    } else {
      games.insert(0, SavedGame(gameId: game.id, name: game.name));
      _savedGameIds.add(game.id);
    }

    await prefs.setString(
        key, jsonEncode(games.map((g) => g.toJson()).toList()));

    if (!mounted) return;
    setState(() {});

    // 反馈
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(wasSaved ? '已取消收藏 ${game.name}' : '已收藏 ${game.name}'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// 根据搜索和分类筛选游戏列表
  List<GameData> get _filteredGames {
    var games = _selectedCategory != null
        ? _config.gamesInCategory(_selectedCategory!)
        : _config.allGames;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      games = games
          .where((g) =>
              g.name.toLowerCase().contains(q) ||
              g.developer.toLowerCase().contains(q) ||
              g.genre.toLowerCase().contains(q) ||
              g.tags.any((t) => t.toLowerCase().contains(q)))
          .toList();
    }
    return games;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final displayGames = _filteredGames;

    return RefreshIndicator(
      onRefresh: _loadSavedGames,
      child: CustomScrollView(
        slivers: [
          // 顶部内容（Hero + 精选 + 免费 + 搜索 + 分类）
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBrandHero(cs, tt),
                  const SizedBox(height: 20),

                  // 精选推荐（仅在未筛选分类时展示）
                  if (_selectedCategory == null && _searchQuery.isEmpty) ...[
                    _buildSectionTitle(
                        '精选推荐', Icons.star_rounded, cs, tt),
                    const SizedBox(height: 10),
                    _buildFeaturedCarousel(cs, tt),
                    const SizedBox(height: 24),

                    // 免费游戏
                    if (_config.freeGames.isNotEmpty) ...[
                      _buildSectionTitle(
                          '免费游戏', Icons.card_giftcard_rounded, cs, tt),
                      const SizedBox(height: 10),
                      _buildFreeGamesRow(cs, tt),
                      const SizedBox(height: 24),
                    ],

                    // 收藏游戏
                    if (_savedGameIds.isNotEmpty) ...[
                      _buildSectionTitle(
                          '我的收藏', Icons.favorite_rounded, cs, tt,
                          trailing: Text(
                            '${_savedGameIds.length} 款',
                            style: tt.labelMedium?.copyWith(
                                color: cs.onSurfaceVariant),
                          )),
                      const SizedBox(height: 10),
                      _buildSavedGamesRow(cs, tt),
                      const SizedBox(height: 24),
                    ],
                  ],

                  // 搜索框
                  _buildSearchBar(cs, tt),
                  const SizedBox(height: 12),

                  // 分类筛选条
                  _buildCategoryChips(cs, tt),
                  const SizedBox(height: 12),

                  // 游戏列表标题
                  _buildSectionTitle(
                    _selectedCategory ?? '全部游戏',
                    Icons.grid_view_rounded,
                    cs,
                    tt,
                    trailing: Text(
                      '${displayGames.length} 款',
                      style: tt.labelMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // 游戏列表（SliverList 提供高效滚动）
          displayGames.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 48,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty
                                ? '未找到匹配「$_searchQuery」的游戏'
                                : '该分类暂无游戏',
                            style: tt.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList.builder(
                    itemCount: displayGames.length,
                    itemBuilder: (context, index) => _buildGameListItem(
                        displayGames[index], cs, tt, index),
                  ),
                ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 品牌 Hero Banner
  // --------------------------------------------------------------------------
  Widget _buildBrandHero(ColorScheme cs, TextTheme tt) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _config.brandColor,
            _config.brandColor.withValues(alpha: 0.75),
            _config.brandColorLight.withValues(alpha: 0.4),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _config.brandColor.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(
              _config.icon,
              size: 150,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Icon(_config.icon, color: Colors.white, size: 28),
                    const SizedBox(width: 10),
                    Text(
                      _config.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _config.subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_config.allGames.length} 款游戏 · '
                  '${_config.freeGames.length} 款免费 · '
                  '${_savedGameIds.length} 款已收藏',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.04, end: 0);
  }

  // --------------------------------------------------------------------------
  // 搜索框
  // --------------------------------------------------------------------------
  Widget _buildSearchBar(ColorScheme cs, TextTheme tt) {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _searchQuery = v.trim()),
      decoration: InputDecoration(
        hintText: '搜索 ${_config.name} 游戏...',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
      ),
      style: tt.bodyMedium,
    );
  }

  // --------------------------------------------------------------------------
  // 精选推荐轮播
  // --------------------------------------------------------------------------
  Widget _buildFeaturedCarousel(ColorScheme cs, TextTheme tt) {
    final featured = _config.featuredGames;
    if (featured.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: featured.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final game = featured[index];
          return SizedBox(
            width: 300,
            child: _FeaturedGameCard(
              game: game,
              isSaved: _savedGameIds.contains(game.id),
              brandColor: _config.brandColor,
              onTap: () => _showGameDetail(game),
              onToggleSave: () => _toggleSave(game),
            ),
          ).animate().fadeIn(delay: (index * 80).ms, duration: 300.ms);
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 免费游戏横向滚动
  // --------------------------------------------------------------------------
  Widget _buildFreeGamesRow(ColorScheme cs, TextTheme tt) {
    final freeGames = _config.freeGames;
    return SizedBox(
      height: 145,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: freeGames.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final game = freeGames[index];
          return SizedBox(
            width: 115,
            child: _CompactGameCard(
              game: game,
              isSaved: _savedGameIds.contains(game.id),
              onTap: () => _showGameDetail(game),
            ),
          ).animate().fadeIn(delay: (index * 60).ms, duration: 250.ms);
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 收藏游戏横向滚动
  // --------------------------------------------------------------------------
  Widget _buildSavedGamesRow(ColorScheme cs, TextTheme tt) {
    final savedGames =
        _config.allGames.where((g) => _savedGameIds.contains(g.id)).toList();
    if (savedGames.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 145,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: savedGames.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final game = savedGames[index];
          return SizedBox(
            width: 115,
            child: _CompactGameCard(
              game: game,
              isSaved: true,
              showFavBadge: true,
              onTap: () => _showGameDetail(game),
            ),
          ).animate().fadeIn(delay: (index * 60).ms, duration: 250.ms);
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 分类筛选条
  // --------------------------------------------------------------------------
  Widget _buildCategoryChips(ColorScheme cs, TextTheme tt) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildChip('全部', null, cs),
          ..._config.categories
              .map((cat) => _buildChip(cat.name, cat, cs)),
        ],
      ),
    );
  }

  Widget _buildChip(String label, GameCategory? cat, ColorScheme cs) {
    final isSelected =
        cat == null ? _selectedCategory == null : _selectedCategory == cat.name;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        avatar: cat != null ? Icon(cat.icon, size: 16) : null,
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(
          () => _selectedCategory =
              (cat == null || _selectedCategory == cat.name) ? null : cat.name,
        ),
        selectedColor: _config.brandColor.withValues(alpha: 0.2),
        checkmarkColor: _config.brandColor,
        labelStyle: TextStyle(
          fontSize: 13,
          color: isSelected ? _config.brandColor : cs.onSurfaceVariant,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 游戏列表项（Material Card）
  // --------------------------------------------------------------------------
  Widget _buildGameListItem(
      GameData game, ColorScheme cs, TextTheme tt, int index) {
    final isSaved = _savedGameIds.contains(game.id);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showGameDetail(game),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 封面
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: game.coverGradient,
                  ),
                ),
                child: Icon(game.coverIcon, color: Colors.white70, size: 30),
              ),
              const SizedBox(width: 14),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.name,
                      style: tt.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      game.developer,
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.star_rounded,
                            size: 14, color: Colors.amber.shade700),
                        const SizedBox(width: 3),
                        Text(
                          game.rating.toStringAsFixed(1),
                          style: tt.labelSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        _tagBadge(game.genre, cs, tt),
                        if (game.tags.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          _tagBadge(game.tags.first, cs, tt),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // 价格 + 收藏
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: game.isFree
                          ? Colors.green.withValues(alpha: 0.15)
                          : _config.brandColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      game.isFree ? '免费' : (game.price ?? ''),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: game.isFree
                            ? Colors.green.shade700
                            : _config.brandColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _toggleSave(game),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        isSaved
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 22,
                        color: isSaved
                            ? Colors.redAccent
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: (index * 50).ms, duration: 250.ms);
  }

  Widget _tagBadge(String text, ColorScheme cs, TextTheme tt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: tt.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontSize: 10,
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Section Title
  // --------------------------------------------------------------------------
  Widget _buildSectionTitle(
    String title,
    IconData icon,
    ColorScheme cs,
    TextTheme tt, {
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _config.brandColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (trailing != null) ...[
          const Spacer(),
          trailing,
        ],
      ],
    );
  }

  // --------------------------------------------------------------------------
  // 游戏详情底部面板
  // --------------------------------------------------------------------------
  void _showGameDetail(GameData game) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // 拖拽手柄
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  children: [
                    // 封面 Banner
                    _buildDetailBanner(game, cs),
                    const SizedBox(height: 20),

                    // 标题 + 价格按钮
                    _buildDetailHeader(game, cs, tt),
                    const SizedBox(height: 16),

                    // 评分 + 分类 + 收藏
                    _buildDetailMeta(game, cs, tt),
                    const SizedBox(height: 20),

                    // 标签
                    _buildDetailTags(game, tt),
                    const SizedBox(height: 20),

                    // 描述
                    Text(
                      '游戏简介',
                      style: tt.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      game.description,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 信息卡片
                    _buildDetailInfoCard(game, cs, tt),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailBanner(GameData game, ColorScheme cs) {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: game.coverGradient,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            bottom: -10,
            child: Icon(game.coverIcon,
                size: 140, color: Colors.white.withValues(alpha: 0.08)),
          ),
          Center(
            child: Icon(game.coverIcon, size: 64, color: Colors.white70),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_config.icon, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    _config.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (game.isFree)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '免费',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailHeader(GameData game, ColorScheme cs, TextTheme tt) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                game.name,
                style: tt.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                game.developer,
                style: tt.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        FilledButton(
          onPressed: () {},
          style: FilledButton.styleFrom(
            backgroundColor:
                game.isFree ? Colors.green : _config.brandColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child:
              Text(game.isFree ? '免费游玩' : (game.price ?? '获取')),
        ),
      ],
    );
  }

  Widget _buildDetailMeta(GameData game, ColorScheme cs, TextTheme tt) {
    return Row(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.star_rounded,
                  size: 18, color: Colors.amber),
              const SizedBox(width: 4),
              Text(
                game.rating.toStringAsFixed(1),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _config.brandColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            game.genre,
            style: TextStyle(
              color: _config.brandColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        const Spacer(),
        StatefulBuilder(
          builder: (ctx, setLocal) {
            final saved = _savedGameIds.contains(game.id);
            return IconButton(
              icon: Icon(
                saved
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: saved ? Colors.redAccent : cs.onSurfaceVariant,
              ),
              onPressed: () {
                _toggleSave(game);
                setLocal(() {});
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildDetailTags(GameData game, TextTheme tt) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: game.tags
          .map((tag) => Chip(
                label: Text(tag),
                labelStyle: tt.labelSmall,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildDetailInfoCard(
      GameData game, ColorScheme cs, TextTheme tt) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _detailInfoRow('开发商', game.developer, tt, cs),
            const Divider(height: 20),
            _detailInfoRow('类型', game.genre, tt, cs),
            const Divider(height: 20),
            _detailInfoRow(
              '价格',
              game.isFree ? '免费' : (game.price ?? '未知'),
              tt,
              cs,
            ),
            const Divider(height: 20),
            _detailInfoRow('平台', _config.name, tt, cs),
            const Divider(height: 20),
            _detailInfoRow(
                '评分', '${game.rating}/5.0', tt, cs),
          ],
        ),
      ),
    );
  }

  Widget _detailInfoRow(
    String label,
    String value,
    TextTheme tt,
    ColorScheme cs,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: tt.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant)),
        Text(value,
            style:
                tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// =============================================================================
// 精选游戏大卡片（横向轮播用）
// =============================================================================

class _FeaturedGameCard extends StatelessWidget {
  final GameData game;
  final bool isSaved;
  final Color brandColor;
  final VoidCallback onTap;
  final VoidCallback onToggleSave;

  const _FeaturedGameCard({
    required this.game,
    required this.isSaved,
    required this.brandColor,
    required this.onTap,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 封面
            Container(
              height: 110,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: game.coverGradient,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -10,
                    bottom: -10,
                    child: Icon(game.coverIcon,
                        size: 100,
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  Center(
                    child: Icon(game.coverIcon,
                        size: 40, color: Colors.white60),
                  ),
                  if (game.isFree)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '免费',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 12, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            game.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!game.isFree && game.price != null)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: brandColor.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          game.price!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 信息
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          game.name,
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          game.developer,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: onToggleSave,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        isSaved
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 20,
                        color: isSaved
                            ? Colors.redAccent
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 紧凑游戏卡片（免费游戏行 & 收藏行）
// =============================================================================

class _CompactGameCard extends StatelessWidget {
  final GameData game;
  final bool isSaved;
  final bool showFavBadge;
  final VoidCallback onTap;

  const _CompactGameCard({
    required this.game,
    required this.isSaved,
    this.showFavBadge = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 75,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: game.coverGradient,
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(game.coverIcon,
                        size: 30, color: Colors.white60),
                  ),
                  if (game.isFree)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '免费',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (showFavBadge)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Icon(Icons.favorite_rounded,
                          size: 14, color: Colors.redAccent.shade100),
                    ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.name,
                    style: tt.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.star_rounded,
                          size: 11, color: Colors.amber.shade700),
                      const SizedBox(width: 2),
                      Text(
                        game.rating.toStringAsFixed(1),
                        style: tt.labelSmall?.copyWith(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
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
    );
  }
}
