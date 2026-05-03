import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart' as local_auth;

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

final biometricAvailableProvider = FutureProvider<bool>((ref) async {
  final service = ref.read(biometricServiceProvider);
  return await service.isAvailable();
});

final biometricTypesProvider = FutureProvider<List<BiometricType>>((ref) async {
  final service = ref.read(biometricServiceProvider);
  return await service.getAvailableBiometrics();
});

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
      final service = ref.read(biometricServiceProvider);
      final available = await service.isAvailable();
      if (!available) {
        return;
      }

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

enum BiometricType {
  fingerprint,
  face,
  iris,
  strong,
  weak,
}

class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  static const _channel = MethodChannel('rockzero/biometric');

  final local_auth.LocalAuthentication _localAuth =
      local_auth.LocalAuthentication();

  bool get _useLocalAuth {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  bool get isPlatformSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux;
  }

  Future<bool> isAvailable() async {
    if (!isPlatformSupported) return false;

    if (_useLocalAuth) {
      return _isAvailableDesktop();
    }

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

  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (!isPlatformSupported) return [];

    if (_useLocalAuth) {
      return _getAvailableBiometricsDesktop();
    }

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

  String getBiometricTypeName(BiometricType type) {
    if (!kIsWeb && Platform.isWindows) {
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
