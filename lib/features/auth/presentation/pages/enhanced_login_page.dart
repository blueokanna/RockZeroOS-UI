import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/biometric_service.dart';
import '../../../../core/services/fido2_service.dart';
import '../../../../core/widgets/wallpaper_background.dart';
import '../../providers/auth_provider.dart';
import 'register_page.dart';

/// 增强的登录页面 - 支持密码、指纹和 FIDO2/Passkey 登录
class EnhancedLoginPage extends ConsumerStatefulWidget {
  const EnhancedLoginPage({super.key});

  @override
  ConsumerState<EnhancedLoginPage> createState() => _EnhancedLoginPageState();
}

class _EnhancedLoginPageState extends ConsumerState<EnhancedLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handlePasswordLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final success = await ref.read(authStateProvider.notifier).login(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );

      if (success && mounted) {
        Navigator.of(context).pushReplacementNamed('/dashboard');
      } else if (mounted) {
        _showError('Login failed. Please check your credentials.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleBiometricLogin() async {
    final biometricService = ref.read(biometricServiceProvider);
    final biometricEnabled = ref.read(biometricEnabledProvider);

    if (!biometricEnabled) {
      _showError(
          'Biometric authentication is not enabled. Please enable it in settings.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authenticated = await biometricService.authenticate(
        reason: 'Authenticate to login to RockZeroOS',
      );

      if (authenticated) {
        final success =
            await ref.read(authStateProvider.notifier).loginWithBiometric();

        if (success && mounted) {
          // Use addPostFrameCallback to ensure state updates are complete
          // before navigation, preventing login loop issues
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).pushReplacementNamed('/dashboard');
            }
          });
        } else if (mounted) {
          _showError('Biometric login failed. Please try password login.');
        }
      }
    } catch (e) {
      debugPrint('❌ Biometric login error: $e');
      _showError('Biometric authentication failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handlePasskeyLogin() async {
    final fido2Service = ref.read(fido2ServiceProvider);

    setState(() => _isLoading = true);

    try {
      final accessToken = await fido2Service.authenticate();

      if (accessToken != null && mounted) {
        // Token 已经在 FIDO2 服务中保存，直接跳转
        Navigator.of(context).pushReplacementNamed('/dashboard');
      } else if (mounted) {
        _showError('Passkey authentication failed. Please try another method.');
      }
    } catch (e) {
      debugPrint('❌ Passkey login error: $e');
      _showError('Passkey authentication failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final biometricAvailable = ref.watch(biometricAvailableProvider);
    final fido2Available = ref.watch(fido2AvailableProvider);

    return WallpaperBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: GlassmorphicBackground(
                blur: 20,
                opacity: 0.8,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [colorScheme.primary, colorScheme.tertiary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.rocket_launch_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Title
                      Text(
                        'Welcome Back',
                        style: textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sign in to continue to RockZeroOS',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Login Form
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // Email Field
                            TextFormField(
                              controller: _emailController,
                              decoration: InputDecoration(
                                labelText: 'Email or Username',
                                prefixIcon:
                                    const Icon(Icons.person_outline_rounded),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your email or username';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Password Field
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon:
                                    const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _handlePasswordLogin(),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your password';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),

                            // Login Button
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: FilledButton(
                                onPressed:
                                    _isLoading ? null : _handlePasswordLogin,
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Sign In'),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Alternative Login Methods
                      if (biometricAvailable.value == true ||
                          fido2Available.value == true) ...[
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                                child: Divider(color: colorScheme.outline)),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'OR',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                                child: Divider(color: colorScheme.outline)),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Alternative Login Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Biometric Login
                            if (biometricAvailable.value == true)
                              _AlternativeLoginButton(
                                icon: Icons.fingerprint_rounded,
                                label: 'Biometric',
                                onPressed:
                                    _isLoading ? null : _handleBiometricLogin,
                                color: Colors.green,
                              ),

                            if (biometricAvailable.value == true &&
                                fido2Available.value == true)
                              const SizedBox(width: 16),

                            // Passkey Login
                            if (fido2Available.value == true)
                              _AlternativeLoginButton(
                                icon: Icons.key_rounded,
                                label: 'Passkey',
                                onPressed:
                                    _isLoading ? null : _handlePasskeyLogin,
                                color: Colors.blue,
                              ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Register Link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account? ",
                            style: textTheme.bodyMedium,
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const RegisterPage(),
                                ),
                              );
                            },
                            child: const Text('Sign Up'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlternativeLoginButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;

  const _AlternativeLoginButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: IconButton(
            icon: Icon(icon, size: 32),
            color: color,
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
