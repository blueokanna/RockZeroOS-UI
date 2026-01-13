import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

// 生物识别服务 Provider
final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

// 生物识别可用性 Provider
final biometricAvailableProvider = FutureProvider<bool>((ref) async {
  final service = ref.read(biometricServiceProvider);
  return await service.isAvailable();
});

// 生物识别类型 Provider
final biometricTypesProvider = FutureProvider<List<BiometricType>>((ref) async {
  final service = ref.read(biometricServiceProvider);
  return await service.getAvailableBiometrics();
});

// 生物识别启用状态 Provider
final biometricEnabledProvider =
    NotifierProvider<BiometricEnabledNotifier, bool>(
  BiometricEnabledNotifier.new,
);

class BiometricEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    final box = Hive.box('settings');
    return box.get('biometricEnabled', defaultValue: false);
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      // 验证生物识别是否可用
      final service = ref.read(biometricServiceProvider);
      final available = await service.isAvailable();
      if (!available) {
        return;
      }

      // 尝试进行一次认证以确认用户意图
      final authenticated = await service.authenticate(
        reason: 'Enable biometric authentication',
      );
      if (!authenticated) {
        return;
      }
    }

    state = enabled;
    final box = Hive.box('settings');
    await box.put('biometricEnabled', enabled);
  }
}

// 生物识别类型枚举
enum BiometricType {
  fingerprint,
  face,
  iris,
  strong,
  weak,
}

// 生物识别服务
class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  static const _channel = MethodChannel('rockzero/biometric');

  // 检查当前平台是否支持生物识别
  bool get isPlatformSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  // 检查设备是否支持生物识别
  Future<bool> isAvailable() async {
    if (!isPlatformSupported) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Biometric availability check failed: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Biometric availability check failed: $e');
      return false;
    }
  }

  // 检查是否可以进行生物识别认证
  Future<bool> canAuthenticate() async {
    if (!isPlatformSupported) return false;

    try {
      final result = await _channel.invokeMethod<bool>('canAuthenticate');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Biometric canAuthenticate check failed: ${e.message}');
      return false;
    } catch (e) {
      return false;
    }
  }

  // 获取可用的生物识别类型
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (!isPlatformSupported) return [];

    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('getAvailableBiometrics');
      if (result == null) return [];

      return result.map((type) {
        switch (type.toString()) {
          case 'fingerprint':
            return BiometricType.fingerprint;
          case 'face':
            return BiometricType.face;
          case 'iris':
            return BiometricType.iris;
          case 'strong':
            return BiometricType.strong;
          case 'weak':
            return BiometricType.weak;
          default:
            return BiometricType.weak;
        }
      }).toList();
    } on PlatformException catch (e) {
      debugPrint('Get available biometrics failed: ${e.message}');
      return [];
    } catch (e) {
      return [];
    }
  }

  // 执行生物识别认证
  Future<bool> authenticate({
    String reason = 'Please authenticate to continue',
    bool biometricOnly = false,
  }) async {
    if (!isPlatformSupported) return false;

    try {
      final result = await _channel.invokeMethod<bool>('authenticate', {
        'reason': reason,
        'biometricOnly': biometricOnly,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Biometric authentication failed: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Biometric authentication failed: $e');
      return false;
    }
  }

  // 获取生物识别类型的显示名称
  String getBiometricTypeName(BiometricType type) {
    switch (type) {
      case BiometricType.fingerprint:
        return 'Fingerprint';
      case BiometricType.face:
        return 'Face ID';
      case BiometricType.iris:
        return 'Iris';
      case BiometricType.strong:
        return 'Strong Biometric';
      case BiometricType.weak:
        return 'Biometric';
    }
  }

  // 获取生物识别类型的图标
  String getBiometricTypeIcon(BiometricType type) {
    switch (type) {
      case BiometricType.fingerprint:
        return 'fingerprint';
      case BiometricType.face:
        return 'face';
      case BiometricType.iris:
        return 'visibility';
      case BiometricType.strong:
      case BiometricType.weak:
        return 'security';
    }
  }
}
