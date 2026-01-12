import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/device_discovery_service.dart';
import '../../../auth/providers/auth_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final seedColor = ref.watch(seedColorProvider);
    final authState = ref.watch(authStateProvider);
    final device = ref.watch(connectedDeviceProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('Settings')),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (device != null)
                  _SettingsSection(
                    title: 'Connection',
                    children: [
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.cloud_done,
                            color: Colors.green,
                          ),
                        ),
                        title: Text(device.name),
                        subtitle: Text('${device.ip}:${device.port}'),
                        trailing: TextButton(
                          onPressed: () {
                            ref.read(connectedDeviceProvider.notifier).state =
                                null;
                            ref.read(authStateProvider.notifier).logout();
                            context.go('/discover');
                          },
                          child: const Text('Disconnect'),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05),

                const SizedBox(height: 16),

                _SettingsSection(
                  title: 'Appearance',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.brightness_6),
                      title: const Text('Theme'),
                      subtitle: Text(_getThemeModeName(themeMode)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showThemeDialog(context, ref, themeMode),
                    ),
                    ListTile(
                      leading: const Icon(Icons.palette),
                      title: const Text('Accent Color'),
                      trailing: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: seedColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: colorScheme.outline),
                        ),
                      ),
                      onTap: () => _showColorPicker(context, ref, seedColor),
                    ),
                  ],
                ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.05),

                const SizedBox(height: 16),

                _SettingsSection(
                  title: 'Security',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.fingerprint),
                      title: const Text('Biometric Authentication'),
                      subtitle: const Text('Use fingerprint or face to unlock'),
                      trailing: Switch(value: false, onChanged: (value) {}),
                    ),
                    ListTile(
                      leading: const Icon(Icons.key),
                      title: const Text('FIDO2 / Passkeys'),
                      subtitle: const Text('Manage security keys'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {},
                    ),
                    if (authState.user?.role == 'admin')
                      ListTile(
                        leading: const Icon(Icons.card_giftcard),
                        title: const Text('Invite Codes'),
                        subtitle: const Text(
                          'Generate invite codes for new users',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showInviteCodeDialog(context, ref),
                      ),
                  ],
                ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.05),

                const SizedBox(height: 16),

                _SettingsSection(
                  title: 'About',
                  children: [
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Version'),
                      subtitle: Text('1.0.0'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.code),
                      title: const Text('Open Source Licenses'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showLicensePage(context: context),
                    ),
                  ],
                ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.05),

                const SizedBox(height: 24),

                FilledButton.tonal(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Sign Out'),
                        content: const Text(
                          'Are you sure you want to sign out?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Sign Out'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true) {
                      await ref.read(authStateProvider.notifier).logout();
                      if (context.mounted) {
                        context.go('/discover');
                      }
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.errorContainer,
                    foregroundColor: colorScheme.onErrorContainer,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout),
                      SizedBox(width: 8),
                      Text('Sign Out'),
                    ],
                  ),
                ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.05),
              ]),
            ),
          ),
        ],
      ),
    );
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
    BuildContext context,
    WidgetRef ref,
    ThemeMode currentMode,
  ) {
    ThemeMode selectedMode = currentMode;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Theme'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: ThemeMode.values.map((mode) {
                return ListTile(
                  title: Text(_getThemeModeName(mode)),
                  leading: Icon(
                    selectedMode == mode
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selectedMode == mode
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  onTap: () {
                    setState(() => selectedMode = mode);
                    ref.read(themeModeProvider.notifier).setThemeMode(mode);
                    Navigator.pop(dialogContext);
                  },
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  void _showColorPicker(
    BuildContext context,
    WidgetRef ref,
    Color currentColor,
  ) {
    final colors = [
      Colors.blue,
      Colors.indigo,
      Colors.purple,
      Colors.deepPurple,
      Colors.pink,
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.yellow,
      Colors.lime,
      Colors.green,
      Colors.teal,
      Colors.cyan,
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accent Color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            final isSelected = color.toARGB32() == currentColor.toARGB32();
            return InkWell(
              onTap: () {
                ref.read(seedColorProvider.notifier).setSeedColor(color);
                Navigator.pop(context);
              },
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showInviteCodeDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final inviteCode = ref.watch(inviteCodeProvider);

          return AlertDialog(
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
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        code.code,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4,
                            ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Expires in ${code.expiresInSeconds ~/ 60} minutes',
                      style: Theme.of(context).textTheme.bodySmall,
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
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
