import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/device_discovery_service.dart';
import '../../../../core/widgets/wallpaper_background.dart';

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
  final _portController = TextEditingController(text: '8080');
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
    _portController.dispose();
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
        ref.read(connectedDeviceProvider.notifier).setDevice(device);
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
    final input = _manualIpController.text.trim();
    if (input.isEmpty) return;

    // 解析用户输入
    String ip;
    int? port;

    // 获取端口输入
    final portInput = _portController.text.trim();
    final customPort = int.tryParse(portInput);

    if (input.startsWith('http://') || input.startsWith('https://')) {
      // 完整URL格式 - 直接使用指定的协议
      try {
        final uri = Uri.parse(input);
        ip = uri.host;
        port = uri.port != 0 ? uri.port : (customPort ?? 8080);
        final isSecure = uri.scheme == 'https';

        final device = DiscoveredDevice(
          id: ip,
          name: 'RockZero @ $ip',
          ip: ip,
          port: port,
          version: 'unknown',
          isSecure: isSecure,
          discoveredAt: DateTime.now(),
        );
        await _connectToDevice(device);
        return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid URL format'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    } else if (input.contains(':')) {
      // IP:端口格式
      final parts = input.split(':');
      ip = parts[0];
      port = int.tryParse(parts[1]) ?? customPort;
    } else {
      // 纯IP格式 - 使用端口输入框的值
      ip = input;
      port = customPort;
    }

    // 显示连接中对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Auto-detecting $ip:${port ?? 8080}...'),
            const SizedBox(height: 8),
            Text(
              'Trying HTTP and HTTPS...',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );

    // 自动探测 HTTP/HTTPS
    final service = ref.read(deviceDiscoveryServiceProvider);
    final device = await service.autoDetectDevice(ip, port: port);

    if (mounted) {
      Navigator.of(context).pop(); // 关闭对话框

      if (device != null) {
        ref.read(connectedDeviceProvider.notifier).setDevice(device);
        context.go('/login');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to connect to $ip. Make sure the server is running.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final discoveryState = ref.watch(deviceDiscoveryStateProvider);
    final textTheme = Theme.of(context).textTheme;

    return WallpaperBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Image.asset(
                              'assets/images/RockZero.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.wifi_find,
                                  size: 56,
                                  color: colorScheme.onPrimaryContainer,
                                );
                              },
                            ),
                          ),
                        );
                      },
                    )
                        .animate()
                        .scale(duration: 400.ms, curve: Curves.elasticOut),
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
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: _manualIpController,
                                      decoration: const InputDecoration(
                                        labelText: 'IP Address',
                                        hintText: '192.168.1.100',
                                        prefixIcon: Icon(Icons.lan),
                                      ),
                                      keyboardType: TextInputType.url,
                                      onSubmitted: (_) => _connectManually(),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 1,
                                    child: TextField(
                                      controller: _portController,
                                      decoration: const InputDecoration(
                                        labelText: 'Port',
                                        hintText: '8080',
                                      ),
                                      keyboardType: TextInputType.number,
                                      onSubmitted: (_) => _connectManually(),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Auto-detects HTTP/HTTPS protocol',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
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
                        onPressed: () =>
                            setState(() => _showManualInput = true),
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
                clipBehavior: Clip.antiAlias,
                child: _buildDeviceIcon(colorScheme),
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

  Widget _buildDeviceIcon(ColorScheme colorScheme) {
    // 优先使用服务端提供的图标URL
    if (device.fullIconUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          device.fullIconUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // 网络图标加载失败，使用本地图标
            return _buildLocalIcon(colorScheme);
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
        ),
      );
    }

    // 使用本地图标
    return _buildLocalIcon(colorScheme);
  }

  Widget _buildLocalIcon(ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Image.asset(
          'assets/images/RockZero.png',
          width: 40,
          height: 40,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // 本地图标也加载失败，使用默认图标
            return Icon(Icons.dns,
                color: colorScheme.onPrimaryContainer, size: 32);
          },
        ),
      ),
    );
  }
}
