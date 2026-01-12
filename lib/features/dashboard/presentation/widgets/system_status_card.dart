import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';

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
                Icon(Icons.monitor_heart, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'System Status',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            hardwareInfo.when(
              data: (info) {
                if (info == null) {
                  return _buildErrorState(context);
                }
                return _buildContent(context, info);
              },
              loading: () => _buildLoadingState(),
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
        Row(
          children: [
            Expanded(
              child: _InfoTile(
                icon: Icons.computer,
                label: 'Hostname',
                value: info.system.hostname,
              ),
            ),
            Expanded(
              child: _InfoTile(
                icon: Icons.memory,
                label: 'Architecture',
                value: info.system.architecture,
              ),
            ),
            Expanded(
              child: _InfoTile(
                icon: Icons.schedule,
                label: 'Uptime',
                value: _formatUptime(info.system.uptime),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Divider(color: colorScheme.outlineVariant),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _UsageIndicator(
                label: 'CPU',
                value: info.cpu.usage,
                icon: Icons.speed,
                color: _getUsageColor(info.cpu.usage),
                subtitle: '${info.cpu.cores} cores',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _UsageIndicator(
                label: 'Memory',
                value: info.memory.usagePercentage,
                icon: Icons.memory,
                color: _getUsageColor(info.memory.usagePercentage),
                subtitle: _formatBytes(info.memory.used),
              ),
            ),
            if (info.cpu.temperature != null) ...[
              const SizedBox(width: 16),
              Expanded(
                child: _TemperatureIndicator(
                  temperature: info.cpu.temperature!,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Column(
      children: [
        Row(
          children: List.generate(
            3,
            (index) => Expanded(
              child: Container(
                height: 60,
                margin: EdgeInsets.only(right: index < 2 ? 8 : 0),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const LinearProgressIndicator(),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 48, color: colorScheme.error),
          const SizedBox(height: 8),
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
    if (usage >= 50) return Colors.yellow.shade700;
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
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
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

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                value: value / 100,
                strokeWidth: 8,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: color),
                Text(
                  '${value.toStringAsFixed(0)}%',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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

    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.thermostat, size: 20, color: color),
              Text(
                '${temperature.toStringAsFixed(0)}°C',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Temperature',
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        Text(
          _getTemperatureStatus(temperature),
          style: textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }

  Color _getTemperatureColor(double temp) {
    if (temp >= 80) return Colors.red;
    if (temp >= 60) return Colors.orange;
    if (temp >= 40) return Colors.yellow.shade700;
    return Colors.green;
  }

  String _getTemperatureStatus(double temp) {
    if (temp >= 80) return 'Critical';
    if (temp >= 60) return 'Warm';
    if (temp >= 40) return 'Normal';
    return 'Cool';
  }
}
