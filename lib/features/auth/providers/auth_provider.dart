import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/models/api_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_service.dart';
import '../../../core/services/device_discovery_service.dart';

// Auth state
class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;
  final bool isAuthenticated;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.isAuthenticated = false,
  });

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
    bool? isAuthenticated,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}

// Auth state provider (Riverpod 3.x Notifier API)
final authStateProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _checkAuthStatus();
    return const AuthState();
  }

  FlutterSecureStorage get _storage => ref.read(secureStorageProvider);
  ApiService get _api => ref.read(apiServiceProvider);

  Future<void> _checkAuthStatus() async {
    final accessToken = await _storage.read(key: 'access_token');
    final userJson = await _storage.read(key: 'user');

    if (accessToken != null && userJson != null) {
      state = state.copyWith(isAuthenticated: true);
    }
  }

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _api.login(email: email, password: password);

      // 检查响应是否成功
      if (!response.success ||
          response.user == null ||
          response.tokens == null) {
        state = state.copyWith(
            isLoading: false,
            error: response.message.isNotEmpty
                ? response.message
                : 'Login failed');
        return false;
      }

      await _saveAuthData(response);

      state = state.copyWith(
        user: response.user,
        isLoading: false,
        isAuthenticated: true,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'Login failed: ${e.toString()}');
      return false;
    }
  }

  /// Login with biometric - uses stored credentials
  Future<bool> loginWithBiometric() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Check if we have stored credentials
      final accessToken = await _storage.read(key: 'access_token');
      final refreshToken = await _storage.read(key: 'refresh_token');
      final userId = await _storage.read(key: 'user_id');
      final userEmail = await _storage.read(key: 'user_email');
      final userRole = await _storage.read(key: 'user_role');

      if (accessToken != null && userId != null && userEmail != null) {
        // We have stored session, validate it
        try {
          // Try to refresh the token to ensure it's valid
          if (refreshToken != null) {
            final newTokens = await _api.refreshToken(refreshToken);
            await _storage.write(
                key: 'access_token', value: newTokens.accessToken);
            await _storage.write(
                key: 'refresh_token', value: newTokens.refreshToken);
          }

          // Create user from stored data
          final user = User(
            id: userId,
            username: userEmail.split('@').first,
            email: userEmail,
            role: userRole ?? 'user',
            createdAt: null, // 修复：使用 null 而不是 DateTime.now()
          );

          state = state.copyWith(
            user: user,
            isLoading: false,
            isAuthenticated: true,
          );
          return true;
        } catch (_) {
          // Token refresh failed, need to login again
          state = state.copyWith(
            isLoading: false,
            error: 'Session expired. Please sign in with password.',
          );
          return false;
        }
      }

      state = state.copyWith(
        isLoading: false,
        error: 'No stored credentials. Please sign in first.',
      );
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Biometric login failed');
      return false;
    }
  }

  Future<bool> register({
    required String username,
    required String email,
    required String password,
    String? inviteCode,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _api.register(
        username: username,
        email: email,
        password: password,
        inviteCode: inviteCode,
      );

      // 检查响应是否成功
      if (!response.success ||
          response.user == null ||
          response.tokens == null) {
        state = state.copyWith(
            isLoading: false,
            error: response.message.isNotEmpty
                ? response.message
                : 'Registration failed');
        return false;
      }

      await _saveAuthData(response);

      state = state.copyWith(
        user: response.user,
        isLoading: false,
        isAuthenticated: true,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'Registration failed: ${e.toString()}');
      return false;
    }
  }

  Future<void> _saveAuthData(AuthResponse response) async {
    if (response.tokens == null || response.user == null) {
      throw Exception('Invalid auth response: missing tokens or user data');
    }

    debugPrint('💾 [Auth] 保存认证数据...');
    debugPrint(
        '   Access Token: ${response.tokens!.accessToken.substring(0, 20)}...');
    debugPrint('   User ID: ${response.user!.id}');
    debugPrint('   User Email: ${response.user!.email}');

    await _storage.write(
      key: 'access_token',
      value: response.tokens!.accessToken,
    );
    await _storage.write(
      key: 'refresh_token',
      value: response.tokens!.refreshToken,
    );
    await _storage.write(key: 'user_id', value: response.user!.id);
    await _storage.write(key: 'user_email', value: response.user!.email);
    await _storage.write(key: 'user_role', value: response.user!.role);

    debugPrint('✅ [Auth] 认证数据保存完成');
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    ref.read(connectedDeviceProvider.notifier).setDevice(null);
    state = const AuthState();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Invite code provider
final inviteCodeProvider =
    FutureProvider.autoDispose<InviteCodeResponse?>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (!authState.isAuthenticated || authState.user?.role != 'admin') {
    return null;
  }

  try {
    final api = ref.read(apiServiceProvider);
    return await api.generateInviteCode();
  } catch (_) {
    return null;
  }
});
