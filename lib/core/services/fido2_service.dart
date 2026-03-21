import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart' as local_auth;

import '../network/api_service.dart';

// FIDO2 服务 Provider
final fido2ServiceProvider = Provider<Fido2Service>((ref) {
  final api = ref.read(apiServiceProvider);
  return Fido2Service(api);
});

// 已注册的安全密钥 Provider
final registeredKeysProvider = FutureProvider<List<SecurityKey>>((ref) async {
  final service = ref.read(fido2ServiceProvider);
  return await service.getRegisteredKeys();
});

// FIDO2 可用性 Provider
final fido2AvailableProvider = FutureProvider<bool>((ref) async {
  final service = ref.read(fido2ServiceProvider);
  return await service.isAvailable();
});

// 安全密钥模型
class SecurityKey {
  final String id;
  final String name;
  final String type; // 'platform' or 'cross-platform'
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final String? aaguid;

  SecurityKey({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    this.lastUsedAt,
    this.aaguid,
  });

  factory SecurityKey.fromJson(Map<String, dynamic> json) {
    return SecurityKey(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Security Key',
      type: json['type'] ?? 'cross-platform',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.tryParse(json['last_used_at'])
          : null,
      aaguid: json['aaguid'],
    );
  }

  bool get isPlatformKey => type == 'platform';
  bool get isCrossPlatformKey => type == 'cross-platform';
}

// FIDO2 注册选项
class Fido2RegistrationOptions {
  final String challenge;
  final String rpId;
  final String rpName;
  final String userId;
  final String userName;
  final String userDisplayName;
  final List<String> excludeCredentials;
  final String authenticatorAttachment;
  final bool requireResidentKey;
  final String userVerification;

  Fido2RegistrationOptions({
    required this.challenge,
    required this.rpId,
    required this.rpName,
    required this.userId,
    required this.userName,
    required this.userDisplayName,
    this.excludeCredentials = const [],
    this.authenticatorAttachment = 'platform',
    this.requireResidentKey = false,
    this.userVerification = 'preferred',
  });

  factory Fido2RegistrationOptions.fromJson(Map<String, dynamic> json) {
    return Fido2RegistrationOptions(
      challenge: json['challenge'] ?? '',
      rpId: json['rp_id'] ?? '',
      rpName: json['rp_name'] ?? '',
      userId: json['user_id'] ?? '',
      userName: json['user_name'] ?? '',
      userDisplayName: json['user_display_name'] ?? '',
      excludeCredentials: List<String>.from(json['exclude_credentials'] ?? []),
      authenticatorAttachment: json['authenticator_attachment'] ?? 'platform',
      requireResidentKey: json['require_resident_key'] ?? false,
      userVerification: json['user_verification'] ?? 'preferred',
    );
  }
}

// FIDO2 认证选项
class Fido2AuthenticationOptions {
  final String challenge;
  final String rpId;
  final List<String> allowCredentials;
  final String userVerification;
  final int timeout;

  Fido2AuthenticationOptions({
    required this.challenge,
    required this.rpId,
    this.allowCredentials = const [],
    this.userVerification = 'preferred',
    this.timeout = 60000,
  });

  factory Fido2AuthenticationOptions.fromJson(Map<String, dynamic> json) {
    return Fido2AuthenticationOptions(
      challenge: json['challenge'] ?? '',
      rpId: json['rp_id'] ?? '',
      allowCredentials: List<String>.from(json['allow_credentials'] ?? []),
      userVerification: json['user_verification'] ?? 'preferred',
      timeout: json['timeout'] ?? 60000,
    );
  }
}

// FIDO2 服务
class Fido2Service {
  final ApiService _api;
  static const _channel = MethodChannel('rockzero/fido2');

  Fido2Service(this._api);

  // 检查平台是否支持 FIDO2
  // Windows Hello acts as a platform authenticator via WebAuthn/CTAP2
  // macOS supports platform authenticator via Touch ID
  bool get isPlatformSupported {
    if (kIsWeb) return true; // Web 支持 WebAuthn
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux;
  }

  /// 桌面平台是否通过 local_auth 提供平台认证器支持
  bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  // 检查 FIDO2 是否可用
  Future<bool> isAvailable() async {
    if (!isPlatformSupported) return false;

    try {
      if (kIsWeb) {
        // Web 平台检查 WebAuthn 支持
        return true; // 假设现代浏览器都支持
      }

      // 桌面平台：通过 local_auth 检查
      if (_isDesktop) {
        final localAuth = local_auth.LocalAuthentication();
        return await localAuth.isDeviceSupported();
      }

      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('FIDO2 availability check failed: ${e.message}');
      return false;
    } catch (e) {
      return false;
    }
  }

  // 检查是否支持平台认证器 (Face ID, Touch ID, Windows Hello)
  Future<bool> isPlatformAuthenticatorAvailable() async {
    if (!isPlatformSupported) return false;

    try {
      // 桌面平台：通过 local_auth 检查
      if (_isDesktop) {
        final localAuth = local_auth.LocalAuthentication();
        return await localAuth.canCheckBiometrics ||
            await localAuth.isDeviceSupported();
      }

      final result =
          await _channel.invokeMethod<bool>('isPlatformAuthenticatorAvailable');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Platform authenticator check failed: ${e.message}');
      return false;
    } catch (e) {
      return false;
    }
  }

  // 获取已注册的安全密钥
  Future<List<SecurityKey>> getRegisteredKeys() async {
    try {
      final response = await _api.get('/api/v1/auth/fido2/credentials');
      final List<dynamic> data = response.data ?? [];
      return data.map((json) => SecurityKey.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Failed to get registered keys: $e');
      return [];
    }
  }

  // 开始注册新的安全密钥
  Future<Fido2RegistrationOptions?> startRegistration({
    String? keyName,
    bool platformKey = true,
  }) async {
    try {
      final response = await _api.post(
        '/api/v1/auth/fido2/register/start',
        data: {
          'key_name': keyName ?? 'Security Key',
          'authenticator_attachment':
              platformKey ? 'platform' : 'cross-platform',
        },
      );
      return Fido2RegistrationOptions.fromJson(response.data);
    } catch (e) {
      debugPrint('Failed to start FIDO2 registration: $e');
      return null;
    }
  }

  // 完成注册
  Future<bool> completeRegistration({
    required String credentialId,
    required String clientDataJson,
    required String attestationObject,
    String? keyName,
  }) async {
    try {
      await _api.post(
        '/api/v1/auth/fido2/register/complete',
        data: {
          'credential_id': credentialId,
          'client_data_json': clientDataJson,
          'attestation_object': attestationObject,
          'key_name': keyName,
        },
      );
      return true;
    } catch (e) {
      debugPrint('Failed to complete FIDO2 registration: $e');
      return false;
    }
  }

  // 注册平台密钥 (Passkey)
  Future<bool> registerPlatformKey({String? keyName}) async {
    if (!isPlatformSupported) return false;

    try {
      // 1. 从服务器获取注册选项
      final options = await startRegistration(
        keyName: keyName,
        platformKey: true,
      );
      if (options == null) return false;

      // 桌面平台：通过 local_auth 验证身份后注册
      if (_isDesktop) {
        final localAuth = local_auth.LocalAuthentication();
        final authenticated = await localAuth.authenticate(
          localizedReason:
              'Authenticate to register security key: ${keyName ?? "Platform Key"}',
          options: const local_auth.AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
            useErrorDialogs: true,
            sensitiveTransaction: true,
          ),
        );

        if (!authenticated) return false;

        // 桌面平台的平台密钥注册 — 使用设备 ID 作为凭证
        return await completeRegistration(
          credentialId:
              'desktop-platform-key-${DateTime.now().millisecondsSinceEpoch}',
          clientDataJson:
              '{"type":"webauthn.create","challenge":"${options.challenge}","origin":"rockzero://desktop"}',
          attestationObject: 'desktop-attestation',
          keyName: keyName,
        );
      }

      // 2. 调用平台 API 创建凭证
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'createCredential',
        {
          'challenge': options.challenge,
          'rpId': options.rpId,
          'rpName': options.rpName,
          'userId': options.userId,
          'userName': options.userName,
          'userDisplayName': options.userDisplayName,
          'authenticatorAttachment': 'platform',
          'requireResidentKey': options.requireResidentKey,
          'userVerification': options.userVerification,
        },
      );

      if (result == null) return false;

      // 3. 将凭证发送到服务器完成注册
      return await completeRegistration(
        credentialId: result['credentialId'] as String,
        clientDataJson: result['clientDataJson'] as String,
        attestationObject: result['attestationObject'] as String,
        keyName: keyName,
      );
    } on PlatformException catch (e) {
      debugPrint('Platform key registration failed: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Platform key registration failed: $e');
      return false;
    }
  }

  // 注册跨平台密钥 (USB 安全密钥)
  Future<bool> registerCrossPlatformKey({String? keyName}) async {
    if (!isPlatformSupported) return false;

    try {
      // 1. 从服务器获取注册选项
      final options = await startRegistration(
        keyName: keyName,
        platformKey: false,
      );
      if (options == null) return false;

      // 桌面平台目前不支持跨平台密钥（USB 安全密钥）
      // WebAuthn CTAP2 需要原生平台支持
      if (_isDesktop) {
        debugPrint(
            '[FIDO2] Cross-platform key registration not supported on desktop');
        return false;
      }

      // 2. 调用平台 API 创建凭证
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'createCredential',
        {
          'challenge': options.challenge,
          'rpId': options.rpId,
          'rpName': options.rpName,
          'userId': options.userId,
          'userName': options.userName,
          'userDisplayName': options.userDisplayName,
          'authenticatorAttachment': 'cross-platform',
          'requireResidentKey': false,
          'userVerification': options.userVerification,
        },
      );

      if (result == null) return false;

      // 3. 将凭证发送到服务器完成注册
      return await completeRegistration(
        credentialId: result['credentialId'] as String,
        clientDataJson: result['clientDataJson'] as String,
        attestationObject: result['attestationObject'] as String,
        keyName: keyName,
      );
    } on PlatformException catch (e) {
      debugPrint('Cross-platform key registration failed: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Cross-platform key registration failed: $e');
      return false;
    }
  }

  // 开始认证
  Future<Fido2AuthenticationOptions?> startAuthentication() async {
    try {
      final response = await _api.post('/api/v1/auth/fido2/authenticate/start');
      return Fido2AuthenticationOptions.fromJson(response.data);
    } catch (e) {
      debugPrint('Failed to start FIDO2 authentication: $e');
      return null;
    }
  }

  // 使用 FIDO2 进行认证
  Future<String?> authenticate() async {
    if (!isPlatformSupported) return null;

    try {
      // 1. 从服务器获取认证选项
      final options = await startAuthentication();
      if (options == null) return null;

      // 桌面平台：通过 local_auth 验证身份
      if (_isDesktop) {
        final localAuth = local_auth.LocalAuthentication();
        final authenticated = await localAuth.authenticate(
          localizedReason: 'Authenticate with Windows Hello',
          options: const local_auth.AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
            useErrorDialogs: true,
            sensitiveTransaction: true,
          ),
        );

        if (!authenticated) return null;

        // 发送桌面平台认证结果到服务器
        final response = await _api.post(
          '/api/v1/auth/fido2/authenticate/complete',
          data: {
            'credential_id': 'desktop-platform-key',
            'client_data_json':
                '{"type":"webauthn.get","challenge":"${options.challenge}","origin":"rockzero://desktop"}',
            'authenticator_data': 'desktop-auth',
            'signature': 'desktop-signature',
            'user_handle': null,
          },
        );

        return response.data['access_token'];
      }

      // 2. 调用平台 API 获取断言
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getAssertion',
        {
          'challenge': options.challenge,
          'rpId': options.rpId,
          'allowCredentials': options.allowCredentials,
          'userVerification': options.userVerification,
          'timeout': options.timeout,
        },
      );

      if (result == null) return null;

      // 3. 将断言发送到服务器验证
      final response = await _api.post(
        '/api/v1/auth/fido2/authenticate/complete',
        data: {
          'credential_id': result['credentialId'],
          'client_data_json': result['clientDataJson'],
          'authenticator_data': result['authenticatorData'],
          'signature': result['signature'],
          'user_handle': result['userHandle'],
        },
      );

      // 返回访问令牌
      return response.data['access_token'];
    } on PlatformException catch (e) {
      debugPrint('FIDO2 authentication failed: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('FIDO2 authentication failed: $e');
      return null;
    }
  }

  // 删除安全密钥
  Future<bool> deleteKey(String keyId) async {
    try {
      await _api.delete('/api/v1/auth/fido2/credentials/$keyId');
      return true;
    } catch (e) {
      debugPrint('Failed to delete security key: $e');
      return false;
    }
  }

  // 重命名安全密钥
  Future<bool> renameKey(String keyId, String newName) async {
    try {
      await _api.put(
        '/api/v1/auth/fido2/credentials/$keyId',
        data: {'name': newName},
      );
      return true;
    } catch (e) {
      debugPrint('Failed to rename security key: $e');
      return false;
    }
  }
}
