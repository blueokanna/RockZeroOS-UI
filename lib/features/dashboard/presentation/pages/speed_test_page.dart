import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../../core/services/device_discovery_service.dart';

enum SpeedTestState {
  idle,
  testingPing,
  testingDownload,
  testingUpload,
  completed,
  error,
}

enum SpeedUnit {
  mbps,
  mbs,
}

class SpeedTestPage extends ConsumerStatefulWidget {
  const SpeedTestPage({super.key});

  @override
  ConsumerState<SpeedTestPage> createState() => _SpeedTestPageState();
}

class _SpeedTestPageState extends ConsumerState<SpeedTestPage>
    with TickerProviderStateMixin {
  SpeedTestState _state = SpeedTestState.idle;
  double _currentSpeed = 0;
  double _downloadSpeed = 0;
  double _uploadSpeed = 0;
  int _ping = 0;
  double _jitter = 0;
  String? _error;
  String? _authToken;
  String? _serverUrl;
  bool _configLoaded = false;
  SpeedUnit _speedUnit = SpeedUnit.mbps;

  double _testProgress = 0;
  String _testPhase = '';

  late AnimationController _pulseController;
  late AnimationController _gaugeController;
  late AnimationController _waveController;
  late AnimationController _glowController;

  bool _isCancelled = false;
  Timer? _downloadUpdateTimer;
  Timer? _uploadUpdateTimer;

  static const int _pingTestCount = 10;
  static const int _downloadTestDurationSec = 10;
  static const int _uploadTestDurationSec = 10;
  static const int _downloadChunkSizeMB = 65;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _gaugeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      const storage = FlutterSecureStorage();
      _authToken = await storage.read(key: 'access_token');
      final device = ref.read(connectedDeviceProvider);
      if (device != null) {
        _serverUrl = device.baseUrl;
      }
      if (mounted) {
        setState(() => _configLoaded = true);
      }
    } catch (e) {
      debugPrint('[SpeedTest] Config load error: $e');
    }
  }

  @override
  void dispose() {
    _isCancelled = true;
    _downloadUpdateTimer?.cancel();
    _uploadUpdateTimer?.cancel();
    _pulseController.dispose();
    _gaugeController.dispose();
    _waveController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _startSpeedTest() async {
    if (!_configLoaded) await _loadConfig();

    final device = ref.read(connectedDeviceProvider);
    if (device == null) {
      setState(() {
        _state = SpeedTestState.error;
        _error = 'Not connected to NAS device';
      });
      return;
    }

    _serverUrl = device.baseUrl;
    const storage = FlutterSecureStorage();
    _authToken = await storage.read(key: 'access_token');

    setState(() {
      _state = SpeedTestState.testingPing;
      _currentSpeed = 0;
      _downloadSpeed = 0;
      _uploadSpeed = 0;
      _ping = 0;
      _jitter = 0;
      _error = null;
      _testProgress = 0;
      _testPhase = 'Initializing...';
      _isCancelled = false;
    });

    try {
      setState(() {
        _testPhase = 'Testing latency...';
        _testProgress = 0;
      });
      await _testPing();

      if (!mounted || _isCancelled) return;

      setState(() {
        _state = SpeedTestState.testingDownload;
        _testPhase = 'Testing download speed...';
        _testProgress = 0;
      });
      await _testDownload();

      if (!mounted || _isCancelled) return;

      setState(() {
        _state = SpeedTestState.testingUpload;
        _testPhase = 'Testing upload speed...';
        _testProgress = 0;
      });
      await _testUpload();

      if (!mounted || _isCancelled) return;

      setState(() {
        _state = SpeedTestState.completed;
        _testPhase = 'Test completed';
        _testProgress = 1.0;
      });
    } catch (e) {
      if (mounted && !_isCancelled) {
        setState(() {
          _state = SpeedTestState.error;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _testPing() async {
    if (_serverUrl == null) return;

    final List<int> pings = [];
    final uri = Uri.parse('$_serverUrl/api/v1/speedtest/ping');
    final headers = <String, String>{};
    if (_authToken != null && _authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_authToken';
    }

    for (int i = 0; i < _pingTestCount; i++) {
      if (!mounted || _isCancelled) return;

      try {
        final stopwatch = Stopwatch()..start();
        final response = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 10));
        stopwatch.stop();

        if (response.statusCode == 200) {
          pings.add(stopwatch.elapsedMilliseconds);
          if (mounted && !_isCancelled) {
            final avgPing = pings.reduce((a, b) => a + b) ~/ pings.length;
            setState(() {
              _ping = avgPing;
              _testProgress = (i + 1) / _pingTestCount;
            });
          }
        }
      } catch (e) {
        debugPrint('[SpeedTest] Ping error: $e');
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (pings.isNotEmpty) {
      final avgPing = pings.reduce((a, b) => a + b) ~/ pings.length;
      double jitterSum = 0;
      for (int i = 1; i < pings.length; i++) {
        jitterSum += (pings[i] - pings[i - 1]).abs();
      }
      final jitter = pings.length > 1 ? jitterSum / (pings.length - 1) : 0.0;

      if (mounted && !_isCancelled) {
        setState(() {
          _ping = avgPing;
          _jitter = jitter;
        });
      }
    }
  }

  Future<void> _testDownload() async {
    if (_serverUrl == null) return;

    final List<double> speeds = [];
    final startTime = DateTime.now();
    final testDuration = Duration(seconds: _downloadTestDurationSec);

    final headers = <String, String>{};
    if (_authToken != null && _authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_authToken';
    }

    try {
      double currentInstantSpeed = 0;
      int totalBytesReceived = 0;
      final overallStart = Stopwatch()..start();

      _downloadUpdateTimer =
          Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!mounted || _isCancelled) {
          timer.cancel();
          return;
        }

        final elapsed = overallStart.elapsedMilliseconds / 1000;
        if (elapsed > 0 && totalBytesReceived > 0) {
          final avgSpeed = (totalBytesReceived * 8) / (elapsed * 1000000);
          if (_currentSpeed == 0) {
            currentInstantSpeed = avgSpeed;
          } else {
            const smoothFactor = 0.3;
            currentInstantSpeed = currentInstantSpeed * (1 - smoothFactor) +
                avgSpeed * smoothFactor;
          }

          setState(() {
            _currentSpeed = currentInstantSpeed;
            _downloadSpeed = currentInstantSpeed;
            final progress =
                DateTime.now().difference(startTime).inMilliseconds /
                    (testDuration.inMilliseconds);
            _testProgress = progress.clamp(0.0, 1.0);
          });
        }
      });

      while (DateTime.now().difference(startTime) < testDuration) {
        if (!mounted || _isCancelled) break;

        final chunkStart = Stopwatch()..start();
        final uri = Uri.parse(
            '$_serverUrl/api/v1/speedtest/download?size=$_downloadChunkSizeMB');

        try {
          final request = http.Request('GET', uri);
          headers.forEach((key, value) => request.headers[key] = value);

          final streamedResponse = await http.Client()
              .send(request)
              .timeout(const Duration(seconds: 60));

          if (streamedResponse.statusCode == 200) {
            int chunkBytes = 0;
            await for (final chunk in streamedResponse.stream) {
              if (_isCancelled) break;
              chunkBytes += chunk.length;
              totalBytesReceived += chunk.length;
            }

            chunkStart.stop();
            final elapsed = chunkStart.elapsedMilliseconds / 1000;
            if (elapsed > 0 && chunkBytes > 0) {
              final speedMbps = (chunkBytes * 8) / (elapsed * 1000000);
              speeds.add(speedMbps);
            }
          }
        } catch (e) {
          debugPrint('[SpeedTest] Download chunk error: $e');
        }

        await Future.delayed(const Duration(milliseconds: 100));
      }

      _downloadUpdateTimer?.cancel();
      overallStart.stop();

      if (speeds.isNotEmpty && mounted && !_isCancelled) {
        speeds.sort();
        final medianSpeed = speeds[speeds.length ~/ 2];
        setState(() {
          _downloadSpeed = medianSpeed;
          _currentSpeed = medianSpeed;
        });
      }
    } catch (e) {
      debugPrint('[SpeedTest] Download error: $e');
    } finally {
      _downloadUpdateTimer?.cancel();
    }
  }

  Future<void> _testUpload() async {
    if (_serverUrl == null) return;

    final List<double> speeds = [];
    final startTime = DateTime.now();
    final testDuration = Duration(seconds: _uploadTestDurationSec);

    final testDataSize = 5 * 1024 * 1024;
    final testData = Uint8List(testDataSize);
    final rng = math.Random();
    for (int i = 0; i < testData.length; i++) {
      testData[i] = rng.nextInt(256);
    }

    final headers = <String, String>{
      'Content-Type': 'application/octet-stream',
      'Content-Length': testData.length.toString(),
    };
    if (_authToken != null && _authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_authToken';
    }

    try {
      double currentInstantSpeed = 0;
      int totalBytesUploaded = 0;
      final overallStart = Stopwatch()..start();

      _uploadUpdateTimer =
          Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!mounted || _isCancelled) {
          timer.cancel();
          return;
        }

        final elapsed = overallStart.elapsedMilliseconds / 1000;
        if (elapsed > 0 && totalBytesUploaded > 0) {
          final avgSpeed = (totalBytesUploaded * 8) / (elapsed * 1000000);
          if (_currentSpeed == 0 || _currentSpeed < 1) {
            currentInstantSpeed = avgSpeed;
          } else {
            const smoothFactor = 0.3;
            currentInstantSpeed = currentInstantSpeed * (1 - smoothFactor) +
                avgSpeed * smoothFactor;
          }

          setState(() {
            _uploadSpeed = currentInstantSpeed;
            _currentSpeed = currentInstantSpeed;
            final progress =
                DateTime.now().difference(startTime).inMilliseconds /
                    (testDuration.inMilliseconds);
            _testProgress = progress.clamp(0.0, 1.0);
          });
        }
      });

      while (DateTime.now().difference(startTime) < testDuration) {
        if (!mounted || _isCancelled) break;

        final uploadStart = Stopwatch()..start();

        try {
          final uri = Uri.parse('$_serverUrl/api/v1/speedtest/upload');
          final response = await http
              .post(uri, headers: headers, body: testData)
              .timeout(const Duration(seconds: 60));

          uploadStart.stop();

          if (response.statusCode == 200) {
            totalBytesUploaded += testData.length;
            final elapsed = uploadStart.elapsedMilliseconds / 1000;
            if (elapsed > 0) {
              final speedMbps = (testData.length * 8) / (elapsed * 1000000);
              speeds.add(speedMbps);
            }
          }
        } catch (e) {
          debugPrint('[SpeedTest] Single upload error: $e');
        }

        await Future.delayed(const Duration(milliseconds: 100));
      }

      _uploadUpdateTimer?.cancel();
      overallStart.stop();

      if (speeds.isNotEmpty && mounted && !_isCancelled) {
        speeds.sort();
        final medianSpeed = speeds[speeds.length ~/ 2];
        setState(() {
          _uploadSpeed = medianSpeed;
          _currentSpeed = medianSpeed;
        });
      }
    } catch (e) {
      debugPrint('[SpeedTest] Upload error: $e');
    } finally {
      _uploadUpdateTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final device = ref.watch(connectedDeviceProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 简化的AppBar - 只保留单位切换器
          SliverAppBar(
            floating: true,
            snap: true,
            pinned: false,
            expandedHeight: 56,
            backgroundColor: colorScheme.surface,
            actions: [
              _buildUnitSwitcher(colorScheme),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Device info card
                _buildDeviceCard(context, device, colorScheme, textTheme),
                const SizedBox(height: 32),
                // Speed gauge
                _buildSpeedGauge(colorScheme, textTheme),
                const SizedBox(height: 24),
                // Progress indicator
                if (_state != SpeedTestState.idle &&
                    _state != SpeedTestState.completed &&
                    _state != SpeedTestState.error)
                  _buildProgressIndicator(colorScheme, textTheme),
                const SizedBox(height: 16),
                // Status text
                _buildStatusText(colorScheme, textTheme),
                const SizedBox(height: 32),
                // Results list
                if (_state == SpeedTestState.completed ||
                    _state == SpeedTestState.testingUpload ||
                    _downloadSpeed > 0)
                  _buildResultsGrid(colorScheme, textTheme),
                const SizedBox(height: 32),
                // Start button
                _buildStartButton(colorScheme, device != null),
                // Error info
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _buildErrorCard(colorScheme, textTheme),
                ],
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitSwitcher(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SegmentedButton<SpeedUnit>(
        segments: const [
          ButtonSegment(value: SpeedUnit.mbps, label: Text('Mbps')),
          ButtonSegment(value: SpeedUnit.mbs, label: Text('MB/s')),
        ],
        selected: {_speedUnit},
        onSelectionChanged: (Set<SpeedUnit> selection) {
          setState(() => _speedUnit = selection.first);
        },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context, dynamic device,
      ColorScheme colorScheme, TextTheme textTheme) {
    if (device != null) {
      return Card(
        elevation: 0,
        color: colorScheme.primaryContainer.withOpacity(0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.dns_rounded,
                    color: colorScheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      device.baseUrl,
                      style: textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.tertiary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle,
                        size: 16, color: colorScheme.tertiary),
                    const SizedBox(width: 4),
                    Text('Connected',
                        style: textTheme.labelSmall
                            ?.copyWith(color: colorScheme.tertiary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: colorScheme.errorContainer.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.warning_rounded, color: colorScheme.error, size: 28),
            const SizedBox(width: 16),
            Text('NAS Not Connected',
                style:
                    textTheme.titleMedium?.copyWith(color: colorScheme.error)),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      children: [
        Container(
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: colorScheme.surfaceContainerHighest,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0, end: _testProgress),
              builder: (context, value, child) {
                return Stack(
                  children: [
                    FractionallySizedBox(
                      widthFactor: value,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              colorScheme.primary,
                              colorScheme.tertiary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    // Shimmer effect
                    if (value > 0)
                      AnimatedBuilder(
                        animation: _waveController,
                        builder: (context, child) {
                          return Positioned(
                            left: value *
                                    MediaQuery.of(context).size.width *
                                    0.8 -
                                40 +
                                _waveController.value * 80,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: 40,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0),
                                    Colors.white.withOpacity(0.3),
                                    Colors.white.withOpacity(0),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _testPhase,
            key: ValueKey(_testPhase),
            style: textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedGauge(ColorScheme colorScheme, TextTheme textTheme) {
    final isActive = _state != SpeedTestState.idle &&
        _state != SpeedTestState.completed &&
        _state != SpeedTestState.error;

    final displaySpeed = _convertSpeed(_currentSpeed);
    // 最大速度: 10000 Mbps 或 1250 MB/s
    final maxSpeed = _speedUnit == SpeedUnit.mbps ? 10000.0 : 1250.0;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: displaySpeed),
      builder: (context, animatedSpeed, child) {
        return Center(
          child: SizedBox(
            width: 320,
            height: 320,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer dynamic glow
                if (isActive)
                  AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, child) {
                      return Container(
                        width: 300 + _glowController.value * 30,
                        height: 300 + _glowController.value * 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              _getSpeedColor(animatedSpeed).withOpacity(
                                  0.2 - _glowController.value * 0.15),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                // Main circular background
                Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colorScheme.surfaceContainerHighest,
                        colorScheme.surfaceContainer,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withOpacity(0.1),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: _getSpeedColor(animatedSpeed).withOpacity(0.15),
                        blurRadius: 20,
                        spreadRadius: -5,
                      ),
                    ],
                  ),
                ),
                // Progress ring with scale markings
                CustomPaint(
                  size: const Size(260, 260),
                  painter: _SpeedGaugePainter(
                    progress: (animatedSpeed / maxSpeed).clamp(0, 1),
                    color: _getSpeedColor(animatedSpeed),
                    backgroundColor: colorScheme.surfaceContainerHigh,
                    isActive: isActive,
                    maxSpeed: maxSpeed,
                    speedUnit: _speedUnit,
                    textColor: colorScheme.onSurfaceVariant,
                  ),
                ),
                // Inner pulse ring
                if (isActive)
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        width: 180 + _pulseController.value * 15,
                        height: 180 + _pulseController.value * 15,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _getSpeedColor(animatedSpeed).withOpacity(
                                0.25 - _pulseController.value * 0.2),
                            width: 2,
                          ),
                        ),
                      );
                    },
                  ),
                // Speed value
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [
                          _getSpeedColor(animatedSpeed),
                          _getSpeedColor(animatedSpeed).withOpacity(0.7),
                        ],
                      ).createShader(bounds),
                      child: Text(
                        animatedSpeed < 100
                            ? animatedSpeed.toStringAsFixed(1)
                            : animatedSpeed.toStringAsFixed(0),
                        style: textTheme.displayLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -3,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getSpeedColor(animatedSpeed).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _getSpeedUnitString(),
                        style: textTheme.titleMedium?.copyWith(
                          color: _getSpeedColor(animatedSpeed),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusText(ColorScheme colorScheme, TextTheme textTheme) {
    String statusText;
    IconData statusIcon;
    Color statusColor;

    switch (_state) {
      case SpeedTestState.idle:
        statusText = 'Tap to test NAS connection speed';
        statusIcon = Icons.play_arrow_rounded;
        statusColor = colorScheme.primary;
        break;
      case SpeedTestState.testingPing:
        statusText = 'Testing latency...';
        statusIcon = Icons.network_ping_rounded;
        statusColor = colorScheme.tertiary;
        break;
      case SpeedTestState.testingDownload:
        statusText = 'Testing download speed...';
        statusIcon = Icons.download_rounded;
        statusColor = Colors.green;
        break;
      case SpeedTestState.testingUpload:
        statusText = 'Testing upload speed...';
        statusIcon = Icons.upload_rounded;
        statusColor = Colors.blue;
        break;
      case SpeedTestState.completed:
        statusText = 'Test completed';
        statusIcon = Icons.check_circle_rounded;
        statusColor = colorScheme.tertiary;
        break;
      case SpeedTestState.error:
        statusText = 'Test failed';
        statusIcon = Icons.error_rounded;
        statusColor = colorScheme.error;
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(_state),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(statusIcon, color: statusColor, size: 24),
            const SizedBox(width: 12),
            Text(
              statusText,
              style: textTheme.titleMedium?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsGrid(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ResultCard(
                icon: Icons.download_rounded,
                label: 'Download',
                value: '${_convertSpeed(_downloadSpeed).toStringAsFixed(1)}',
                unit: _getSpeedUnitString(),
                color: Colors.green,
                delay: 0,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _ResultCard(
                icon: Icons.upload_rounded,
                label: 'Upload',
                value: '${_convertSpeed(_uploadSpeed).toStringAsFixed(1)}',
                unit: _getSpeedUnitString(),
                color: Colors.blue,
                delay: 100,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ResultCard(
                icon: Icons.network_ping_rounded,
                label: 'Latency',
                value: '$_ping',
                unit: 'ms',
                color: Colors.orange,
                delay: 200,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _ResultCard(
                icon: Icons.swap_vert_rounded,
                label: 'Jitter',
                value: _jitter.toStringAsFixed(1),
                unit: 'ms',
                color: Colors.purple,
                delay: 300,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStartButton(ColorScheme colorScheme, bool enabled) {
    final isRunning = _state != SpeedTestState.idle &&
        _state != SpeedTestState.completed &&
        _state != SpeedTestState.error;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      height: 64,
      child: FilledButton(
        onPressed: (isRunning || !enabled) ? null : _startSpeedTest,
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 32),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isRunning ? Icons.hourglass_top_rounded : Icons.speed_rounded,
                size: 28),
            const SizedBox(width: 12),
            Text(
              isRunning ? 'Testing...' : 'Start Test',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      elevation: 0,
      color: colorScheme.errorContainer.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_error!,
                  style:
                      textTheme.bodyMedium?.copyWith(color: colorScheme.error)),
            ),
          ],
        ),
      ),
    );
  }

  double _convertSpeed(double speedMbps) {
    if (_speedUnit == SpeedUnit.mbs) return speedMbps / 8;
    return speedMbps;
  }

  String _getSpeedUnitString() =>
      _speedUnit == SpeedUnit.mbps ? 'Mbps' : 'MB/s';

  Color _getSpeedColor(double speed) {
    // 基于10000 Mbps最大值的颜色阈值
    final maxSpeed = _speedUnit == SpeedUnit.mbps ? 10000.0 : 1250.0;
    final percentage = speed / maxSpeed;

    if (percentage >= 0.5) return Colors.green; // >= 5000 Mbps / 625 MB/s
    if (percentage >= 0.25)
      return Colors.lightGreen; // >= 2500 Mbps / 312.5 MB/s
    if (percentage >= 0.1) return Colors.amber; // >= 1000 Mbps / 125 MB/s
    if (percentage >= 0.05) return Colors.orange; // >= 500 Mbps / 62.5 MB/s
    if (percentage >= 0.01) return Colors.deepOrange; // >= 100 Mbps / 12.5 MB/s
    return Colors.red;
  }
}

class _SpeedGaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;
  final bool isActive;
  final double maxSpeed;
  final SpeedUnit speedUnit;
  final Color textColor;

  _SpeedGaugePainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
    this.isActive = false,
    required this.maxSpeed,
    required this.speedUnit,
    required this.textColor,
  });

  // 刻度值 - Mbps: 0, 50, 100, 250, 500, 1000, 2500, 5000, 10000
  // MB/s: 0, 6.25, 12.5, 31.25, 62.5, 125, 312.5, 625, 1250
  List<double> get _scaleValues {
    if (speedUnit == SpeedUnit.mbps) {
      return [0, 50, 100, 250, 500, 1000, 2500, 5000, 10000];
    } else {
      return [0, 6.25, 12.5, 31.25, 62.5, 125, 312.5, 625, 1250];
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;
    const startAngle = 135 * math.pi / 180;
    const sweepAngle = 270 * math.pi / 180;

    // Background track
    final bgPaint = Paint()
      ..color = backgroundColor.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Draw scale markings and labels
    _drawScaleMarkings(canvas, center, radius, startAngle, sweepAngle);

    // Progress bar
    if (progress > 0) {
      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + sweepAngle * progress,
          colors: _getGradientColors(),
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * progress,
        false,
        progressPaint,
      );

      // Endpoint glow
      if (isActive) {
        final endAngle = startAngle + sweepAngle * progress;
        final endX = center.dx + radius * math.cos(endAngle);
        final endY = center.dy + radius * math.sin(endAngle);
        final endPoint = Offset(endX, endY);

        final glowPaint = Paint()
          ..color = color.withOpacity(0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
        canvas.drawCircle(endPoint, 14, glowPaint);

        final dotPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(endPoint, 6, dotPaint);
      }
    }
  }

  void _drawScaleMarkings(Canvas canvas, Offset center, double radius,
      double startAngle, double sweepAngle) {
    final tickPaint = Paint()
      ..color = textColor.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final smallTickPaint = Paint()
      ..color = textColor.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    final scaleValues = _scaleValues;
    final outerRadius = radius + 8;
    final innerRadius = radius - 24;
    final labelRadius = radius + 28;

    for (int i = 0; i < scaleValues.length; i++) {
      final value = scaleValues[i];
      final normalizedValue = value / maxSpeed;
      final angle = startAngle + sweepAngle * normalizedValue;

      // 主刻度线
      final outerX = center.dx + outerRadius * math.cos(angle);
      final outerY = center.dy + outerRadius * math.sin(angle);
      final innerX = center.dx + innerRadius * math.cos(angle);
      final innerY = center.dy + innerRadius * math.sin(angle);

      canvas.drawLine(
        Offset(innerX, innerY),
        Offset(outerX, outerY),
        tickPaint,
      );

      // 刻度标签
      final labelX = center.dx + labelRadius * math.cos(angle);
      final labelY = center.dy + labelRadius * math.sin(angle);

      String labelText;
      if (speedUnit == SpeedUnit.mbps) {
        if (value >= 1000) {
          labelText =
              '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k';
        } else {
          labelText = value.toStringAsFixed(0);
        }
      } else {
        if (value >= 100) {
          labelText = value.toStringAsFixed(0);
        } else if (value >= 10) {
          labelText = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
        } else {
          labelText = value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
        }
      }

      textPainter.text = TextSpan(
        text: labelText,
        style: TextStyle(
          color: textColor.withOpacity(0.7),
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(labelX - textPainter.width / 2, labelY - textPainter.height / 2),
      );

      // 在主刻度之间绘制小刻度
      if (i < scaleValues.length - 1) {
        final nextValue = scaleValues[i + 1];
        final midValue = (value + nextValue) / 2;
        final midNormalized = midValue / maxSpeed;
        final midAngle = startAngle + sweepAngle * midNormalized;

        final midOuterX = center.dx + (outerRadius - 4) * math.cos(midAngle);
        final midOuterY = center.dy + (outerRadius - 4) * math.sin(midAngle);
        final midInnerX = center.dx + (innerRadius + 8) * math.cos(midAngle);
        final midInnerY = center.dy + (innerRadius + 8) * math.sin(midAngle);

        canvas.drawLine(
          Offset(midInnerX, midInnerY),
          Offset(midOuterX, midOuterY),
          smallTickPaint,
        );
      }
    }
  }

  List<Color> _getGradientColors() {
    if (progress < 0.25) return [Colors.red.shade400, Colors.orange.shade400];
    if (progress < 0.5) return [Colors.orange.shade400, Colors.amber.shade400];
    if (progress < 0.75)
      return [Colors.amber.shade400, Colors.lightGreen.shade400];
    return [Colors.lightGreen.shade400, Colors.green.shade400];
  }

  @override
  bool shouldRepaint(covariant _SpeedGaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.isActive != isActive ||
        oldDelegate.maxSpeed != maxSpeed ||
        oldDelegate.speedUnit != speedUnit;
  }
}

class _ResultCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;
  final int delay;

  const _ResultCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    this.delay = 0,
  });

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.color.withOpacity(0.08),
                    widget.color.withOpacity(0.15),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: widget.color.withOpacity(0.2), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 24),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.label,
                    style: textTheme.bodyMedium?.copyWith(
                      color: widget.color.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        widget.value,
                        style: textTheme.headlineMedium?.copyWith(
                          color: widget.color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.unit,
                        style: textTheme.bodySmall?.copyWith(
                          color: widget.color.withOpacity(0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
