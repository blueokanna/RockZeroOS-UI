import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/device_discovery_service.dart';
import '../../../../core/services/biometric_service.dart';
import '../../../../core/services/fido2_service.dart';
import '../../../auth/providers/auth_provider.dart';

// Check if running on mobile platform
bool get _isMobilePlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final seedColor = ref.watch(seedColorProvider);
    final dynamicColorEnabled = ref.watch(dynamicColorEnabledProvider);
    final systemAccentColor = ref.watch(systemAccentColorProvider);
    final authState = ref.watch(authStateProvider);
    final device = ref.watch(connectedDeviceProvider);
    final biometricEnabled = ref.watch(biometricEnabledProvider);

    // Use system color if dynamic color is enabled
    final effectiveColor = dynamicColorEnabled && systemAccentColor != null
        ? systemAccentColor
        : seedColor;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('Settings')),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (device != null)
                  _buildConnectionSection(context, ref, device, colorScheme),
                const SizedBox(height: 16),
                _buildAppearanceSection(
                  context,
                  ref,
                  themeMode,
                  effectiveColor,
                  dynamicColorEnabled,
                  systemAccentColor,
                ),
                const SizedBox(height: 16),
                _buildSecuritySection(
                  context,
                  ref,
                  authState,
                  biometricEnabled,
                ),
                const SizedBox(height: 16),
                _buildAboutSection(context),
                const SizedBox(height: 24),
                _buildSignOutButton(context, ref, colorScheme),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionSection(
    BuildContext context,
    WidgetRef ref,
    DiscoveredDevice device,
    ColorScheme colorScheme,
  ) {
    return _SettingsSection(
      title: 'Connection',
      icon: Icons.cloud_done_rounded,
      children: [
        ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.cloud_done_rounded, color: Colors.green),
          ),
          title: Text(device.name),
          subtitle: Text('${device.ip}:${device.port}'),
          trailing: FilledButton.tonal(
            onPressed: () {
              ref.read(connectedDeviceProvider.notifier).setDevice(null);
              ref.read(authStateProvider.notifier).logout();
              context.go('/discover');
            },
            child: const Text('Disconnect'),
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(delay: 100.ms)
        .slideY(begin: 0.05, curve: M3Curves.emphasized);
  }

  Widget _buildAppearanceSection(
    BuildContext context,
    WidgetRef ref,
    ThemeMode themeMode,
    Color effectiveColor,
    bool dynamicColorEnabled,
    Color? systemAccentColor,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return _SettingsSection(
      title: 'Appearance',
      icon: Icons.palette_rounded,
      children: [
        ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.brightness_6_rounded,
                color: colorScheme.onPrimaryContainer),
          ),
          title: const Text('Theme'),
          subtitle: Text(_getThemeModeName(themeMode)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _showThemeDialog(context, ref, themeMode),
        ),
        ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: effectiveColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.palette_rounded, color: effectiveColor),
          ),
          title: const Text('Accent Color'),
          subtitle: const Text('Material You dynamic theming'),
          trailing: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: effectiveColor,
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.outline, width: 2),
              boxShadow: [
                BoxShadow(
                  color: effectiveColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          onTap: dynamicColorEnabled
              ? null
              : () => _showColorPicker(context, ref, effectiveColor),
        ),
        if (_isMobilePlatform)
          FutureBuilder<bool>(
            future: DynamicColorService.isDynamicColorAvailable(),
            builder: (context, snapshot) {
              final isAvailable = snapshot.data ?? false;
              return ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.auto_awesome_rounded,
                      color: colorScheme.onTertiaryContainer),
                ),
                title: const Text('Dynamic Color'),
                subtitle: Text(
                  isAvailable
                      ? 'Use system wallpaper colors'
                      : 'Not available on this device',
                ),
                trailing: Switch(
                  value: dynamicColorEnabled,
                  onChanged: isAvailable
                      ? (value) async {
                          await ref
                              .read(dynamicColorEnabledProvider.notifier)
                              .setEnabled(value);
                          if (value) {
                            await ref
                                .read(systemAccentColorProvider.notifier)
                                .refresh();
                          }
                        }
                      : null,
                ),
              );
            },
          ),
      ],
    )
        .animate()
        .fadeIn(delay: 200.ms)
        .slideY(begin: 0.05, curve: M3Curves.emphasized);
  }

  Widget _buildSecuritySection(
    BuildContext context,
    WidgetRef ref,
    AuthState authState,
    bool biometricEnabled,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final biometricAvailable = ref.watch(biometricAvailableProvider);
    final fido2Available = ref.watch(fido2AvailableProvider);

    return _SettingsSection(
      title: 'Security',
      icon: Icons.security_rounded,
      children: [
        if (_isMobilePlatform)
          biometricAvailable.when(
            data: (available) => ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.fingerprint_rounded,
                    color: colorScheme.onSecondaryContainer),
              ),
              title: const Text('Biometric Authentication'),
              subtitle: Text(
                available
                    ? 'Use fingerprint or face to unlock'
                    : 'Not available on this device',
              ),
              trailing: Switch(
                value: biometricEnabled,
                onChanged: available
                    ? (value) async {
                        await ref
                            .read(biometricEnabledProvider.notifier)
                            .setEnabled(value);
                      }
                    : null,
              ),
            ),
            loading: () => const ListTile(
              leading: SizedBox(
                width: 44,
                height: 44,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              title: Text('Biometric Authentication'),
              subtitle: Text('Checking availability...'),
            ),
            error: (_, __) => ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.error_outline_rounded,
                    color: colorScheme.onErrorContainer),
              ),
              title: const Text('Biometric Authentication'),
              subtitle: const Text('Error checking availability'),
            ),
          ),
        fido2Available.when(
          data: (available) => ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.key_rounded,
                  color: colorScheme.onPrimaryContainer),
            ),
            title:
                Text(_isMobilePlatform ? 'FIDO2 / Passkeys' : 'Security Keys'),
            subtitle: Text(
              available
                  ? 'Manage security keys'
                  : 'Not available on this device',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: available ? () => _showFido2Dialog(context, ref) : null,
          ),
          loading: () => const ListTile(
            leading: SizedBox(
              width: 44,
              height: 44,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            title: Text('Security Keys'),
            subtitle: Text('Checking availability...'),
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
        if (authState.user?.role == 'admin')
          ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.card_giftcard_rounded,
                  color: colorScheme.onTertiaryContainer),
            ),
            title: const Text('Invite Codes'),
            subtitle: const Text('Generate invite codes for new users'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showInviteCodeDialog(context, ref),
          ),
      ],
    )
        .animate()
        .fadeIn(delay: 300.ms)
        .slideY(begin: 0.05, curve: M3Curves.emphasized);
  }

  Widget _buildAboutSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _SettingsSection(
      title: 'About',
      icon: Icons.info_outline_rounded,
      children: [
        ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.info_outline_rounded,
                color: colorScheme.onSurfaceVariant),
          ),
          title: const Text('Version'),
          subtitle: const Text('1.0.0'),
        ),
        ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Icon(Icons.code_rounded, color: colorScheme.onSurfaceVariant),
          ),
          title: const Text('Open Source Licenses'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => showLicensePage(context: context),
        ),
      ],
    )
        .animate()
        .fadeIn(delay: 400.ms)
        .slideY(begin: 0.05, curve: M3Curves.emphasized);
  }

  Widget _buildSignOutButton(
      BuildContext context, WidgetRef ref, ColorScheme colorScheme) {
    return FilledButton.tonal(
      onPressed: () => _showSignOutDialog(context, ref),
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.errorContainer,
        foregroundColor: colorScheme.onErrorContainer,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.logout_rounded),
          SizedBox(width: 8),
          Text('Sign Out'),
        ],
      ),
    )
        .animate()
        .fadeIn(delay: 500.ms)
        .slideY(begin: 0.05, curve: M3Curves.emphasized);
  }

  String _getThemeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  void _showThemeDialog(
      BuildContext context, WidgetRef ref, ThemeMode currentMode) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Theme',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            ...ThemeMode.values.map((mode) {
              final isSelected = mode == currentMode;
              return ListTile(
                leading: Icon(
                  mode == ThemeMode.light
                      ? Icons.light_mode_rounded
                      : mode == ThemeMode.dark
                          ? Icons.dark_mode_rounded
                          : Icons.brightness_auto_rounded,
                  color:
                      isSelected ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(_getThemeModeName(mode)),
                trailing: isSelected
                    ? Icon(Icons.check_circle_rounded,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  ref.read(themeModeProvider.notifier).setThemeMode(mode);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showColorPicker(
      BuildContext context, WidgetRef ref, Color currentColor) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Accent Color',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: AppTheme.presetColors.map((color) {
                  final isSelected =
                      color.toARGB32() == currentColor.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      ref.read(seedColorProvider.notifier).setSeedColor(color);
                      Navigator.pop(context);
                    },
                    child: AnimatedContainer(
                      duration: M3Durations.short4,
                      curve: M3Curves.emphasized,
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color:
                                color.withValues(alpha: isSelected ? 0.5 : 0.3),
                            blurRadius: isSelected ? 12 : 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 28)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showSignOutDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.logout_rounded,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(authStateProvider.notifier).logout();
      if (context.mounted) {
        context.go('/discover');
      }
    }
  }

  void _showInviteCodeDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final inviteCode = ref.watch(inviteCodeProvider);
          final colorScheme = Theme.of(context).colorScheme;

          return AlertDialog(
            icon: Icon(Icons.card_giftcard_rounded,
                size: 48, color: colorScheme.primary),
            title: const Text('Invite Code'),
            content: inviteCode.when(
              data: (code) {
                if (code == null) {
                  return const Text('Failed to generate invite code');
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Share this code with new users:'),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SelectableText(
                        code.code,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4,
                              color: colorScheme.onPrimaryContainer,
                            ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Expires in ${code.expiresInSeconds ~/ 60} minutes',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                );
              },
              loading: () => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating code...'),
                ],
              ),
              error: (e, s) => const Text('Error generating invite code'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFido2Dialog(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final registeredKeys = ref.watch(registeredKeysProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _isMobilePlatform
                            ? Icons.key_rounded
                            : Icons.usb_rounded,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isMobilePlatform
                                ? 'FIDO2 / Passkeys'
                                : 'Security Keys',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Text(
                            'Passwordless authentication',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      _isMobilePlatform
                          ? 'Passkeys provide a more secure and convenient way to sign in without passwords.'
                          : 'Connect a USB security key (like YubiKey) to enhance your account security.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _registerNewKey(context, ref),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(_isMobilePlatform
                          ? 'Register Passkey'
                          : 'Register Security Key'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Registered Keys',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    registeredKeys.when(
                      data: (keys) {
                        if (keys.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.key_off_rounded,
                                  size: 48,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No security keys registered',
                                  style: TextStyle(
                                      color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          );
                        }
                        return Column(
                          children: keys
                              .map((key) => _SecurityKeyTile(
                                    securityKey: key,
                                    onDelete: () =>
                                        _deleteKey(context, ref, key),
                                    onRename: () =>
                                        _renameKey(context, ref, key),
                                  ))
                              .toList(),
                        );
                      },
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (e, s) => Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Failed to load keys',
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _registerNewKey(BuildContext context, WidgetRef ref) async {
    final fido2Service = ref.read(fido2ServiceProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // First check if FIDO2 is available
    final isAvailable = await fido2Service.isAvailable();
    if (!isAvailable) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.white),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('FIDO2/Passkey is not available on this device'),
                ),
              ],
            ),
            backgroundColor: colorScheme.error,
          ),
        );
      }
      return;
    }

    // Show loading dialog with cancel option
    bool cancelled = false;
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colorScheme.primary, colorScheme.tertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.key_rounded, size: 32, color: Colors.white),
        ),
        title: Text(
            _isMobilePlatform ? 'Register Passkey' : 'Register Security Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              _isMobilePlatform
                  ? 'Follow the prompts to register your passkey...'
                  : 'Insert and touch your security key...',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _isMobilePlatform
                  ? 'Use Face ID, Touch ID, or your device PIN'
                  : 'Make sure your security key is connected',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.pop(dialogContext);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    try {
      if (cancelled) return;

      final success = _isMobilePlatform
          ? await fido2Service.registerPlatformKey(keyName: 'My Passkey')
          : await fido2Service.registerCrossPlatformKey(
              keyName: 'Security Key');

      if (context.mounted && !cancelled) {
        Navigator.pop(context); // Close loading dialog

        if (success) {
          ref.invalidate(registeredKeysProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  const Text('Security key registered successfully'),
                ],
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                        'Failed to register security key. Please try again.'),
                  ),
                ],
              ),
              backgroundColor: colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted && !cancelled) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Error: $e')),
              ],
            ),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteKey(
      BuildContext context, WidgetRef ref, SecurityKey key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.delete_rounded,
            size: 48, color: Theme.of(context).colorScheme.error),
        title: const Text('Delete Security Key'),
        content: Text('Are you sure you want to delete "${key.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final fido2Service = ref.read(fido2ServiceProvider);
      final success = await fido2Service.deleteKey(key.id);
      if (success) {
        ref.invalidate(registeredKeysProvider);
      }
    }
  }

  Future<void> _renameKey(
      BuildContext context, WidgetRef ref, SecurityKey key) async {
    final controller = TextEditingController(text: key.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Security Key'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != key.name) {
      final fido2Service = ref.read(fido2ServiceProvider);
      final success = await fido2Service.renameKey(key.id, newName);
      if (success) {
        ref.invalidate(registeredKeysProvider);
      }
    }
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SecurityKeyTile extends StatelessWidget {
  final SecurityKey securityKey;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  const _SecurityKeyTile({
    required this.securityKey,
    required this.onDelete,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: securityKey.isPlatformKey
                ? colorScheme.primaryContainer
                : colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            securityKey.isPlatformKey
                ? Icons.smartphone_rounded
                : Icons.usb_rounded,
            color: securityKey.isPlatformKey
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSecondaryContainer,
          ),
        ),
        title: Text(securityKey.name),
        subtitle: Text(
          securityKey.lastUsedAt != null
              ? 'Last used: ${_formatDate(securityKey.lastUsedAt!)}'
              : 'Created: ${_formatDate(securityKey.createdAt)}',
          style: textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'rename') onRename();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'rename',
              child: Row(
                children: [
                  Icon(Icons.edit_rounded),
                  SizedBox(width: 12),
                  Text('Rename'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_rounded, color: colorScheme.error),
                  const SizedBox(width: 12),
                  Text('Delete', style: TextStyle(color: colorScheme.error)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
