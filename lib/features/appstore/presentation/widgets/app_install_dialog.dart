import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/api_models.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/theme/app_theme.dart';

class _PortConfig {
  int containerPort;
  int hostPort;
  String protocol;

  _PortConfig({
    required this.containerPort,
    required this.hostPort,
    this.protocol = 'tcp',
  });

  PortMapping toPortMapping() => PortMapping(
        containerPort: containerPort,
        hostPort: hostPort,
        protocol: protocol,
      );
}

class _VolumeConfig {
  String containerPath;
  String hostPath;
  String mode;

  _VolumeConfig({
    required this.containerPath,
    required this.hostPath,
    this.mode = 'rw',
  });

  VolumeMapping toVolumeMapping() => VolumeMapping(
        containerPath: containerPath,
        hostPath: hostPath,
        mode: mode,
      );
}

class _EnvConfig {
  String key;
  String value;
  bool required;

  _EnvConfig({required this.key, this.value = '', this.required = false});

  EnvVar toEnvVar() => EnvVar(key: key, value: value, required: required);
}

class AppInstallDialog extends ConsumerStatefulWidget {
  final AppStoreItem app;

  const AppInstallDialog({super.key, required this.app});

  @override
  ConsumerState<AppInstallDialog> createState() => _AppInstallDialogState();
}

class _AppInstallDialogState extends ConsumerState<AppInstallDialog> {
  late List<_PortConfig> _ports;
  late List<_VolumeConfig> _volumes;
  late List<_EnvConfig> _envVars;
  String _memoryLimit = '512m';
  double _cpuLimit = 1.0;
  bool _autoStart = true;
  bool _isInstalling = false;
  String? _installError;
  double _installProgress = 0;
  String _installStatus = '';

  @override
  void initState() {
    super.initState();
    _ports = widget.app.defaultPorts
        .map(
          (p) => _PortConfig(
            containerPort: p.containerPort,
            hostPort: p.hostPort,
            protocol: p.protocol,
          ),
        )
        .toList();
    _volumes = widget.app.defaultVolumes
        .map(
          (v) => _VolumeConfig(
            containerPath: v.containerPath,
            hostPath: v.hostPath,
            mode: v.mode,
          ),
        )
        .toList();
    _envVars = widget.app.requiredEnv
        .map((e) => _EnvConfig(key: e, value: '', required: true))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenWidth > 600 ? screenWidth * 0.15 : 16,
        vertical: 24,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: screenHeight * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  _AppIcon(iconUrl: widget.app.icon, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Install ${widget.app.displayName}',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.app.dockerImage}:${widget.app.recommendedTag}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(
                  duration: M3Durations.medium2,
                  curve: M3Curves.emphasizedDecelerate,
                ),
            Flexible(
              child: _isInstalling
                  ? _buildInstallingView(colorScheme)
                  : _buildConfigView(colorScheme, textTheme),
            ),
            if (!_isInstalling)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _startInstall,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Install'),
                    ),
                  ],
                ),
              ).animate().fadeIn(
                    delay: 100.ms,
                    duration: M3Durations.medium2,
                    curve: M3Curves.emphasizedDecelerate,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigView(ColorScheme colorScheme, TextTheme textTheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.app.description).animate().fadeIn(
              duration: M3Durations.medium2,
              curve: M3Curves.emphasizedDecelerate),
          const SizedBox(height: 20),
          _buildSectionHeader(
            colorScheme,
            textTheme,
            Icons.lan_rounded,
            'Port Mappings',
          ).animate().fadeIn(
              delay: 50.ms,
              duration: M3Durations.medium2,
              curve: M3Curves.emphasizedDecelerate),
          const SizedBox(height: 8),
          ..._ports.asMap().entries.map((entry) => _buildPortRow(entry.key)
              .animate()
              .fadeIn(
                  delay: (80 + entry.key * 30).ms,
                  duration: M3Durations.medium2,
                  curve: M3Curves.emphasizedDecelerate)
              .slideX(begin: -0.02, curve: M3Curves.emphasized)),
          TextButton.icon(
            onPressed: _addPort,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Port'),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader(
            colorScheme,
            textTheme,
            Icons.folder_rounded,
            'Volume Mappings',
          ).animate().fadeIn(
              delay: 150.ms,
              duration: M3Durations.medium2,
              curve: M3Curves.emphasizedDecelerate),
          const SizedBox(height: 8),
          ..._volumes.asMap().entries.map(
                (entry) => _buildVolumeRow(entry.key)
                    .animate()
                    .fadeIn(
                        delay: (180 + entry.key * 30).ms,
                        duration: M3Durations.medium2,
                        curve: M3Curves.emphasizedDecelerate)
                    .slideX(begin: -0.02, curve: M3Curves.emphasized),
              ),
          TextButton.icon(
            onPressed: _addVolume,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Volume'),
          ),
          const SizedBox(height: 16),
          if (_envVars.isNotEmpty) ...[
            _buildSectionHeader(
              colorScheme,
              textTheme,
              Icons.settings_rounded,
              'Environment Variables',
            ).animate().fadeIn(
                delay: 250.ms,
                duration: M3Durations.medium2,
                curve: M3Curves.emphasizedDecelerate),
            const SizedBox(height: 8),
            ..._envVars.asMap().entries.map((entry) => _buildEnvRow(entry.key)
                .animate()
                .fadeIn(
                    delay: (280 + entry.key * 30).ms,
                    duration: M3Durations.medium2,
                    curve: M3Curves.emphasizedDecelerate)
                .slideX(begin: -0.02, curve: M3Curves.emphasized)),
            const SizedBox(height: 16),
          ],
          _buildSectionHeader(
            colorScheme,
            textTheme,
            Icons.memory_rounded,
            'Resource Limits',
          ).animate().fadeIn(
              delay: 350.ms,
              duration: M3Durations.medium2,
              curve: M3Curves.emphasizedDecelerate),
          const SizedBox(height: 8),
          _buildResourceLimits(colorScheme).animate().fadeIn(
              delay: 380.ms,
              duration: M3Durations.medium2,
              curve: M3Curves.emphasizedDecelerate),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            child: SwitchListTile(
              title: const Text('Auto Start'),
              subtitle: const Text('Start container after installation'),
              value: _autoStart,
              onChanged: (value) => setState(() => _autoStart = value),
            ),
          ).animate().fadeIn(
              delay: 420.ms,
              duration: M3Durations.medium2,
              curve: M3Curves.emphasizedDecelerate),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    ColorScheme colorScheme,
    TextTheme textTheme,
    IconData icon,
    String title,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildPortRow(int index) {
    final port = _ports[index];
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: port.hostPort.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Host',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      port.hostPort = int.tryParse(value) ?? port.hostPort;
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 16, color: colorScheme.primary),
                ),
                Expanded(
                  child: TextFormField(
                    initialValue: port.containerPort.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Container',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      port.containerPort =
                          int.tryParse(value) ?? port.containerPort;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: DropdownButtonFormField<String>(
                    initialValue: port.protocol,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                      DropdownMenuItem(value: 'udp', child: Text('UDP')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => port.protocol = value);
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_rounded,
                      size: 18, color: colorScheme.error),
                  onPressed: () => setState(() => _ports.removeAt(index)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeRow(int index) {
    final volume = _volumes[index];
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: volume.hostPath,
                    decoration: const InputDecoration(
                      labelText: 'Host Path',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (value) => volume.hostPath = value,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_rounded,
                      size: 18, color: colorScheme.error),
                  onPressed: () => setState(() => _volumes.removeAt(index)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.arrow_downward_rounded,
                    size: 14, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: volume.containerPath,
                    decoration: const InputDecoration(
                      labelText: 'Container Path',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (value) => volume.containerPath = value,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: DropdownButtonFormField<String>(
                    initialValue: volume.mode,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'rw', child: Text('RW')),
                      DropdownMenuItem(value: 'ro', child: Text('RO')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => volume.mode = value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnvRow(int index) {
    final env = _envVars[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: env.key,
              decoration: InputDecoration(
                labelText: 'Key',
                isDense: true,
                suffixIcon: env.required
                    ? const Icon(Icons.star, size: 12, color: Colors.red)
                    : null,
              ),
              readOnly: env.required,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: env.value,
              decoration: const InputDecoration(
                labelText: 'Value',
                isDense: true,
              ),
              onChanged: (value) => env.value = value,
            ),
          ),
          if (!env.required)
            IconButton(
              icon: const Icon(Icons.delete_rounded, size: 18),
              onPressed: () => setState(() => _envVars.removeAt(index)),
            ),
        ],
      ),
    );
  }

  Widget _buildResourceLimits(ColorScheme colorScheme) {
    return Column(
      children: [
        Row(
          children: [
            const Text('Memory Limit:'),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _memoryLimit,
                decoration: const InputDecoration(isDense: true),
                items: const [
                  DropdownMenuItem(value: '256m', child: Text('256 MB')),
                  DropdownMenuItem(value: '512m', child: Text('512 MB')),
                  DropdownMenuItem(value: '1g', child: Text('1 GB')),
                  DropdownMenuItem(value: '2g', child: Text('2 GB')),
                  DropdownMenuItem(value: '4g', child: Text('4 GB')),
                  DropdownMenuItem(value: '0', child: Text('Unlimited')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _memoryLimit = value);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('CPU Limit:'),
            const SizedBox(width: 16),
            Expanded(
              child: Slider(
                value: _cpuLimit,
                min: 0.25,
                max: 4.0,
                divisions: 15,
                label: '${_cpuLimit.toStringAsFixed(2)} cores',
                onChanged: (value) => setState(() => _cpuLimit = value),
              ),
            ),
            Text(_cpuLimit.toStringAsFixed(2)),
          ],
        ),
      ],
    );
  }

  Widget _buildInstallingView(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_installError != null) ...[
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Installation Failed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _installError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () => setState(() {
                    _isInstalling = false;
                    _installError = null;
                  }),
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ] else ...[
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                value: _installProgress > 0 ? _installProgress : null,
                strokeWidth: 6,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _installStatus.isNotEmpty
                  ? _installStatus
                  : 'Installing ${widget.app.displayName}...',
              style: const TextStyle(fontSize: 16),
            ),
            if (_installProgress > 0) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _installProgress),
              const SizedBox(height: 8),
              Text('${(_installProgress * 100).toInt()}%'),
            ],
          ],
        ],
      ),
    );
  }

  void _addPort() {
    setState(() {
      _ports.add(_PortConfig(containerPort: 8080, hostPort: 8080));
    });
  }

  void _addVolume() {
    setState(() {
      _volumes.add(
        _VolumeConfig(
          containerPath: '/data',
          hostPath: '/opt/rockzero/data/${widget.app.name}',
        ),
      );
    });
  }

  Future<void> _startInstall() async {
    for (final env in _envVars) {
      if (env.required && env.value.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please fill in required variable: ${env.key}'),
          ),
        );
        return;
      }
    }

    setState(() {
      _isInstalling = true;
      _installError = null;
      _installProgress = 0;
      _installStatus = 'Preparing installation...';
    });

    try {
      final api = ref.read(apiServiceProvider);

      setState(() {
        _installProgress = 0.1;
        _installStatus = 'Pulling Docker image...';
      });

      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _installProgress = 0.3;
        _installStatus = 'Creating container...';
      });

      await api.installApp(
        name: widget.app.name,
        dockerImage: widget.app.dockerImage,
        dockerTag: widget.app.recommendedTag,
        ports: _ports.map((p) => p.toPortMapping()).toList(),
        volumes: _volumes.map((v) => v.toVolumeMapping()).toList(),
        environment: _envVars.map((e) => e.toEnvVar()).toList(),
      );

      setState(() {
        _installProgress = 0.9;
        _installStatus = 'Starting container...';
      });

      if (_autoStart) {
        try {
          await api.startApp(widget.app.name);
        } catch (e) {
          debugPrint('Failed to auto-start container: $e');
        }
      }

      setState(() {
        _installProgress = 1.0;
        _installStatus = 'Installation complete!';
      });

      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      String errorMessage = e.toString();

      if (errorMessage.contains('port is already allocated') ||
          errorMessage.contains('address already in use')) {
        errorMessage =
            'Port conflict: One or more ports are already in use. Please change the host port mappings.';
      } else if (errorMessage.contains('no such image') ||
          errorMessage.contains('pull access denied')) {
        errorMessage =
            'Failed to pull Docker image. Please check your network connection and image name.';
      } else if (errorMessage.contains('permission denied')) {
        errorMessage =
            'Permission denied. Please check volume path permissions.';
      } else if (errorMessage.contains('Failed to start container')) {
        errorMessage =
            'Container created but failed to start. Please check the configuration and try starting it manually from the Apps page.';
      } else if (errorMessage.contains('Bad request')) {
        errorMessage =
            'Invalid configuration. Please check port mappings, volume paths, and environment variables.';
      } else if (errorMessage.contains('timeout') ||
          errorMessage.contains('Timeout')) {
        errorMessage =
            'Connection timeout. The server may be busy pulling the image. Please try again later.';
      } else if (errorMessage.contains('DioException')) {
        final match = RegExp(r'Error:\s*(.+)').firstMatch(errorMessage);
        if (match != null) {
          errorMessage = match.group(1) ?? errorMessage;
        }

        if (errorMessage.contains('null')) {
          errorMessage =
              'Server error occurred. Please check the NAS logs for details.';
        }
      }

      setState(() {
        _installError = errorMessage;
      });
    }
  }
}

class _AppIcon extends StatelessWidget {
  final String iconUrl;
  final double size;

  const _AppIcon({required this.iconUrl, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: iconUrl.isNotEmpty
          ? Image.network(
              iconUrl,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => _buildFallbackIcon(context),
            )
          : _buildFallbackIcon(context),
    );
  }

  Widget _buildFallbackIcon(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withValues(alpha: 0.8),
            colorScheme.tertiary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(Icons.apps_rounded, size: size * 0.5, color: Colors.white),
    );
  }
}
