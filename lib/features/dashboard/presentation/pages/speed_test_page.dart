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
  bool _isCancelled = false;
  Timer? _downloadUpdateTimer;
  Timer? _uploadUpdateTimer;

  late AnimationController _needleController;
  late AnimationController _pulseController;
  late AnimationController _tickController;

  static const int _pingTestCount = 10;
  static const int _downloadTestDurationSec = 10;
  static const int _uploadTestDurationSec = 10;
  static const int _downloadChunkSizeMB = 65;

  @override
  void initState() {
    super.initState();
    _needleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _tickController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      const storage = FlutterSecureStorage();
      _authToken = await storage.read(key: 'access_token');
      final device = ref.read(connectedDeviceProvider);
      if (device != null) _serverUrl = device.baseUrl;
      if (mounted) setState(() => _configLoaded = true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _isCancelled = true;
    _downloadUpdateTimer?.cancel();
    _uploadUpdateTimer?.cancel();
    _needleController.dispose();
    _pulseController.dispose();
    _tickController.dispose();
    super.dispose();
  }

  Future<void> _startSpeedTest() async {
    if (!_configLoaded) await _loadConfig();
    final device = ref.read(connectedDeviceProvider);
    if (device == null) {
      setState(() {
        _state = SpeedTestState.error;
        _error = 'Not connected to NAS';
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
      _testPhase = 'Measuring latency...';
      _isCancelled = false;
    });

    try {
      await _testPing();
      if (!mounted || _isCancelled) return;
      setState(() {
        _state = SpeedTestState.testingDownload;
        _testPhase = 'Download...';
        _testProgress = 0;
      });
      await _testDownload();
      if (!mounted || _isCancelled) return;
      setState(() {
        _state = SpeedTestState.testingUpload;
        _testPhase = 'Upload...';
        _testProgress = 0;
      });
      await _testUpload();
      if (!mounted || _isCancelled) return;
      setState(() {
        _state = SpeedTestState.completed;
        _testPhase = 'Complete';
        _testProgress = 1.0;
      });
    } catch (e) {
      if (mounted && !_isCancelled)
        setState(() {
          _state = SpeedTestState.error;
          _error = e.toString();
        });
    }
  }

  Future<void> _testPing() async {
    if (_serverUrl == null) return;
    final List<int> pings = [];
    final uri = Uri.parse('$_serverUrl/api/v1/speedtest/ping');
    final headers = <String, String>{};
    if (_authToken != null && _authToken!.isNotEmpty)
      headers['Authorization'] = 'Bearer $_authToken';

    for (int i = 0; i < _pingTestCount; i++) {
      if (!mounted || _isCancelled) return;
      try {
        final sw = Stopwatch()..start();
        final r = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 10));
        sw.stop();
        if (r.statusCode == 200) {
          pings.add(sw.elapsedMilliseconds);
          if (mounted && !_isCancelled) {
            setState(() {
              _ping = pings.reduce((a, b) => a + b) ~/ pings.length;
              _testProgress = (i + 1) / _pingTestCount;
            });
          }
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (pings.isNotEmpty) {
      final avg = pings.reduce((a, b) => a + b) ~/ pings.length;
      double jitterSum = 0;
      for (int i = 1; i < pings.length; i++)
        jitterSum += (pings[i] - pings[i - 1]).abs();
      if (mounted && !_isCancelled)
        setState(() {
          _ping = avg;
          _jitter = pings.length > 1 ? jitterSum / (pings.length - 1) : 0;
        });
    }
  }

  Future<void> _testDownload() async {
    if (_serverUrl == null) return;
    final List<double> speeds = [];
    final startTime = DateTime.now();
    final testDuration = Duration(seconds: _downloadTestDurationSec);
    final headers = <String, String>{};
    if (_authToken != null && _authToken!.isNotEmpty)
      headers['Authorization'] = 'Bearer $_authToken';

    try {
      double instantSpeed = 0;
      int totalBytes = 0;
      final sw = Stopwatch()..start();

      _downloadUpdateTimer =
          Timer.periodic(const Duration(milliseconds: 50), (t) {
        if (!mounted || _isCancelled) {
          t.cancel();
          return;
        }
        final elapsed = sw.elapsedMilliseconds / 1000;
        if (elapsed > 0 && totalBytes > 0) {
          final avg = (totalBytes * 8) / (elapsed * 1000000);
          instantSpeed =
              instantSpeed == 0 ? avg : instantSpeed * 0.7 + avg * 0.3;
          setState(() {
            _currentSpeed = instantSpeed;
            _downloadSpeed = instantSpeed;
            _testProgress =
                (DateTime.now().difference(startTime).inMilliseconds /
                        testDuration.inMilliseconds)
                    .clamp(0.0, 1.0);
          });
        }
      });

      while (DateTime.now().difference(startTime) < testDuration) {
        if (!mounted || _isCancelled) break;
        final chunkSw = Stopwatch()..start();
        try {
          final uri = Uri.parse(
              '$_serverUrl/api/v1/speedtest/download?size=$_downloadChunkSizeMB');
          final req = http.Request('GET', uri);
          headers.forEach((k, v) => req.headers[k] = v);
          final resp = await http.Client()
              .send(req)
              .timeout(const Duration(seconds: 60));
          if (resp.statusCode == 200) {
            int chunkBytes = 0;
            await for (final chunk in resp.stream) {
              if (_isCancelled) break;
              chunkBytes += chunk.length;
              totalBytes += chunk.length;
            }
            chunkSw.stop();
            final e = chunkSw.elapsedMilliseconds / 1000;
            if (e > 0 && chunkBytes > 0)
              speeds.add((chunkBytes * 8) / (e * 1000000));
          }
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 100));
      }
      _downloadUpdateTimer?.cancel();
      sw.stop();
      if (speeds.isNotEmpty && mounted && !_isCancelled) {
        speeds.sort();
        final median = speeds[speeds.length ~/ 2];
        setState(() {
          _downloadSpeed = median;
          _currentSpeed = median;
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
    final testData = Uint8List(5 * 1024 * 1024);
    final rng = math.Random();
    for (int i = 0; i < testData.length; i++) testData[i] = rng.nextInt(256);
    final headers = <String, String>{
      'Content-Type': 'application/octet-stream',
      'Content-Length': testData.length.toString()
    };
    if (_authToken != null && _authToken!.isNotEmpty)
      headers['Authorization'] = 'Bearer $_authToken';

    try {
      double instantSpeed = 0;
      int totalBytes = 0;
      final sw = Stopwatch()..start();

      _uploadUpdateTimer =
          Timer.periodic(const Duration(milliseconds: 50), (t) {
        if (!mounted || _isCancelled) {
          t.cancel();
          return;
        }
        final elapsed = sw.elapsedMilliseconds / 1000;
        if (elapsed > 0 && totalBytes > 0) {
          final avg = (totalBytes * 8) / (elapsed * 1000000);
          instantSpeed =
              instantSpeed == 0 ? avg : instantSpeed * 0.7 + avg * 0.3;
          setState(() {
            _uploadSpeed = instantSpeed;
            _currentSpeed = instantSpeed;
            _testProgress =
                (DateTime.now().difference(startTime).inMilliseconds /
                        testDuration.inMilliseconds)
                    .clamp(0.0, 1.0);
          });
        }
      });

      while (DateTime.now().difference(startTime) < testDuration) {
        if (!mounted || _isCancelled) break;
        final upSw = Stopwatch()..start();
        try {
          final uri = Uri.parse('$_serverUrl/api/v1/speedtest/upload');
          final r = await http
              .post(uri, headers: headers, body: testData)
              .timeout(const Duration(seconds: 60));
          upSw.stop();
          if (r.statusCode == 200) {
            totalBytes += testData.length;
            final e = upSw.elapsedMilliseconds / 1000;
            if (e > 0) speeds.add((testData.length * 8) / (e * 1000000));
          }
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 100));
      }
      _uploadUpdateTimer?.cancel();
      sw.stop();
      if (speeds.isNotEmpty && mounted && !_isCancelled) {
        speeds.sort();
        final median = speeds[speeds.length ~/ 2];
        setState(() {
          _uploadSpeed = median;
          _currentSpeed = median;
        });
      }
    } finally {
      _uploadUpdateTimer?.cancel();
    }
  }

  double _convertSpeed(double mbps) =>
      _speedUnit == SpeedUnit.mbs ? mbps / 8 : mbps;
  String _unitStr() => _speedUnit == SpeedUnit.mbps ? 'Mbps' : 'MB/s';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final device = ref.watch(connectedDeviceProvider);
    final isRunning = _state != SpeedTestState.idle &&
        _state != SpeedTestState.completed &&
        _state != SpeedTestState.error;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            pinned: false,
            backgroundColor: cs.surface,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SegmentedButton<SpeedUnit>(
                  segments: const [
                    ButtonSegment(value: SpeedUnit.mbps, label: Text('Mbps')),
                    ButtonSegment(value: SpeedUnit.mbs, label: Text('MB/s')),
                  ],
                  selected: {_speedUnit},
                  onSelectionChanged: (s) =>
                      setState(() => _speedUnit = s.first),
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Device card
                _buildDeviceCard(device, cs, tt),
                const SizedBox(height: 24),
                // Watch-style gauge
                _buildWatchGauge(cs, tt, isRunning),
                const SizedBox(height: 16),
                // Sub-dials row
                _buildSubDials(cs, tt),
                const SizedBox(height: 24),
                // Progress
                if (isRunning) _buildProgress(cs, tt),
                if (isRunning) const SizedBox(height: 16),
                // Start button
                _buildStartButton(cs, isRunning, device != null),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: cs.errorContainer.withValues(alpha: 0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Icon(Icons.error_outline, color: cs.error),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_error!,
                                style:
                                    tt.bodySmall?.copyWith(color: cs.error))),
                      ]),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(dynamic device, ColorScheme cs, TextTheme tt) {
    if (device == null) {
      return Card(
          color: cs.errorContainer.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.warning_rounded, color: cs.error),
              const SizedBox(width: 12),
              Text('NAS Not Connected',
                  style: tt.titleSmall?.copyWith(color: cs.error))
            ]),
          ));
    }
    return Card(
      elevation: 0,
      color: cs.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.dns_rounded, color: cs.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(device.name,
                    style:
                        tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(device.baseUrl,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle, size: 14, color: Colors.green),
              const SizedBox(width: 4),
              Text('Connected',
                  style: tt.labelSmall?.copyWith(color: Colors.green)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildWatchGauge(ColorScheme cs, TextTheme tt, bool isActive) {
    final displaySpeed = _convertSpeed(_currentSpeed);
    final maxSpeed = _speedUnit == SpeedUnit.mbps ? 10000.0 : 1250.0;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: displaySpeed),
      builder: (context, speed, _) {
        return Center(
          child: SizedBox(
            width: 320,
            height: 320,
            child: Stack(alignment: Alignment.center, children: [
              // Outer bezel shadow
              Container(
                width: 310,
                height: 310,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.surfaceContainerHighest,
                      cs.surfaceContainerLow
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: cs.shadow.withValues(alpha: 0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 8)),
                    BoxShadow(
                        color: cs.shadow.withValues(alpha: 0.05),
                        blurRadius: 4,
                        spreadRadius: 1),
                  ],
                ),
              ),
              // Inner dial face
              Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [cs.surface, cs.surfaceContainerLow],
                    stops: const [0.6, 1.0],
                  ),
                ),
              ),
              // Gauge painter
              CustomPaint(
                size: const Size(280, 280),
                painter: _WatchGaugePainter(
                  speed: speed,
                  maxSpeed: maxSpeed,
                  speedUnit: _speedUnit,
                  accentColor: _speedColor(speed, maxSpeed),
                  dialColor: cs.onSurface,
                  tickColor: cs.onSurfaceVariant,
                  isActive: isActive,
                ),
              ),
              // Center display
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  speed < 100
                      ? speed.toStringAsFixed(1)
                      : speed.toStringAsFixed(0),
                  style: tt.displayMedium?.copyWith(
                    fontWeight: FontWeight.w300,
                    letterSpacing: -2,
                    color: cs.onSurface,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  decoration: BoxDecoration(
                    color: _speedColor(speed, maxSpeed).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_unitStr(),
                      style: tt.labelMedium?.copyWith(
                        color: _speedColor(speed, maxSpeed),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      )),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildSubDials(ColorScheme cs, TextTheme tt) {
    return Row(children: [
      Expanded(
          child: _SubDial(
              label: 'DOWNLOAD',
              value: _convertSpeed(_downloadSpeed).toStringAsFixed(1),
              unit: _unitStr(),
              icon: Icons.arrow_downward_rounded,
              color: const Color(0xFF4CAF50))),
      const SizedBox(width: 12),
      Expanded(
          child: _SubDial(
              label: 'UPLOAD',
              value: _convertSpeed(_uploadSpeed).toStringAsFixed(1),
              unit: _unitStr(),
              icon: Icons.arrow_upward_rounded,
              color: const Color(0xFF2196F3))),
      const SizedBox(width: 12),
      Expanded(
          child: _SubDial(
              label: 'PING',
              value: '$_ping',
              unit: 'ms',
              icon: Icons.network_ping_rounded,
              color: const Color(0xFFFF9800))),
      const SizedBox(width: 12),
      Expanded(
          child: _SubDial(
              label: 'JITTER',
              value: _jitter.toStringAsFixed(1),
              unit: 'ms',
              icon: Icons.swap_vert_rounded,
              color: const Color(0xFF9C27B0))),
    ]);
  }

  Widget _buildProgress(ColorScheme cs, TextTheme tt) {
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: _testProgress,
          minHeight: 6,
          backgroundColor: cs.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation(_speedColor(
              _convertSpeed(_currentSpeed),
              _speedUnit == SpeedUnit.mbps ? 10000 : 1250)),
        ),
      ),
      const SizedBox(height: 8),
      Text(_testPhase,
          style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
    ]);
  }

  Widget _buildStartButton(ColorScheme cs, bool isRunning, bool enabled) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: (isRunning || !enabled) ? null : _startSpeedTest,
        style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(isRunning ? Icons.hourglass_top_rounded : Icons.speed_rounded,
              size: 24),
          const SizedBox(width: 10),
          Text(isRunning ? 'Testing...' : 'Start Speed Test',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Color _speedColor(double speed, double maxSpeed) {
    final p = speed / maxSpeed;
    if (p >= 0.5) return const Color(0xFF4CAF50);
    if (p >= 0.25) return const Color(0xFF8BC34A);
    if (p >= 0.1) return const Color(0xFFFFC107);
    if (p >= 0.05) return const Color(0xFFFF9800);
    if (p >= 0.01) return const Color(0xFFFF5722);
    return const Color(0xFFF44336);
  }
}

/// Luxury watch-style gauge painter inspired by Patek Philippe chronograph
class _WatchGaugePainter extends CustomPainter {
  final double speed;
  final double maxSpeed;
  final SpeedUnit speedUnit;
  final Color accentColor;
  final Color dialColor;
  final Color tickColor;
  final bool isActive;

  _WatchGaugePainter({
    required this.speed,
    required this.maxSpeed,
    required this.speedUnit,
    required this.accentColor,
    required this.dialColor,
    required this.tickColor,
    this.isActive = false,
  });

  List<double> get _majorValues => speedUnit == SpeedUnit.mbps
      ? [0, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]
      : [0, 1.25, 3.125, 6.25, 12.5, 31.25, 62.5, 125, 312.5, 625, 1250];

  double _toAngle(double value) {
    if (value <= 0) return 0;
    return (math.log(1 + value) / math.log(1 + maxSpeed)).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const startAngle = 135 * math.pi / 180;
    const sweepAngle = 270 * math.pi / 180;

    // Outer minute track (fine ticks like a watch chapter ring)
    _drawChapterRing(canvas, center, radius, startAngle, sweepAngle);

    // Major indices (like hour markers on a luxury watch)
    _drawIndices(canvas, center, radius, startAngle, sweepAngle);

    // Active arc (colored sweep)
    final progress = _toAngle(speed);
    if (progress > 0) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + sweepAngle * progress,
          colors: [accentColor.withValues(alpha: 0.4), accentColor],
        ).createShader(Rect.fromCircle(center: center, radius: radius - 22));

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 22),
        startAngle,
        sweepAngle * progress,
        false,
        arcPaint,
      );
    }

    // Needle
    _drawNeedle(canvas, center, radius, startAngle, sweepAngle, progress);

    // Center cap (like a watch crown)
    final capGrad = RadialGradient(colors: [
      dialColor.withValues(alpha: 0.3),
      dialColor.withValues(alpha: 0.1),
    ]);
    canvas.drawCircle(
        center,
        8,
        Paint()
          ..shader =
              capGrad.createShader(Rect.fromCircle(center: center, radius: 8)));
    canvas.drawCircle(
        center,
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = tickColor.withValues(alpha: 0.3)
          ..strokeWidth = 1.5);
    canvas.drawCircle(center, 3, Paint()..color = accentColor);
  }

  void _drawChapterRing(Canvas canvas, Offset center, double radius,
      double startAngle, double sweepAngle) {
    final totalTicks = 60;
    final tickPaint = Paint()
      ..color = tickColor.withValues(alpha: 0.15)
      ..strokeWidth = 0.8;
    final outerR = radius - 2;
    final innerR = radius - 8;

    for (int i = 0; i <= totalTicks; i++) {
      final t = i / totalTicks;
      final angle = startAngle + sweepAngle * t;
      canvas.drawLine(
        Offset(center.dx + innerR * math.cos(angle),
            center.dy + innerR * math.sin(angle)),
        Offset(center.dx + outerR * math.cos(angle),
            center.dy + outerR * math.sin(angle)),
        tickPaint,
      );
    }
  }

  void _drawIndices(Canvas canvas, Offset center, double radius,
      double startAngle, double sweepAngle) {
    final majorPaint = Paint()
      ..color = dialColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final minorPaint = Paint()
      ..color = tickColor.withValues(alpha: 0.4)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final tp = TextPainter(
        textDirection: TextDirection.ltr, textAlign: TextAlign.center);

    final outerR = radius - 10;
    final majorInnerR = radius - 30;
    final labelR = radius - 44;

    for (int i = 0; i < _majorValues.length; i++) {
      final v = _majorValues[i];
      final t = _toAngle(v);
      final angle = startAngle + sweepAngle * t;

      // Major tick (applied index style)
      canvas.drawLine(
        Offset(center.dx + majorInnerR * math.cos(angle),
            center.dy + majorInnerR * math.sin(angle)),
        Offset(center.dx + outerR * math.cos(angle),
            center.dy + outerR * math.sin(angle)),
        majorPaint,
      );

      // Label
      String label;
      if (speedUnit == SpeedUnit.mbps) {
        label = v >= 1000
            ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k'
            : v.toStringAsFixed(0);
      } else {
        label = v >= 100
            ? v.toStringAsFixed(0)
            : v >= 10
                ? v.toStringAsFixed(v % 1 == 0 ? 0 : 1)
                : v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
      }

      tp.text = TextSpan(
          text: label,
          style: TextStyle(
            color: tickColor.withValues(alpha: 0.7),
            fontSize: 9,
            fontWeight: FontWeight.w500,
            fontFamily: 'monospace',
          ));
      tp.layout();
      final lx = center.dx + labelR * math.cos(angle) - tp.width / 2;
      final ly = center.dy + labelR * math.sin(angle) - tp.height / 2;
      tp.paint(canvas, Offset(lx, ly));

      // Minor ticks between majors
      if (i < _majorValues.length - 1) {
        final nextT = _toAngle(_majorValues[i + 1]);
        if ((nextT - t) > 0.06) {
          final midT = (t + nextT) / 2;
          final midAngle = startAngle + sweepAngle * midT;
          canvas.drawLine(
            Offset(center.dx + (majorInnerR + 8) * math.cos(midAngle),
                center.dy + (majorInnerR + 8) * math.sin(midAngle)),
            Offset(center.dx + outerR * math.cos(midAngle),
                center.dy + outerR * math.sin(midAngle)),
            minorPaint,
          );
        }
      }
    }
  }

  void _drawNeedle(Canvas canvas, Offset center, double radius,
      double startAngle, double sweepAngle, double progress) {
    final needleAngle = startAngle + sweepAngle * progress;
    final needleLength = radius - 36;
    final tailLength = 18.0;

    // Needle shadow
    final shadowPath = Path();
    final sx = center.dx + 1;
    final sy = center.dy + 2;
    shadowPath.moveTo(sx + needleLength * math.cos(needleAngle),
        sy + needleLength * math.sin(needleAngle));
    shadowPath.lineTo(sx + 4 * math.cos(needleAngle + math.pi / 2),
        sy + 4 * math.sin(needleAngle + math.pi / 2));
    shadowPath.lineTo(sx - tailLength * math.cos(needleAngle),
        sy - tailLength * math.sin(needleAngle));
    shadowPath.lineTo(sx + 4 * math.cos(needleAngle - math.pi / 2),
        sy + 4 * math.sin(needleAngle - math.pi / 2));
    shadowPath.close();
    canvas.drawPath(
        shadowPath,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));

    // Needle body
    final needlePath = Path();
    needlePath.moveTo(center.dx + needleLength * math.cos(needleAngle),
        center.dy + needleLength * math.sin(needleAngle));
    needlePath.lineTo(center.dx + 3 * math.cos(needleAngle + math.pi / 2),
        center.dy + 3 * math.sin(needleAngle + math.pi / 2));
    needlePath.lineTo(center.dx - tailLength * math.cos(needleAngle),
        center.dy - tailLength * math.sin(needleAngle));
    needlePath.lineTo(center.dx + 3 * math.cos(needleAngle - math.pi / 2),
        center.dy + 3 * math.sin(needleAngle - math.pi / 2));
    needlePath.close();
    canvas.drawPath(needlePath, Paint()..color = accentColor);

    // Needle tip highlight
    final tipX = center.dx + needleLength * math.cos(needleAngle);
    final tipY = center.dy + needleLength * math.sin(needleAngle);
    canvas.drawCircle(Offset(tipX, tipY), 2,
        Paint()..color = Colors.white.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(covariant _WatchGaugePainter old) =>
      old.speed != speed ||
      old.accentColor != accentColor ||
      old.isActive != isActive ||
      old.speedUnit != speedUnit;
}

/// Sub-dial widget (like chronograph sub-dials on a luxury watch)
class _SubDial extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _SubDial(
      {required this.label,
      required this.value,
      required this.unit,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 6),
        Text(value,
            style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w700, color: cs.onSurface, height: 1)),
        Text(unit,
            style: tt.labelSmall
                ?.copyWith(color: cs.onSurfaceVariant, fontSize: 9)),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.8)),
      ]),
    );
  }
}
