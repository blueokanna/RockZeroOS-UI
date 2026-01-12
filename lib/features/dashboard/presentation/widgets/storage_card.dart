import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';

class StorageCard extends StatelessWidget {
  final AsyncValue<StorageInfo?> storageInfo;

  const StorageCard({super.key, required this.storageInfo});

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
                Icon(Icons.storage, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Storage',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            storageInfo.when(
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

  Widget _buildContent(BuildContext context, StorageInfo info) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final usageColor = _getUsageColor(info.usagePercentage);

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: CircularProgressIndicator(
                value: info.usagePercentage / 100,
                strokeWidth: 12,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(usageColor),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${info.usagePercentage.toStringAsFixed(1)}%',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: usageColor,
                  ),
                ),
                Text(
                  'Used',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        _StorageRow(
          label: 'Used',
          value: _formatBytes(info.usedSpace),
          color: usageColor,
        ),
        const SizedBox(height: 8),
        _StorageRow(
          label: 'Available',
          value: _formatBytes(info.availableSpace),
          color: Colors.green,
        ),
        const SizedBox(height: 8),
        _StorageRow(
          label: 'Total',
          value: _formatBytes(info.totalSpace),
          color: colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey.withValues(alpha: 0.1),
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
            'Failed to load storage info',
            style: TextStyle(color: colorScheme.error),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
    } else if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
  }

  Color _getUsageColor(double usage) {
    if (usage >= 90) return Colors.red;
    if (usage >= 70) return Colors.orange;
    if (usage >= 50) return Colors.yellow.shade700;
    return Colors.green;
  }
}

class _StorageRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StorageRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: textTheme.bodyMedium),
          ],
        ),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
