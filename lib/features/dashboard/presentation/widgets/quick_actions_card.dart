import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

class QuickActionsCard extends StatelessWidget {
  const QuickActionsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flash_on, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Quick Actions',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ActionButton(
                  icon: Icons.upload_file,
                  label: 'Upload',
                  color: colorScheme.primaryContainer,
                  iconColor: colorScheme.onPrimaryContainer,
                  onTap: () => context.go('/files'),
                ).animate(delay: 100.ms).scale(begin: const Offset(0.8, 0.8)),
                _ActionButton(
                  icon: Icons.folder_open,
                  label: 'Files',
                  color: colorScheme.secondaryContainer,
                  iconColor: colorScheme.onSecondaryContainer,
                  onTap: () => context.go('/files'),
                ).animate(delay: 150.ms).scale(begin: const Offset(0.8, 0.8)),
                _ActionButton(
                  icon: Icons.play_circle,
                  label: 'Media',
                  color: colorScheme.tertiaryContainer,
                  iconColor: colorScheme.onTertiaryContainer,
                  onTap: () => context.go('/media'),
                ).animate(delay: 200.ms).scale(begin: const Offset(0.8, 0.8)),
                _ActionButton(
                  icon: Icons.apps,
                  label: 'Apps',
                  color: colorScheme.errorContainer,
                  iconColor: colorScheme.onErrorContainer,
                  onTap: () => context.go('/appstore'),
                ).animate(delay: 250.ms).scale(begin: const Offset(0.8, 0.8)),
                _ActionButton(
                  icon: Icons.settings,
                  label: 'Settings',
                  color: colorScheme.surfaceContainerHighest,
                  iconColor: colorScheme.onSurface,
                  onTap: () => context.go('/settings'),
                ).animate(delay: 300.ms).scale(begin: const Offset(0.8, 0.8)),
                _ActionButton(
                  icon: Icons.terminal,
                  label: 'System',
                  color: colorScheme.inverseSurface.withValues(alpha: 0.1),
                  iconColor: colorScheme.onSurface,
                  onTap: () => context.go('/system'),
                ).animate(delay: 350.ms).scale(begin: const Offset(0.8, 0.8)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 80,
          height: 80,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor, size: 28),
              const SizedBox(height: 4),
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: iconColor,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
