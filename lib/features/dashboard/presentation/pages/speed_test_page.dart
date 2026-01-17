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
  mbps, // Megabits per second
  mbs, // Megabytes per second (MB/s)
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

  // 用于取消测试的标志
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
    // 停止所有测试
    _isCancelled = true;
    _downloadUpdateTimer?.cancel();
    _uploadUpdateTimer?.cancel();
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
      _isCancelled = false; // 重置取消标志
    });

    try {
      setState(() {
        _testPhase = '测试延迟...';
        _testProgress = 0;
      });
      await _testPing();

      if (!mounted || _isCancelled) return;

      setState(() {
        _state = SpeedTestState.testingDownload;
        _testPhase = '测试下载速度...';
        _testProgress = 0;
      });
      await _testDownload();

      if (!mounted || _isCancelled) return;

      setState(() {
        _state = SpeedTestState.testingUpload;
        _testPhase = '测试上传速度...';
        _testProgress = 0;
      });
      await _testUpload();

      if (!mounted || _isCancelled) return;

      setState(() {
        _state = SpeedTestState.completed;
        _testPhase = '测试完成';
        _testProgress = 1.0;
      });
    } catch (e) {
      debugPrint('[SpeedTest] Error: $e');
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
      // 使用定时器每50ms更新一次速度显示
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
          // 计算平均速度
          final avgSpeed = (totalBytesReceived * 8) / (elapsed * 1000000);

          // 使用指数移动平均来平滑速度变化
          if (_currentSpeed == 0) {
            currentInstantSpeed = avgSpeed;
          } else {
            // EMA平滑因子，值越小越平滑
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

      // 并发下载多个块以获得更准确的速度
      while (DateTime.now().difference(startTime) < testDuration) {
        if (!mounted || _isCancelled) break;

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

        // 短暂延迟避免过度请求
        await Future.delayed(const Duration(milliseconds: 100));
      }

      _downloadUpdateTimer?.cancel();
      overallStart.stop();

      if (speeds.isNotEmpty && mounted && !_isCancelled) {
        // 使用中位数而不是平均值，更准确
        speeds.sort();
        final medianSpeed = speeds[speeds.length ~/ 2];

        setState(() {
          _downloadSpeed = medianSpeed;
          _currentSpeed = medianSpeed;
        });
      }
    } catch (e) {
      debugPrint('[SpeedTest] Download error: $e');
      if (speeds.isNotEmpty && mounted && !_isCancelled) {
        final avgSpeed = speeds.reduce((a, b) => a + b) / speeds.length;
        setState(() {
          _downloadSpeed = avgSpeed;
          _currentSpeed = avgSpeed;
        });
      }
    } finally {
      _downloadUpdateTimer?.cancel();
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
      // 使用定时器每50ms更新一次速度显示
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
          // 计算平均速度
          final avgSpeed = (totalBytesUploaded * 8) / (elapsed * 1000000);

          // 使用指数移动平均来平滑速度变化
          if (_currentSpeed == 0 || _currentSpeed < 1) {
            currentInstantSpeed = avgSpeed;
          } else {
            // EMA平滑因子
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

      // 并发上传
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
      if (speeds.isNotEmpty && mounted && !_isCancelled) {
        final avgSpeed = speeds.reduce((a, b) => a + b) / speeds.length;
        setState(() {
          _uploadSpeed = avgSpeed;
          _currentSpeed = avgSpeed;
        });
      }
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
      appBar: AppBar(
        title: const Text('网速测试'),
        centerTitle: true,
        actions: [
          // 单位切换按钮
          PopupMenuButton<SpeedUnit>(
            icon: Icon(
              _speedUnit == SpeedUnit.mbps
                  ? Icons.speed_rounded
                  : Icons.storage_rounded,
            ),
            tooltip: '切换单位',
            onSelected: (unit) {
              setState(() => _speedUnit = unit);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: SpeedUnit.mbps,
                child: Row(
                  children: [
                    Icon(
                      Icons.speed_rounded,
                      color: _speedUnit == SpeedUnit.mbps
                          ? colorScheme.primary
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Mbps (兆比特/秒)',
                      style: TextStyle(
                        color: _speedUnit == SpeedUnit.mbps
                            ? colorScheme.primary
                            : null,
                        fontWeight: _speedUnit == SpeedUnit.mbps
                            ? FontWeight.bold
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: SpeedUnit.mbs,
                child: Row(
                  children: [
                    Icon(
                      Icons.storage_rounded,
                      color: _speedUnit == SpeedUnit.mbs
                          ? colorScheme.primary
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'MB/s (兆字节/秒)',
                      style: TextStyle(
                        color: _speedUnit == SpeedUnit.mbs
                            ? colorScheme.primary
                            : null,
                        fontWeight: _speedUnit == SpeedUnit.mbs
                            ? FontWeight.bold
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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
        Container(
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: colorScheme.surfaceContainerHighest,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              tween: Tween<double>(begin: 0, end: _testProgress),
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(
                    colorScheme.primary,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _testPhase,
            key: ValueKey(_testPhase),
            style: textTheme.bodyMedium?.copyWith(
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

    // 根据单位调整最大速度刻度
    final displaySpeed = _convertSpeed(_currentSpeed);
    final maxSpeed = _speedUnit == SpeedUnit.mbps
        ? (displaySpeed > 500
            ? 1000.0
            : displaySpeed > 100
                ? 500.0
                : 200.0)
        : (displaySpeed > 62.5
            ? 125.0
            : displaySpeed > 12.5
                ? 62.5
                : 25.0);

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: displaySpeed),
      builder: (context, animatedSpeed, child) {
        return SizedBox(
          width: 280,
          height: 280,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 外层光晕效果
              if (isActive)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 260 + _pulseController.value * 20,
                      height: 260 + _pulseController.value * 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _getSpeedColor(animatedSpeed).withValues(
                              alpha: 0.15 - _pulseController.value * 0.1,
                            ),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    );
                  },
                ),
              // 主圆形背景
              Container(
                width: 240,
                height: 240,
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
                      color: colorScheme.shadow.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color:
                          _getSpeedColor(animatedSpeed).withValues(alpha: 0.1),
                      blurRadius: 16,
                      spreadRadius: -4,
                    ),
                  ],
                ),
              ),
              // 进度圆环
              CustomPaint(
                size: const Size(220, 220),
                painter: _SpeedGaugePainter(
                  progress: (animatedSpeed / maxSpeed).clamp(0, 1),
                  color: _getSpeedColor(animatedSpeed),
                  backgroundColor: colorScheme.surfaceContainerHigh,
                  isActive: isActive,
                ),
              ),
              // 中心脉冲效果
              if (isActive)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 160 + _pulseController.value * 10,
                      height: 160 + _pulseController.value * 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _getSpeedColor(animatedSpeed).withValues(
                            alpha: 0.2 - _pulseController.value * 0.15,
                          ),
                          width: 2,
                        ),
                      ),
                    );
                  },
                ),
              // 速度数值显示
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [
                        _getSpeedColor(animatedSpeed),
                        _getSpeedColor(animatedSpeed).withValues(alpha: 0.8),
                      ],
                    ).createShader(bounds),
                    child: Text(
                      animatedSpeed.toStringAsFixed(1),
                      style: textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getSpeedUnitString(),
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
          value:
              '${_convertSpeed(_downloadSpeed).toStringAsFixed(1)} ${_getSpeedUnitString()}',
          color: Colors.green,
        ),
        const SizedBox(height: 12),
        _ResultRow(
          icon: Icons.upload_rounded,
          label: '上传',
          value:
              '${_convertSpeed(_uploadSpeed).toStringAsFixed(1)} ${_getSpeedUnitString()}',
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

  // 转换速度单位
  double _convertSpeed(double speedMbps) {
    if (_speedUnit == SpeedUnit.mbs) {
      return speedMbps / 8; // Mbps to MB/s
    }
    return speedMbps;
  }

  // 获取单位字符串
  String _getSpeedUnitString() {
    return _speedUnit == SpeedUnit.mbps ? 'Mbps' : 'MB/s';
  }

  Color _getSpeedColor(double speed) {
    // 根据单位调整阈值
    final threshold = _speedUnit == SpeedUnit.mbps ? 1.0 : 0.125;
    if (speed >= 100 * threshold) return Colors.green;
    if (speed >= 50 * threshold) return Colors.lightGreen;
    if (speed >= 20 * threshold) return Colors.orange;
    if (speed >= 5 * threshold) return Colors.deepOrange;
    return Colors.red;
  }
}

class _SpeedGaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;
  final bool isActive;

  _SpeedGaugePainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
    this.isActive = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const startAngle = 140 * math.pi / 180;
    const sweepAngle = 260 * math.pi / 180;

    // 背景轨道 - 更细腻的设计
    final bgPaint = Paint()
      ..color = backgroundColor.withValues(alpha: 0.3)
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

    // 进度条 - 渐变色彩
    if (progress > 0) {
      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + sweepAngle * progress,
          colors: _getGradientColors(progress),
          stops: _getGradientStops(progress),
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

      // 进度端点光晕效果
      if (isActive) {
        final endAngle = startAngle + sweepAngle * progress;
        final endX = center.dx + radius * math.cos(endAngle);
        final endY = center.dy + radius * math.sin(endAngle);
        final endPoint = Offset(endX, endY);

        final glowPaint = Paint()
          ..color = color.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

        canvas.drawCircle(endPoint, 12, glowPaint);

        final dotPaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;

        canvas.drawCircle(endPoint, 6, dotPaint);
      }
    }
  }

  List<Color> _getGradientColors(double progress) {
    if (progress < 0.2) {
      return [Colors.red.shade400, Colors.red.shade600];
    } else if (progress < 0.4) {
      return [Colors.orange.shade400, Colors.orange.shade600];
    } else if (progress < 0.6) {
      return [Colors.amber.shade400, Colors.amber.shade600];
    } else if (progress < 0.8) {
      return [Colors.lightGreen.shade400, Colors.lightGreen.shade600];
    } else {
      return [Colors.green.shade400, Colors.green.shade600];
    }
  }

  List<double> _getGradientStops(double progress) {
    return [0.0, 1.0];
  }

  @override
  bool shouldRepaint(covariant _SpeedGaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.isActive != isActive;
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
    final colorScheme = Theme.of(context).colorScheme;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, animValue, child) {
        return Transform.scale(
          scale: 0.9 + (animValue * 0.1),
          child: Opacity(
            opacity: animValue,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.08),
                    color.withValues(alpha: 0.12),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: color.withValues(alpha: 0.2),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          color.withValues(alpha: 0.2),
                          color.withValues(alpha: 0.3),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      label,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [color, color.withValues(alpha: 0.8)],
                    ).createShader(bounds),
                    child: Text(
                      value,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
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
