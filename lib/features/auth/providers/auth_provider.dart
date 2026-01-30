import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thirds/blake3.dart' as blake3;

import '../../../core/models/api_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_service.dart';

// Secure storage provider
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

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

    // 只有在有token和用户数据时才标记为已认证
    // 但不自动登录，需要用户进行生物识别或密码认证
    if (accessToken != null && userJson != null) {
      try {
        final user = User.fromJson(jsonDecode(userJson));
        // 不设置 isAuthenticated = true，让用户重新认证
        state = state.copyWith(user: user, isAuthenticated: false);
      } catch (e) {
        debugPrint('[Auth] Failed to parse stored user: $e');
        await _storage.deleteAll();
      }
    }
  }

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _api.login(email: email, password: password);

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

      // 保存认证数据（包括密码哈希）
      await _saveAuthData(response, password: password);

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

  Future<bool> loginWithBiometric() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final accessToken = await _storage.read(key: 'access_token');
      final refreshToken = await _storage.read(key: 'refresh_token');
      final userJson = await _storage.read(key: 'user');

      if (accessToken == null || refreshToken == null || userJson == null) {
        state = state.copyWith(
          isLoading: false,
          error:
              'No stored credentials found. Please sign in with password first.',
        );
        return false;
      }

      try {
        // 尝试刷新token以验证会话是否有效
        final newTokens = await _api.refreshToken(refreshToken);
        await _storage.write(key: 'access_token', value: newTokens.accessToken);
        await _storage.write(
            key: 'refresh_token', value: newTokens.refreshToken);

        final user = User.fromJson(jsonDecode(userJson));

        state = state.copyWith(
          user: user,
          isLoading: false,
          isAuthenticated: true,
        );
        return true;
      } catch (e) {
        debugPrint('[Auth] Token refresh failed: $e');
        // Token过期或无效，清除存储的凭据
        await _storage.deleteAll();
        state = state.copyWith(
          isLoading: false,
          error: 'Session expired. Please sign in with password.',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Biometric login failed: ${e.toString()}',
      );
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    String? inviteCode,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // 从email生成username（使用@前面的部分）
      final username = email.split('@').first;

      final response = await _api.register(
        username: username,
        email: email,
        password: password,
        inviteCode: inviteCode,
      );

      if (!response.success) {
        state = state.copyWith(
          isLoading: false,
          error: response.message.isNotEmpty
              ? response.message
              : 'Registration failed',
        );
        return false;
      }

      // Auto-login after registration
      return await login(email: email, password: password);
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Registration failed: ${e.toString()}',
      );
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    state = const AuthState();
  }

  /// 保存 tokens（用于 ZKP 认证后保存 tokens）
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);

    // 尝试获取用户信息
    try {
      final userResponse = await _api.getCurrentUser();
      if (userResponse != null) {
        await _storage.write(
            key: 'user', value: jsonEncode(userResponse.toJson()));
        await _storage.write(key: 'user_id', value: userResponse.id);
        await _storage.write(key: 'user_email', value: userResponse.email);
        await _storage.write(key: 'user_role', value: userResponse.role);

        state = state.copyWith(
          user: userResponse,
          isAuthenticated: true,
        );
      }
    } catch (e) {
      debugPrint('[Auth] Failed to get user info after ZKP login: $e');
    }
  }

  Future<void> _saveAuthData(AuthResponse response, {String? password}) async {
    if (response.tokens != null) {
      await _storage.write(
          key: 'access_token', value: response.tokens!.accessToken);
      await _storage.write(
          key: 'refresh_token', value: response.tokens!.refreshToken);
    }

    if (response.user != null) {
      await _storage.write(
          key: 'user', value: jsonEncode(response.user!.toJson()));
      await _storage.write(key: 'user_id', value: response.user!.id);
      await _storage.write(key: 'user_email', value: response.user!.email);
      await _storage.write(key: 'user_role', value: response.user!.role);

      // 保存密码哈希（用于 SAE 握手）
      // 注意：这里保存的是密码的 SHA3-256 哈希，不是明文密码
      if (password != null) {
        final passwordHash = _hashPassword(password);
        await _storage.write(key: 'user_password_hash', value: passwordHash);
        debugPrint('[Auth] ✅ Saved password hash for SAE handshake');
      }
    }
  }

  /// 计算密码的 Blake3 哈希
  ///
  /// 这个哈希值用于 SAE 握手，不是用于认证
  /// 认证使用的是 JWT token
  /// 与 Rust 端的 compute_sae_secret 函数保持一致
  String _hashPassword(String password) {
    // 使用 Blake3 哈希（与 Rust blake3::hash 兼容）
    final hash = blake3.blake3(utf8.encode(password), 32);
    return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

// Invite code provider with persistent state
class InviteCodeState {
  final InviteCodeResponse? code;
  final DateTime? expiresAt;
  final bool isLoading;
  final String? error;

  const InviteCodeState({
    this.code,
    this.expiresAt,
    this.isLoading = false,
    this.error,
  });

  bool get isExpired {
    if (expiresAt == null) return true;
    return DateTime.now().isAfter(expiresAt!);
  }

  int get remainingSeconds {
    if (expiresAt == null) return 0;
    final diff = expiresAt!.difference(DateTime.now());
    return diff.inSeconds.clamp(0, 3600);
  }

  InviteCodeState copyWith({
    InviteCodeResponse? code,
    DateTime? expiresAt,
    bool? isLoading,
    String? error,
  }) {
    return InviteCodeState(
      code: code ?? this.code,
      expiresAt: expiresAt ?? this.expiresAt,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class InviteCodeNotifier extends Notifier<InviteCodeState> {
  Timer? _refreshTimer;

  @override
  InviteCodeState build() {
    _loadPersistedState();
    return const InviteCodeState(isLoading: true);
  }

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final codeJson = prefs.getString('invite_code');
      final expiresAtMs = prefs.getInt('invite_code_expires_at');

      if (codeJson != null && expiresAtMs != null) {
        final code = InviteCodeResponse.fromJson(jsonDecode(codeJson));
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs);

        if (DateTime.now().isBefore(expiresAt)) {
          state = InviteCodeState(
            code: code,
            expiresAt: expiresAt,
            isLoading: false,
          );
          _startRefreshTimer();
          return;
        }
      }
    } catch (e) {
      debugPrint('[InviteCode] Failed to load persisted state: $e');
    }

    await refresh();
  }

  Future<void> refresh() async {
    final authState = ref.read(authStateProvider);
    final user = authState.user;
    if (!authState.isAuthenticated || user == null || user.role != 'admin') {
      state = const InviteCodeState(
        error: 'Not authorized',
        isLoading: false,
      );
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final api = ref.read(apiServiceProvider);
      final code = await api.generateInviteCode();

      final expiresAt = DateTime.now().add(const Duration(hours: 1));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('invite_code', jsonEncode(code.toJson()));
      await prefs.setInt(
          'invite_code_expires_at', expiresAt.millisecondsSinceEpoch);

      state = InviteCodeState(
        code: code,
        expiresAt: expiresAt,
        isLoading: false,
      );

      _startRefreshTimer();
    } catch (e) {
      state = InviteCodeState(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();

    final remainingSeconds = state.remainingSeconds;
    if (remainingSeconds > 0) {
      _refreshTimer = Timer(Duration(seconds: remainingSeconds), refresh);
    }
  }

  void cancelTimer() {
    _refreshTimer?.cancel();
  }
}

final inviteCodeProvider =
    NotifierProvider<InviteCodeNotifier, InviteCodeState>(
  InviteCodeNotifier.new,
);
