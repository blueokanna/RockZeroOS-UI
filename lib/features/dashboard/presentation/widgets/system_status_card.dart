import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/theme/app_theme.dart';

class SystemStatusCard extends StatelessWidget {
  final AsyncValue<HardwareInfo?> hardwareInfo;

  const SystemStatusCard({super.key, required this.hardwareInfo});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, colorScheme.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.monitor_heart_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'System Status',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Real-time monitoring',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            hardwareInfo.when(
              data: (info) {
                if (info == null) return _buildErrorState(context);
                return _buildContent(context, info);
              },
              loading: () => _buildLoadingState(context),
              error: (e, s) => _buildErrorState(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, HardwareInfo info) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // System info row - more spacious
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: _InfoTile(
                  icon: Icons.computer_rounded,
                  label: 'Hostname',
                  value: info.system.hostname,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              Expanded(
                child: _InfoTile(
                  icon: Icons.memory_rounded,
                  label: 'Architecture',
                  value: info.system.architecture,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              Expanded(
                child: _InfoTile(
                  icon: Icons.schedule_rounded,
                  label: 'Uptime',
                  value: _formatUptime(info.system.uptime),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 100.ms, curve: M3Curves.emphasizedDecelerate),
        const SizedBox(height: 24),

        // Usage indicators - modern card style without spinning circles
        LayoutBuilder(
          builder: (context, constraints) {
            final hasTemp = info.cpu.temperature != null;
            final itemCount = hasTemp ? 3 : 2;
            final spacing = 16.0;
            final totalSpacing = spacing * (itemCount - 1);
            final itemWidth = (constraints.maxWidth - totalSpacing) / itemCount;

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: itemWidth,
                  child: _ModernUsageCard(
                    label: 'CPU',
                    value: info.cpu.usage,
                    icon: Icons.speed_rounded,
                    color: _getUsageColor(info.cpu.usage),
                    subtitle:
                        '${info.cpu.cores} cores • ${info.cpu.frequency} MHz',
                  ).animate().fadeIn(
                        delay: 150.ms,
                        curve: M3Curves.emphasizedDecelerate,
                      ),
                ),
                SizedBox(width: spacing),
                SizedBox(
                  width: itemWidth,
                  child: _ModernUsageCard(
                    label: 'Memory',
                    value: info.memory.usagePercentage,
                    icon: Icons.memory_rounded,
                    color: _getUsageColor(info.memory.usagePercentage),
                    subtitle:
                        '${_formatBytes(info.memory.used)} / ${_formatBytes(info.memory.total)}',
                  ).animate().fadeIn(
                        delay: 200.ms,
                        curve: M3Curves.emphasizedDecelerate,
                      ),
                ),
                if (hasTemp) ...[
                  SizedBox(width: spacing),
                  SizedBox(
                    width: itemWidth,
                    child: _ModernTemperatureCard(
                      temperature: info.cpu.temperature!,
                    ).animate().fadeIn(
                          delay: 250.ms,
                          curve: M3Curves.emphasizedDecelerate,
                        ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          height: 84,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: List.generate(
            3,
            (index) => Expanded(
              child: Container(
                height: 160,
                margin: EdgeInsets.only(right: index < 2 ? 16 : 0),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 36,
                color: colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load system info',
              style: textTheme.bodyLarge?.copyWith(
                color: colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatUptime(int seconds) {
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;

    if (days > 0) {
      return '${days}d ${hours}h';
    } else if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
  }

  Color _getUsageColor(double usage) {
    if (usage >= 90) return Colors.red;
    if (usage >= 70) return Colors.orange;
    if (usage >= 50) return Colors.amber.shade700;
    return Colors.green;
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Icon(icon, color: colorScheme.primary, size: 24),
        const SizedBox(height: 8),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Modern usage card with horizontal progress bar instead of circular spinner
class _ModernUsageCard extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final String subtitle;

  const _ModernUsageCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value),
            duration: M3Durations.long2,
            curve: M3Curves.emphasized,
            builder: (context, animValue, child) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${animValue.toStringAsFixed(1)}%',
                        style: textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: animValue / 100,
                      minHeight: 8,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Modern temperature card
class _ModernTemperatureCard extends StatelessWidget {
  final double temperature;

  const _ModernTemperatureCard({required this.temperature});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = _getTemperatureColor(temperature);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.thermostat_rounded, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Temperature',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: temperature),
            duration: M3Durations.long2,
            curve: M3Curves.emphasized,
            builder: (context, animValue, child) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${animValue.toStringAsFixed(0)}°C',
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (animValue / 100).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _getTemperatureStatus(temperature),
              style: textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getTemperatureColor(double temp) {
    if (temp >= 80) return Colors.red;
    if (temp >= 60) return Colors.orange;
    if (temp >= 40) return Colors.amber.shade700;
    return Colors.green;
  }

  String _getTemperatureStatus(double temp) {
    if (temp >= 80) return 'Critical';
    if (temp >= 60) return 'Warm';
    if (temp >= 40) return 'Normal';
    return 'Cool';
  }
}
