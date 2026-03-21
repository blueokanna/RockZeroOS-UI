import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// HLS播放模式
/// 注意：简单HLS已移除，现在只支持安全HLS
enum HlsMode {
  /// 安全HLS - SAE握手 + ZKP验证 + AES-256-GCM加密（唯一支持的模式）
  secure,
}

/// HLS配置服务
class HlsConfigService {
  static const String _boxName = 'settings';
  static const String _keyHlsMode = 'hls_mode';

  /// 获取当前HLS模式（始终返回secure）
  HlsMode getHlsMode() {
    // 简单HLS已移除，始终使用安全HLS
    return HlsMode.secure;
  }

  /// 设置HLS模式（已废弃，始终使用secure）
  Future<void> setHlsMode(HlsMode mode) async {
    final box = Hive.box(_boxName);
    // 始终设置为secure
    await box.put(_keyHlsMode, 'secure');
  }

  /// 是否使用安全HLS（始终返回true）
  bool get isSecureMode => true;
}

/// HLS配置服务Provider
final hlsConfigServiceProvider = Provider<HlsConfigService>((ref) {
  return HlsConfigService();
});

/// HLS模式Provider（始终返回secure）
final hlsModeProvider = Provider<HlsMode>((ref) {
  return HlsMode.secure;
});
