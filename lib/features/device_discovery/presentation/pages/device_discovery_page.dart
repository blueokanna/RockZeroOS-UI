import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/device_discovery_service.dart';

class DeviceDiscoveryPage extends ConsumerStatefulWidget {
  const DeviceDiscoveryPage({super.key});

  @override
  ConsumerState<DeviceDiscoveryPage> createState() =>
      _DeviceDiscoveryPageState();
}

class _DeviceDiscoveryPageState extends ConsumerState<DeviceDiscoveryPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final _manualIpController = TextEditingController();
  bool _showManualInput = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _manualIpController.dispose();
    super.dispose();
  }

  Future<void> _connectToDevice(DiscoveredDevice device) async {
    final service = ref.read(deviceDiscoveryServiceProvider);

    // Show connecting dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Connecting to ${device.ip}...'),
          ],
        ),
      ),
    );

    final success = await service.testConnection(device);

    if (mounted) {
      Navigator.of(context).pop(); // Close dialog

      if (success) {
        ref.read(connectedDeviceProvider.notifier).state = device;
        context.go('/login');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to ${device.ip}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _connectManually() async {
    final ip = _manualIpController.text.trim();
    if (ip.isEmpty) return;

    final device = DiscoveredDevice(
      id: ip,
      name: 'RockZero @ $ip',
      ip: ip,
      port: 8443,
      version: 'unknown',
      isSecure: true,
      discoveredAt: DateTime.now(),
    );

    await _connectToDevice(device);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final discoveryState = ref.watch(deviceDiscoveryStateProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Logo
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primaryContainer,
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withValues(
                                alpha: 0.3 * (1 - _pulseController.value),
                              ),
                              blurRadius: 30 * _pulseController.value,
                              spreadRadius: 10 * _pulseController.value,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.wifi_find,
                          size: 56,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      );
                    },
                  ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
                  const SizedBox(height: 32),

                  // Title
                  Text(
                    'Discover RockZero Devices',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 200.ms),
                  const SizedBox(height: 8),
                  Text(
                    'Scanning your local network for RockZero OS devices',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 300.ms),

                  if (discoveryState.localIp != null) ...[
                    const SizedBox(height: 8),
                    Chip(
                      avatar: const Icon(Icons.computer, size: 18),
                      label: Text('Your IP: ${discoveryState.localIp}'),
                    ).animate().fadeIn(delay: 400.ms),
                  ],

                  const SizedBox(height: 32),

                  // Scanning indicator
                  if (discoveryState.isScanning)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Scanning...',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ).animate().fadeIn(),

                  const SizedBox(height: 16),

                  // Device List
                  if (discoveryState.devices.isNotEmpty) ...[
                    Text(
                      'Found ${discoveryState.devices.length} device(s)',
                      style: textTheme.titleSmall,
                    ).animate().fadeIn(),
                    const SizedBox(height: 16),
                    ...discoveryState.devices.asMap().entries.map((entry) {
                      final index = entry.key;
                      final device = entry.value;
                      return _DeviceCard(
                            device: device,
                            onTap: () => _connectToDevice(device),
                          )
                          .animate(delay: (100 * index).ms)
                          .fadeIn()
                          .slideY(begin: 0.1);
                    }),
                  ] else if (!discoveryState.isScanning) ...[
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No devices found',
                            style: textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Make sure your RockZero device is powered on and connected to the same network',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 500.ms),
                  ],

                  const SizedBox(height: 24),

                  // Manual Connection
                  if (_showManualInput) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Manual Connection',
                              style: textTheme.titleSmall,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _manualIpController,
                              decoration: const InputDecoration(
                                labelText: 'IP Address',
                                hintText: '192.168.1.100',
                                prefixIcon: Icon(Icons.lan),
                              ),
                              keyboardType: TextInputType.number,
                              onSubmitted: (_) => _connectManually(),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _connectManually,
                              child: const Text('Connect'),
                            ),
                          ],
                        ),
                      ),
                    ).animate().fadeIn().slideY(begin: 0.1),
                  ] else ...[
                    TextButton.icon(
                      onPressed: () => setState(() => _showManualInput = true),
                      icon: const Icon(Icons.edit),
                      label: const Text('Enter IP manually'),
                    ).animate().fadeIn(delay: 600.ms),
                  ],

                  const SizedBox(height: 16),

                  // Refresh Button
                  OutlinedButton.icon(
                    onPressed: discoveryState.isScanning
                        ? null
                        : () => ref
                              .read(deviceDiscoveryServiceProvider)
                              .scanNetwork(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Scan Again'),
                  ).animate().fadeIn(delay: 700.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final DiscoveredDevice device;
  final VoidCallback onTap;

  const _DeviceCard({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.dns, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          device.isSecure ? Icons.lock : Icons.lock_open,
                          size: 14,
                          color: device.isSecure ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${device.ip}:${device.port}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'v${device.version}',
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
