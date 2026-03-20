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
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, colorScheme.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
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
                      Text('System Status',
                          style: textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Real-time monitoring',
                          style: textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            hardwareInfo.when(
              data: (info) => info == null
                  ? _buildErrorState(context)
                  : _buildContent(context, info),
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
    final hasTemp = info.cpu.temperature != null;

    return Column(
      children: [
        _buildNoDiskModeRow(context, info)
            .animate()
            .fadeIn(delay: 80.ms, curve: M3Curves.emphasizedDecelerate),
        const SizedBox(height: 12),

        // System info row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                  child: _InfoTile(
                      icon: Icons.computer_rounded,
                      label: 'Hostname',
                      value: info.system.hostname)),
              Container(
                  width: 1,
                  height: 40,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              Expanded(
                  child: _InfoTile(
                      icon: Icons.memory_rounded,
                      label: 'Arch',
                      value: info.system.architecture)),
              Container(
                  width: 1,
                  height: 40,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              Expanded(
                  child: _InfoTile(
                      icon: Icons.schedule_rounded,
                      label: 'Uptime',
                      value: _formatUptime(info.system.uptime))),
            ],
          ),
        ).animate().fadeIn(delay: 100.ms, curve: M3Curves.emphasizedDecelerate),
        const SizedBox(height: 16),

        // CPU row
        _buildStatRow(
          context,
          icon: Icons.speed_rounded,
          label: 'CPU',
          value: info.cpu.usage,
          subtitle: _buildCpuSubtitle(info.cpu),
          color: _getUsageColor(info.cpu.usage),
        ).animate().fadeIn(delay: 150.ms, curve: M3Curves.emphasizedDecelerate),
        const SizedBox(height: 12),

        // Memory row
        _buildStatRow(
          context,
          icon: Icons.memory_rounded,
          label: 'Memory',
          value: info.memory.usagePercentage,
          subtitle:
              '${_formatBytes(info.memory.used)} / ${_formatBytes(info.memory.total)}',
          color: _getUsageColor(info.memory.usagePercentage),
        ).animate().fadeIn(delay: 200.ms, curve: M3Curves.emphasizedDecelerate),

        // Temperature row
        if (hasTemp) ...[
          const SizedBox(height: 12),
          _buildTempRow(context, info.cpu.temperature!)
              .animate()
              .fadeIn(delay: 250.ms, curve: M3Curves.emphasizedDecelerate),
        ],
      ],
    );
  }

  Widget _buildNoDiskModeRow(BuildContext context, HardwareInfo info) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final active = info.noDiskPlaybackModeActive;
    final sessions = info.noDiskPlaybackSessionCount;
    final statusColor = active ? colorScheme.error : colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.warning_amber_rounded : Icons.verified_rounded,
            size: 20,
            color: statusColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              active
                  ? 'No-disk playback mode ACTIVE ($sessions session${sessions == 1 ? '' : 's'})'
                  : 'No-disk playback mode inactive',
              style: textTheme.bodyMedium?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required double value,
    required String subtitle,
    required Color color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label,
                        style: textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${value.toStringAsFixed(1)}%',
                        style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold, color: color)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: value / 100,
                    minHeight: 6,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: textTheme.labelSmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTempRow(BuildContext context, double temperature) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = _getTemperatureColor(temperature);
    final status = _getTemperatureStatus(temperature);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.thermostat_rounded, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Temperature',
                        style: textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${temperature.toStringAsFixed(0)}°C',
                        style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold, color: color)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (temperature / 100).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(status,
                      style: textTheme.labelSmall?.copyWith(
                          color: color, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: CircularProgressIndicator(
            strokeWidth: 2.5, color: colorScheme.primary),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text('Failed to load', style: TextStyle(color: colorScheme.error)),
          ],
        ),
      ),
    );
  }

  String _formatUptime(int seconds) {
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    if (days > 0) {
      return '${days}d ${hours}h';
    }
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String _buildCpuSubtitle(CpuInfo cpu) {
    if (cpu.coreTypes != null && cpu.coreTypes!.isNotEmpty) {
      // 显示异构架构信息
      final coreTypesStr =
          cpu.coreTypes!.map((ct) => '${ct.count}x ${ct.coreName}').join(' + ');
      return '$coreTypesStr • ${cpu.frequency} MHz';
    }
    return '${cpu.cores} cores • ${cpu.frequency} MHz';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)}MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)}KB';
  }

  Color _getUsageColor(double usage) {
    if (usage >= 90) return Colors.red;
    if (usage >= 70) return Colors.orange;
    if (usage >= 50) return Colors.amber.shade700;
    return Colors.green;
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

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: colorScheme.primary, size: 22),
        const SizedBox(height: 6),
        Text(label,
            style: textTheme.labelSmall
                ?.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value,
            style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
