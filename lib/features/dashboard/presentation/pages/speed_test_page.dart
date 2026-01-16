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

  double _testProgress = 0;
  String _testPhase = '';

  late AnimationController _pulseController;
  late AnimationController _gaugeController;

  static const int _pingTestCount = 10;
  static const int _downloadTestDurationSec = 10;
  static const int _uploadTestDurationSec = 10;
  static const int _downloadChunkSizeMB = 25;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _gaugeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      const storage = FlutterSecureStorage();
      _authToken = await storage.read(key: 'access_token');
      debugPrint(
          '[SpeedTest] Token loaded: ${_authToken != null ? "yes" : "no"}');

      final device = ref.read(connectedDeviceProvider);
      if (device != null) {
        _serverUrl = device.baseUrl;
        debugPrint('[SpeedTest] Server URL: $_serverUrl');
      }

      if (mounted) {
        setState(() {
          _configLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('[SpeedTest] Config load error: $e');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _gaugeController.dispose();
    super.dispose();
  }

  Future<void> _startSpeedTest() async {
    if (!_configLoaded) {
      await _loadConfig();
    }

    final device = ref.read(connectedDeviceProvider);
    if (device == null) {
      setState(() {
        _state = SpeedTestState.error;
        _error = '未连接到 NAS 设备';
      });
      return;
    }

    _serverUrl = device.baseUrl;

    const storage = FlutterSecureStorage();
    _authToken = await storage.read(key: 'access_token');

    debugPrint('[SpeedTest] Starting test with server: $_serverUrl');

    setState(() {
      _state = SpeedTestState.testingPing;
      _currentSpeed = 0;
      _downloadSpeed = 0;
      _uploadSpeed = 0;
      _ping = 0;
      _jitter = 0;
      _error = null;
      _testProgress = 0;
      _testPhase = '初始化...';
    });

    try {
      setState(() {
        _testPhase = '测试延迟...';
        _testProgress = 0;
      });
      await _testPing();

      if (!mounted) return;

      setState(() {
        _state = SpeedTestState.testingDownload;
        _testPhase = '测试下载速度...';
        _testProgress = 0;
      });
      await _testDownload();

      if (!mounted) return;

      setState(() {
        _state = SpeedTestState.testingUpload;
        _testPhase = '测试上传速度...';
        _testProgress = 0;
      });
      await _testUpload();

      if (!mounted) return;

      setState(() {
        _state = SpeedTestState.completed;
        _testPhase = '测试完成';
        _testProgress = 1.0;
      });
    } catch (e) {
      debugPrint('[SpeedTest] Error: $e');
      if (mounted) {
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
      if (!mounted) return;

      try {
        final stopwatch = Stopwatch()..start();
        final response = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 10));
        stopwatch.stop();

        if (response.statusCode == 200) {
          pings.add(stopwatch.elapsedMilliseconds);

          if (mounted) {
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

      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (pings.isNotEmpty) {
      final avgPing = pings.reduce((a, b) => a + b) ~/ pings.length;
      double jitterSum = 0;
      for (int i = 1; i < pings.length; i++) {
        jitterSum += (pings[i] - pings[i - 1]).abs();
      }
      final jitter = pings.length > 1 ? jitterSum / (pings.length - 1) : 0.0;

      if (mounted) {
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
      final overallStart = Stopwatch()..start();

      while (DateTime.now().difference(startTime) < testDuration) {
        if (!mounted) return;

        final chunkStart = Stopwatch()..start();

        final uri = Uri.parse(
            '$_serverUrl/api/v1/speedtest/download?size=$_downloadChunkSizeMB');

        try {
          final request = http.Request('GET', uri);
          headers.forEach((key, value) {
            request.headers[key] = value;
          });

          final streamedResponse = await http.Client()
              .send(request)
              .timeout(const Duration(seconds: 60));

          if (streamedResponse.statusCode == 200) {
            int bytesReceived = 0;

            await for (final chunk in streamedResponse.stream) {
              bytesReceived += chunk.length;

              final elapsed = chunkStart.elapsedMilliseconds / 1000;
              if (elapsed > 0.1 && mounted) {
                final instantSpeed = (bytesReceived * 8) / (elapsed * 1000000);
                setState(() {
                  _currentSpeed = instantSpeed;
                });
              }
            }

            chunkStart.stop();
            final elapsed = chunkStart.elapsedMilliseconds / 1000;

            if (elapsed > 0 && bytesReceived > 0) {
              final speedMbps = (bytesReceived * 8) / (elapsed * 1000000);
              speeds.add(speedMbps);

              if (mounted) {
                final recentSpeeds = speeds.length > 3
                    ? speeds.sublist(speeds.length - 3)
                    : speeds;
                final avgSpeed =
                    recentSpeeds.reduce((a, b) => a + b) / recentSpeeds.length;

                final progress =
                    DateTime.now().difference(startTime).inMilliseconds /
                        (testDuration.inMilliseconds);

                setState(() {
                  _currentSpeed = avgSpeed;
                  _downloadSpeed = avgSpeed;
                  _testProgress = progress.clamp(0.0, 1.0);
                });
              }
            }
          }
        } catch (e) {
          debugPrint('[SpeedTest] Download chunk error: $e');
        }
      }

      overallStart.stop();

      if (speeds.isNotEmpty && mounted) {
        speeds.sort();
        final trimCount = (speeds.length * 0.1).round();
        final trimmedSpeeds = speeds.length > trimCount * 2
            ? speeds.sublist(trimCount, speeds.length - trimCount)
            : speeds;

        final avgSpeed =
            trimmedSpeeds.reduce((a, b) => a + b) / trimmedSpeeds.length;

        setState(() {
          _downloadSpeed = avgSpeed;
          _currentSpeed = avgSpeed;
        });
      }
    } catch (e) {
      debugPrint('[SpeedTest] Download error: $e');
      if (speeds.isNotEmpty && mounted) {
        final avgSpeed = speeds.reduce((a, b) => a + b) / speeds.length;
        setState(() {
          _downloadSpeed = avgSpeed;
          _currentSpeed = avgSpeed;
        });
      }
    }
  }

  Future<void> _testUpload() async {
    if (_serverUrl == null) return;

    final List<double> speeds = [];
    final startTime = DateTime.now();
    final testDuration = Duration(seconds: _uploadTestDurationSec);

    final testDataSize = 5 * 1024 * 1024; // 5MB
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
      final overallStart = Stopwatch()..start();

      while (DateTime.now().difference(startTime) < testDuration) {
        if (!mounted) return;

        final uploadStart = Stopwatch()..start();

        try {
          final uri = Uri.parse('$_serverUrl/api/v1/speedtest/upload');
          final response = await http
              .post(uri, headers: headers, body: testData)
              .timeout(const Duration(seconds: 60));

          uploadStart.stop();

          if (response.statusCode == 200) {
            final elapsed = uploadStart.elapsedMilliseconds / 1000;

            if (elapsed > 0) {
              final speedMbps = (testData.length * 8) / (elapsed * 1000000);
              speeds.add(speedMbps);

              if (mounted) {
                final recentSpeeds = speeds.length > 3
                    ? speeds.sublist(speeds.length - 3)
                    : speeds;
                final avgSpeed =
                    recentSpeeds.reduce((a, b) => a + b) / recentSpeeds.length;

                final progress =
                    DateTime.now().difference(startTime).inMilliseconds /
                        (testDuration.inMilliseconds);

                setState(() {
                  _uploadSpeed = avgSpeed;
                  _currentSpeed = avgSpeed;
                  _testProgress = progress.clamp(0.0, 1.0);
                });
              }
            }
          }
        } catch (e) {
          debugPrint('[SpeedTest] Single upload error: $e');
        }

        await Future.delayed(const Duration(milliseconds: 100));
      }

      overallStart.stop();

      if (speeds.isNotEmpty && mounted) {
        speeds.sort();
        final trimCount = (speeds.length * 0.1).round();
        final trimmedSpeeds = speeds.length > trimCount * 2
            ? speeds.sublist(trimCount, speeds.length - trimCount)
            : speeds;

        final avgSpeed =
            trimmedSpeeds.reduce((a, b) => a + b) / trimmedSpeeds.length;

        setState(() {
          _uploadSpeed = avgSpeed;
          _currentSpeed = avgSpeed;
        });
      }
    } catch (e) {
      debugPrint('[SpeedTest] Upload error: $e');
      if (speeds.isNotEmpty && mounted) {
        final avgSpeed = speeds.reduce((a, b) => a + b) / speeds.length;
        setState(() {
          _uploadSpeed = avgSpeed;
          _currentSpeed = avgSpeed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final device = ref.watch(connectedDeviceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('网速测试'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (device != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.dns_rounded, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '测试目标: ${device.name}',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            device.baseUrl,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_rounded, color: colorScheme.error),
                    const SizedBox(width: 12),
                    Text(
                      '未连接 NAS',
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 32),
            _buildSpeedGauge(colorScheme, textTheme),
            const SizedBox(height: 16),
            if (_state != SpeedTestState.idle &&
                _state != SpeedTestState.completed &&
                _state != SpeedTestState.error)
              _buildProgressIndicator(colorScheme, textTheme),
            const SizedBox(height: 8),
            _buildStatusText(colorScheme, textTheme),
            const SizedBox(height: 32),
            if (_state == SpeedTestState.completed ||
                _state == SpeedTestState.testingUpload ||
                _downloadSpeed > 0)
              _buildResultsList(colorScheme, textTheme),
            const SizedBox(height: 32),
            _buildStartButton(colorScheme, device != null),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _testProgress,
            minHeight: 6,
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(colorScheme.primary),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _testPhase,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedGauge(ColorScheme colorScheme, TextTheme textTheme) {
    final isActive = _state != SpeedTestState.idle &&
        _state != SpeedTestState.completed &&
        _state != SpeedTestState.error;

    final maxSpeed = _currentSpeed > 500
        ? 1000.0
        : _currentSpeed > 100
            ? 500.0
            : 200.0;

    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surfaceContainerHighest,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),
          CustomPaint(
            size: const Size(220, 220),
            painter: _SpeedGaugePainter(
              progress: (_currentSpeed / maxSpeed).clamp(0, 1),
              color: _getSpeedColor(_currentSpeed),
              backgroundColor: colorScheme.surfaceContainerHigh,
            ),
          ),
          if (isActive)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 150 + _pulseController.value * 15,
                  height: 150 + _pulseController.value * 15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.primary.withValues(
                        alpha: 0.3 - _pulseController.value * 0.2,
                      ),
                      width: 2,
                    ),
                  ),
                );
              },
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _currentSpeed.toStringAsFixed(1),
                style: textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _getSpeedColor(_currentSpeed),
                ),
              ),
              Text(
                'Mbps',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusText(ColorScheme colorScheme, TextTheme textTheme) {
    String statusText;
    IconData statusIcon;

    switch (_state) {
      case SpeedTestState.idle:
        statusText = '点击开始测试 NAS 连接速度';
        statusIcon = Icons.play_arrow_rounded;
        break;
      case SpeedTestState.testingPing:
        statusText = '正在测试延迟...';
        statusIcon = Icons.network_ping_rounded;
        break;
      case SpeedTestState.testingDownload:
        statusText = '正在测试下载速度...';
        statusIcon = Icons.download_rounded;
        break;
      case SpeedTestState.testingUpload:
        statusText = '正在测试上传速度...';
        statusIcon = Icons.upload_rounded;
        break;
      case SpeedTestState.completed:
        statusText = '测试完成';
        statusIcon = Icons.check_circle_rounded;
        break;
      case SpeedTestState.error:
        statusText = '测试失败';
        statusIcon = Icons.error_rounded;
        break;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          statusIcon,
          color: _state == SpeedTestState.error
              ? colorScheme.error
              : colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          statusText,
          style: textTheme.titleMedium?.copyWith(
            color: _state == SpeedTestState.error
                ? colorScheme.error
                : colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildResultsList(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      children: [
        _ResultRow(
          icon: Icons.download_rounded,
          label: '下载',
          value: '${_downloadSpeed.toStringAsFixed(1)} Mbps',
          color: Colors.green,
        ),
        const SizedBox(height: 12),
        _ResultRow(
          icon: Icons.upload_rounded,
          label: '上传',
          value: '${_uploadSpeed.toStringAsFixed(1)} Mbps',
          color: Colors.blue,
        ),
        const SizedBox(height: 12),
        _ResultRow(
          icon: Icons.network_ping_rounded,
          label: '延迟',
          value: '$_ping ms',
          color: Colors.orange,
        ),
        if (_jitter > 0) ...[
          const SizedBox(height: 12),
          _ResultRow(
            icon: Icons.swap_vert_rounded,
            label: '抖动',
            value: '${_jitter.toStringAsFixed(1)} ms',
            color: Colors.purple,
          ),
        ],
      ],
    );
  }

  Widget _buildStartButton(ColorScheme colorScheme, bool enabled) {
    final isRunning = _state != SpeedTestState.idle &&
        _state != SpeedTestState.completed &&
        _state != SpeedTestState.error;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: (isRunning || !enabled) ? null : _startSpeedTest,
        icon:
            Icon(isRunning ? Icons.hourglass_top_rounded : Icons.speed_rounded),
        label: Text(isRunning ? '测试中...' : '开始测试'),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Color _getSpeedColor(double speed) {
    if (speed >= 100) return Colors.green;
    if (speed >= 50) return Colors.lightGreen;
    if (speed >= 20) return Colors.orange;
    if (speed >= 5) return Colors.deepOrange;
    return Colors.red;
  }
}

class _SpeedGaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  _SpeedGaugePainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const startAngle = 135 * math.pi / 180;
    const sweepAngle = 270 * math.pi / 180;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    final progressPaint = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: const [
          Colors.red,
          Colors.orange,
          Colors.yellow,
          Colors.lightGreen,
          Colors.green,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedGaugePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _ResultRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ResultRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
