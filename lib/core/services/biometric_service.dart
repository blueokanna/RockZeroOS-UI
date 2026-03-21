import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart' as local_auth;

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

// 生物识别服务 — 支持所有平台
//
// Windows: Windows Hello (指纹/人脸/PIN) — 通过 local_auth
//          支持 Broadcom CV3_WBF_PROVIDER_TOUCH 等 WBF 兼容传感器
// macOS:   Touch ID — 通过 local_auth
// Linux:   PAM 认证（指纹/密码） — 通过 local_auth
// Android: 指纹/人脸 — 通过原生平台通道
// iOS:     Touch ID/Face ID — 通过原生平台通道
class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  // 原有平台通道（Android/iOS）
  static const _channel = MethodChannel('rockzero/biometric');

  // 桌面平台使用 local_auth
  final local_auth.LocalAuthentication _localAuth =
      local_auth.LocalAuthentication();

  /// 是否使用 local_auth（桌面平台）
  bool get _useLocalAuth {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  // 检查当前平台是否支持生物识别
  bool get isPlatformSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux;
  }

  // 检查设备是否支持生物识别
  Future<bool> isAvailable() async {
    if (!isPlatformSupported) return false;

    if (_useLocalAuth) {
      return _isAvailableDesktop();
    }

    // 移动平台：使用原有平台通道
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

  /// 桌面平台：通过 local_auth 检查可用性
  Future<bool> _isAvailableDesktop() async {
    try {
      final canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final canAuthenticate =
          canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();

      if (canAuthenticate) {
        debugPrint(
            '[Biometric] Desktop biometric available (canCheckBiometrics=$canAuthenticateWithBiometrics)');
        if (Platform.isWindows) {
          debugPrint(
              '[Biometric] Windows Hello available (supports fingerprint/face/PIN via WBF)');
        } else if (Platform.isMacOS) {
          debugPrint('[Biometric] macOS Touch ID / password available');
        } else if (Platform.isLinux) {
          debugPrint('[Biometric] Linux PAM authentication available');
        }
      }

      return canAuthenticate;
    } catch (e) {
      debugPrint('[Biometric] Desktop biometric check failed: $e');
      return false;
    }
  }

  // 检查是否可以进行生物识别认证
  Future<bool> canAuthenticate() async {
    if (!isPlatformSupported) return false;

    if (_useLocalAuth) {
      return _isAvailableDesktop();
    }

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

    if (_useLocalAuth) {
      return _getAvailableBiometricsDesktop();
    }

    // 移动平台：使用原有平台通道
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

  /// 桌面平台：通过 local_auth 获取可用生物识别类型
  Future<List<BiometricType>> _getAvailableBiometricsDesktop() async {
    try {
      final biometrics = await _localAuth.getAvailableBiometrics();
      final result = <BiometricType>[];

      for (final b in biometrics) {
        switch (b) {
          case local_auth.BiometricType.fingerprint:
            result.add(BiometricType.fingerprint);
          case local_auth.BiometricType.face:
            result.add(BiometricType.face);
          case local_auth.BiometricType.iris:
            result.add(BiometricType.iris);
          case local_auth.BiometricType.strong:
            result.add(BiometricType.strong);
          case local_auth.BiometricType.weak:
            result.add(BiometricType.weak);
        }
      }

      // Windows Hello 统一报告为 strong 类型（兼容指纹/人脸/PIN）
      if (Platform.isWindows && result.isEmpty) {
        final isDeviceSupported = await _localAuth.isDeviceSupported();
        if (isDeviceSupported) {
          result.add(BiometricType.strong);
        }
      }

      debugPrint('[Biometric] Desktop available types: $result');
      return result;
    } catch (e) {
      debugPrint('[Biometric] Get desktop biometrics failed: $e');
      return [];
    }
  }

  // 执行生物识别认证
  Future<bool> authenticate({
    String reason = 'Please authenticate to continue',
    bool biometricOnly = false,
  }) async {
    if (!isPlatformSupported) return false;

    if (_useLocalAuth) {
      return _authenticateDesktop(
        reason: reason,
        biometricOnly: biometricOnly,
      );
    }

    // 移动平台：使用原有平台通道
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

  /// 桌面平台：通过 local_auth 执行认证
  ///
  /// Windows: 弹出 Windows Hello 对话框（指纹/人脸/PIN，取决于硬件）
  ///          Broadcom CV3_WBF_PROVIDER_TOUCH 等 WBF 传感器自动被 Windows Hello 识别
  /// macOS:   弹出 Touch ID 或密码对话框
  /// Linux:   通过 PAM 进行认证（系统密码或已注册的指纹）
  Future<bool> _authenticateDesktop({
    required String reason,
    bool biometricOnly = false,
  }) async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: reason,
        options: local_auth.AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: biometricOnly,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );

      debugPrint('[Biometric] Desktop authentication result: $authenticated');
      return authenticated;
    } on PlatformException catch (e) {
      debugPrint('[Biometric] Desktop authentication error: ${e.message}');
      // 常见错误处理
      if (e.code == 'NotAvailable') {
        debugPrint(
            '[Biometric] No biometric hardware or Windows Hello not configured');
      } else if (e.code == 'NotEnrolled') {
        debugPrint(
            '[Biometric] Biometric not enrolled — configure Windows Hello in Settings');
      } else if (e.code == 'LockedOut') {
        debugPrint(
            '[Biometric] Too many failed attempts — biometric temporarily locked');
      } else if (e.code == 'PermanentlyLockedOut') {
        debugPrint(
            '[Biometric] Biometric permanently locked — requires device unlock');
      }
      return false;
    } catch (e) {
      debugPrint('[Biometric] Desktop authentication exception: $e');
      return false;
    }
  }

  // 获取生物识别类型的显示名称
  String getBiometricTypeName(BiometricType type) {
    if (!kIsWeb && Platform.isWindows) {
      // Windows 使用 Windows Hello 品牌名称
      switch (type) {
        case BiometricType.fingerprint:
          return 'Windows Hello Fingerprint';
        case BiometricType.face:
          return 'Windows Hello Face';
        case BiometricType.strong:
          return 'Windows Hello';
        default:
          return 'Windows Hello';
      }
    }
    if (!kIsWeb && Platform.isMacOS) {
      switch (type) {
        case BiometricType.fingerprint:
          return 'Touch ID';
        case BiometricType.face:
          return 'Face ID';
        default:
          return 'Touch ID';
      }
    }

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
