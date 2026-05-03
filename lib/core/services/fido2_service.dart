import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart' as local_auth;

import '../network/api_service.dart';

final fido2ServiceProvider = Provider<Fido2Service>((ref) {
  final api = ref.read(apiServiceProvider);
  return Fido2Service(api);
});

final registeredKeysProvider = FutureProvider<List<SecurityKey>>((ref) async {
  final service = ref.read(fido2ServiceProvider);
  return await service.getRegisteredKeys();
});

final fido2AvailableProvider = FutureProvider<bool>((ref) async {
  final service = ref.read(fido2ServiceProvider);
  return await service.isAvailable();
});

class SecurityKey {
  final String id;
  final String name;
  final String type;
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

class Fido2Service {
  final ApiService _api;
  static const _channel = MethodChannel('rockzero/fido2');

  Fido2Service(this._api);

  bool get isPlatformSupported {
    if (kIsWeb) return true;
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux;
  }

  bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  Future<bool> isAvailable() async {
    if (!isPlatformSupported) return false;

    try {
      if (kIsWeb) {
        return true;
      }

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

  Future<bool> isPlatformAuthenticatorAvailable() async {
    if (!isPlatformSupported) return false;

    try {
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

  Future<bool> registerPlatformKey({String? keyName}) async {
    if (!isPlatformSupported) return false;

    try {
      final options = await startRegistration(
        keyName: keyName,
        platformKey: true,
      );
      if (options == null) return false;

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

        return await completeRegistration(
          credentialId:
              'desktop-platform-key-${DateTime.now().millisecondsSinceEpoch}',
          clientDataJson:
              '{"type":"webauthn.create","challenge":"${options.challenge}","origin":"rockzero://desktop"}',
          attestationObject: 'desktop-attestation',
          keyName: keyName,
        );
      }

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

  Future<bool> registerCrossPlatformKey({String? keyName}) async {
    if (!isPlatformSupported) return false;

    try {
      final options = await startRegistration(
        keyName: keyName,
        platformKey: false,
      );
      if (options == null) return false;

      if (_isDesktop) {
        debugPrint(
            '[FIDO2] Cross-platform key registration not supported on desktop');
        return false;
      }

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

  Future<Fido2AuthenticationOptions?> startAuthentication() async {
    try {
      final response = await _api.post('/api/v1/auth/fido2/authenticate/start');
      return Fido2AuthenticationOptions.fromJson(response.data);
    } catch (e) {
      debugPrint('Failed to start FIDO2 authentication: $e');
      return null;
    }
  }

  Future<String?> authenticate() async {
    if (!isPlatformSupported) return null;

    try {
      final options = await startAuthentication();
      if (options == null) return null;

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

      return response.data['access_token'];
    } on PlatformException catch (e) {
      debugPrint('FIDO2 authentication failed: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('FIDO2 authentication failed: $e');
      return null;
    }
  }

  Future<bool> deleteKey(String keyId) async {
    try {
      await _api.delete('/api/v1/auth/fido2/credentials/$keyId');
      return true;
    } catch (e) {
      debugPrint('Failed to delete security key: $e');
      return false;
    }
  }

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
