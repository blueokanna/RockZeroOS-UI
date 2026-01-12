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
      state = state.copyWith(isLoading: false, error: 'Login failed');
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
      state = state.copyWith(isLoading: false, error: 'Registration failed');
      return false;
    }
  }

  Future<void> _saveAuthData(AuthResponse response) async {
    await _storage.write(
      key: 'access_token',
      value: response.tokens.accessToken,
    );
    await _storage.write(
      key: 'refresh_token',
      value: response.tokens.refreshToken,
    );
    await _storage.write(key: 'user_id', value: response.user.id);
    await _storage.write(key: 'user_email', value: response.user.email);
    await _storage.write(key: 'user_role', value: response.user.role);
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
