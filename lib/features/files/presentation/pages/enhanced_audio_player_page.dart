import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shimmer/shimmer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/shell_scaffold.dart';

/// Enhanced audio player with visualizations and Material Design 3 Expressive animations
class EnhancedAudioPlayerPage extends ConsumerStatefulWidget {
  final String mediaUrl;
  final String fileName;

  const EnhancedAudioPlayerPage({
    super.key,
    required this.mediaUrl,
    required this.fileName,
  });

  @override
  ConsumerState<EnhancedAudioPlayerPage> createState() =>
      _EnhancedAudioPlayerPageState();
}

class _EnhancedAudioPlayerPageState
    extends ConsumerState<EnhancedAudioPlayerPage>
    with TickerProviderStateMixin {
  AudioPlayer? _audioPlayer;
  bool _isLoading = true;
  String? _error;
  String? _authToken;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

  // Animation controllers for expressive animations
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _rotationController;
  late AnimationController _scaleController;

  // Audio visualization data
  final List<double> _audioLevels = List.filled(32, 0.0);
  Timer? _visualizationTimer;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadTokenAndInitialize();
    WakelockPlus.enable();
    _startVisualizationSimulation();
  }

  void _initializeAnimations() {
    // Pulse animation for play button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Wave animation for background
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Rotation animation for album art
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );

    // Scale animation for interactive elements
    _scaleController = AnimationController(
      vsync: this,
      duration: M3Durations.medium2,
      value: 1.0,
    );
  }

  void _startVisualizationSimulation() {
    // Simulate audio levels based on playback state
    _visualizationTimer =
        Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < _audioLevels.length; i++) {
          if (_isPlaying) {
            // Simulate audio levels with smooth transitions
            final target = math.Random().nextDouble() * 0.8 + 0.2;
            _audioLevels[i] = _audioLevels[i] * 0.7 + target * 0.3;
          } else {
            // Fade out when paused
            _audioLevels[i] *= 0.9;
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _visualizationTimer?.cancel();
    _pulseController.dispose();
    _waveController.dispose();
    _rotationController.dispose();
    _scaleController.dispose();
    _audioPlayer?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _loadTokenAndInitialize() async {
    const storage = FlutterSecureStorage();
    _authToken = await storage.read(key: 'access_token');
    await _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _audioPlayer = AudioPlayer();

      final headers = <String, String>{
        'Accept': '*/*',
        'Connection': 'keep-alive',
      };
      if (_authToken != null && _authToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_authToken';
      }

      await _audioPlayer!.setAudioSource(
        AudioSource.uri(
          Uri.parse(widget.mediaUrl),
          headers: headers,
        ),
      );

      // Listen to player state
      _audioPlayer!.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
          });
          if (state.playing) {
            _rotationController.repeat();
          } else {
            _rotationController.stop();
          }
        }
      });

      // Listen to position
      _audioPlayer!.positionStream.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
        }
      });

      // Listen to duration
      _audioPlayer!.durationStream.listen((duration) {
        if (mounted && duration != null) {
          setState(() {
            _duration = duration;
          });
        }
      });

      // Auto play
      await _audioPlayer!.play();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load audio: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _togglePlayPause() async {
    if (_audioPlayer == null) return;

    // Animate button press
    await _scaleController.reverse();
    await _scaleController.forward();

    if (_isPlaying) {
      await _audioPlayer!.pause();
    } else {
      await _audioPlayer!.play();
    }
  }

  void _seekTo(Duration position) {
    _audioPlayer?.seek(position);
  }

  void _seekForward() {
    final newPos = _position + const Duration(seconds: 10);
    _seekTo(newPos > _duration ? _duration : newPos);
  }

  void _seekBackward() {
    final newPos = _position - const Duration(seconds: 10);
    _seekTo(newPos < Duration.zero ? Duration.zero : newPos);
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          ref.read(bottomNavVisibleProvider.notifier).show();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Stack(
          children: [
            // Animated gradient background
            _buildAnimatedBackground(colorScheme),
            // Main content
            SafeArea(
              child: _isLoading
                  ? _buildLoadingState(colorScheme)
                  : _error != null
                      ? _buildErrorState(colorScheme)
                      : _buildPlayerContent(colorScheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBackground(ColorScheme colorScheme) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primary.withValues(alpha: 0.1),
                colorScheme.secondary.withValues(alpha: 0.1),
                colorScheme.tertiary.withValues(alpha: 0.1),
              ],
              stops: [
                0.0,
                0.5 + math.sin(_waveController.value * 2 * math.pi) * 0.2,
                1.0,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Shimmer.fromColors(
            baseColor: colorScheme.primary.withValues(alpha: 0.3),
            highlightColor: colorScheme.primary.withValues(alpha: 0.6),
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Loading audio...',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      )
          .animate(onPlay: (controller) => controller.repeat())
          .fadeIn(duration: 600.ms)
          .scale(
            begin: const Offset(0.8, 0.8),
            end: const Offset(1.0, 1.0),
            duration: 600.ms,
            curve: M3Curves.emphasized,
          ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 80,
              color: colorScheme.error,
            )
                .animate()
                .scale(
                  duration: 400.ms,
                  curve: M3Curves.emphasized,
                )
                .shake(hz: 2, duration: 400.ms),
            const SizedBox(height: 24),
            Text(
              _error ?? 'Unknown error',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _initializePlayer,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            )
                .animate()
                .fadeIn(delay: 200.ms, duration: 400.ms)
                .slideY(begin: 0.2, end: 0, curve: M3Curves.emphasized),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerContent(ColorScheme colorScheme) {
    return Column(
      children: [
        const Spacer(),
        // Album art with rotation and pulse
        _buildAlbumArt(colorScheme),
        const SizedBox(height: 48),
        // Audio visualizer
        _buildAudioVisualizer(colorScheme),
        const SizedBox(height: 32),
        // Song title
        _buildSongTitle(colorScheme),
        const SizedBox(height: 48),
        // Progress bar
        _buildProgressBar(colorScheme),
        const SizedBox(height: 32),
        // Controls
        _buildControls(colorScheme),
        const Spacer(),
      ],
    );
  }

  Widget _buildAlbumArt(ColorScheme colorScheme) {
    return AnimatedBuilder(
      animation: Listenable.merge([_rotationController, _pulseController]),
      builder: (context, child) {
        final scale = _isPlaying
            ? 1.0 + math.sin(_pulseController.value * math.pi) * 0.05
            : 1.0;
        return Transform.scale(
          scale: scale,
          child: Transform.rotate(
            angle: _rotationController.value * 2 * math.pi,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary,
                    colorScheme.secondary,
                    colorScheme.tertiary,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.4),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Icon(
                Icons.music_note_rounded,
                size: 100,
                color: colorScheme.onPrimary,
              ),
            ),
          ),
        );
      },
    )
        .animate()
        .scale(
          duration: 600.ms,
          curve: M3Curves.emphasized,
        )
        .fadeIn(duration: 400.ms);
  }

  Widget _buildAudioVisualizer(ColorScheme colorScheme) {
    return SizedBox(
      height: 80,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(_audioLevels.length, (index) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            curve: M3Curves.emphasized,
            width: 4,
            height: 80 * _audioLevels[index],
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  colorScheme.primary,
                  colorScheme.secondary,
                ],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    )
        .animate()
        .fadeIn(delay: 200.ms, duration: 400.ms)
        .slideY(begin: 0.3, end: 0, curve: M3Curves.emphasized);
  }

  Widget _buildSongTitle(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            widget.fileName,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            'Now Playing',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(delay: 300.ms, duration: 400.ms)
        .slideY(begin: 0.2, end: 0, curve: M3Curves.emphasized);
  }

  Widget _buildProgressBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.surfaceContainerHighest,
              thumbColor: colorScheme.primary,
              overlayColor: colorScheme.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: _duration.inMilliseconds > 0
                  ? (_position.inMilliseconds / _duration.inMilliseconds)
                      .clamp(0.0, 1.0)
                  : 0,
              onChanged: (value) {
                _seekTo(Duration(
                    milliseconds: (value * _duration.inMilliseconds).round()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_position),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _formatDuration(_duration),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(delay: 400.ms, duration: 400.ms)
        .slideX(begin: -0.2, end: 0, curve: M3Curves.emphasized);
  }

  Widget _buildControls(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Skip backward
          IconButton(
            iconSize: 36,
            icon: const Icon(Icons.replay_10_rounded),
            onPressed: _seekBackward,
            color: colorScheme.onSurface,
          ).animate().fadeIn(delay: 500.ms, duration: 300.ms).scale(
                begin: const Offset(0.5, 0.5),
                curve: M3Curves.emphasized,
              ),
          // Play/Pause with expressive animation
          ScaleTransition(
            scale: _scaleController,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.secondary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: IconButton(
                iconSize: 40,
                icon: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: colorScheme.onPrimary,
                ),
                onPressed: _togglePlayPause,
              ),
            ),
          ).animate().fadeIn(delay: 550.ms, duration: 300.ms).scale(
                begin: const Offset(0.3, 0.3),
                curve: M3Curves.emphasized,
              ),
          // Skip forward
          IconButton(
            iconSize: 36,
            icon: const Icon(Icons.forward_10_rounded),
            onPressed: _seekForward,
            color: colorScheme.onSurface,
          ).animate().fadeIn(delay: 600.ms, duration: 300.ms).scale(
                begin: const Offset(0.5, 0.5),
                curve: M3Curves.emphasized,
              ),
        ],
      ),
    );
  }
}
