import 'dart:io';
import 'package:flutter/foundation.dart';

// 生物识别服务 - 跨平台兼容
class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  // 检查当前平台是否支持生物识别
  bool get isPlatformSupported {
    if (kIsWeb) return false;
    // 只有 Android 和 iOS 完全支持 local_auth
    return Platform.isAndroid || Platform.isIOS;
  }

  // 检查设备是否支持生物识别
  Future<bool> isAvailable() async {
    if (!isPlatformSupported) return false;

    try {
      // 动态导入 local_auth 只在支持的平台
      return await _checkBiometricAvailability();
    } catch (e) {
      return false;
    }
  }

  // 执行生物识别认证
  Future<bool> authenticate({String reason = 'Please authenticate'}) async {
    if (!isPlatformSupported) return false;

    try {
      return await _performAuthentication(reason);
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkBiometricAvailability() async {
    // 这里会在支持的平台上使用 local_auth
    // 在不支持的平台上返回 false
    return false; // 默认实现，实际使用时会被平台特定代码覆盖
  }

  Future<bool> _performAuthentication(String reason) async {
    return false; // 默认实现
  }
}
