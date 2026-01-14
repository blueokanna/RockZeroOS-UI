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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, colorScheme.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.monitor_heart_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'System Status',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Real-time monitoring',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
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
        // System info row
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
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
                height: 40,
                color: colorScheme.outlineVariant,
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
                height: 40,
                color: colorScheme.outlineVariant,
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
        const SizedBox(height: 20),

        // Usage indicators - horizontal layout with consistent sizing
        LayoutBuilder(
          builder: (context, constraints) {
            final hasTemp = info.cpu.temperature != null;
            final itemCount = hasTemp ? 3 : 2;
            final spacing = 12.0;
            final totalSpacing = spacing * (itemCount - 1);
            final itemWidth = (constraints.maxWidth - totalSpacing) / itemCount;

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: itemWidth,
                  child:
                      _UsageIndicator(
                        label: 'CPU',
                        value: info.cpu.usage,
                        icon: Icons.speed_rounded,
                        color: _getUsageColor(info.cpu.usage),
                        subtitle: '${info.cpu.cores} cores',
                      ).animate().fadeIn(
                        delay: 150.ms,
                        curve: M3Curves.emphasizedDecelerate,
                      ),
                ),
                SizedBox(width: spacing),
                SizedBox(
                  width: itemWidth,
                  child:
                      _UsageIndicator(
                        label: 'Memory',
                        value: info.memory.usagePercentage,
                        icon: Icons.memory_rounded,
                        color: _getUsageColor(info.memory.usagePercentage),
                        subtitle: _formatBytes(info.memory.used),
                      ).animate().fadeIn(
                        delay: 200.ms,
                        curve: M3Curves.emphasizedDecelerate,
                      ),
                ),
                if (hasTemp) ...[
                  SizedBox(width: spacing),
                  SizedBox(
                    width: itemWidth,
                    child:
                        _TemperatureIndicator(
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
          height: 72,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: List.generate(
            3,
            (index) => Expanded(
              child: Container(
                height: 140,
                margin: EdgeInsets.only(right: index < 2 ? 16 : 0),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              size: 32,
              color: colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Failed to load system info',
            style: TextStyle(color: colorScheme.error),
          ),
        ],
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
        Icon(icon, color: colorScheme.primary, size: 22),
        const SizedBox(height: 6),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _UsageIndicator extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final String subtitle;

  const _UsageIndicator({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value / 100),
            duration: M3Durations.long2,
            curve: M3Curves.emphasized,
            builder: (context, animValue, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      value: animValue,
                      strokeWidth: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(color),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: color),
                      const SizedBox(height: 1),
                      Text(
                        '${(animValue * 100).toStringAsFixed(0)}%',
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TemperatureIndicator extends StatelessWidget {
  final double temperature;

  const _TemperatureIndicator({required this.temperature});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = _getTemperatureColor(temperature);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.thermostat_rounded, size: 14, color: color),
                const SizedBox(height: 1),
                Text(
                  '${temperature.toStringAsFixed(0)}°C',
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Temp',
            style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            _getTemperatureStatus(temperature),
            style: textTheme.bodySmall?.copyWith(color: color),
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
