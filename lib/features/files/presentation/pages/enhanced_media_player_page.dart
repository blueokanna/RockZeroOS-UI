import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/widgets/shell_scaffold.dart';

/// Media info from server including transcode information
class MediaStreamInfo {
  final String filename;
  final String contentType;
  final int size;
  final double? duration;
  final int? width;
  final int? height;
  final String? videoCodec;
  final String? audioCodec;
  final int? bitrate;
  final bool supportsRange;
  final bool needsAudioTranscode;
  final String? transcodeUrl;
  final bool hasAudio;

  MediaStreamInfo({
    required this.filename,
    required this.contentType,
    required this.size,
    this.duration,
    this.width,
    this.height,
    this.videoCodec,
    this.audioCodec,
    this.bitrate,
    this.supportsRange = true,
    this.needsAudioTranscode = false,
    this.transcodeUrl,
    this.hasAudio = true,
  });

  factory MediaStreamInfo.fromJson(Map<String, dynamic> json) {
    return MediaStreamInfo(
      filename: json['filename'] ?? '',
      contentType: json['content_type'] ?? '',
      size: json['size'] ?? 0,
      duration: json['duration']?.toDouble(),
      width: json['width'],
      height: json['height'],
      videoCodec: json['video_codec'],
      audioCodec: json['audio_codec'],
      bitrate: json['bitrate'],
      supportsRange: json['supports_range'] ?? true,
      needsAudioTranscode: json['needs_audio_transcode'] ?? false,
      transcodeUrl: json['transcode_url'],
      hasAudio: json['has_audio'] ?? true,
    );
  }
}

/// Enhanced media player with DTS/AC3/TrueHD audio support via server-side transcoding
/// Uses video_player + chewie for cross-platform video playback
/// Automatically detects and uses transcoded stream for unsupported audio codecs
class EnhancedMediaPlayerPage extends ConsumerStatefulWidget {
  final String mediaUrl;
  final String fileName;
  final bool isVideo;

  const EnhancedMediaPlayerPage({
    super.key,
    required this.mediaUrl,
    required this.fileName,
    required this.isVideo,
  });

  @override
  ConsumerState<EnhancedMediaPlayerPage> createState() =>
      _EnhancedMediaPlayerPageState();
}

class _EnhancedMediaPlayerPageState
    extends ConsumerState<EnhancedMediaPlayerPage> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  bool _isLoading = true;
  String? _error;
  String? _authToken;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  bool _isLooping = false;

  // Media info
  MediaStreamInfo? _mediaInfo;
  bool _isTranscoding = false;
  String? _originalAudioCodec;

  @override
  void initState() {
    super.initState();
    _enterFullScreen();
    _loadTokenAndInitialize();
    WakelockPlus.enable();
  }

  void _enterFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky,
        overlays: []);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(bottomNavVisibleProvider.notifier).hide();
      }
    });
  }

  void _exitFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    ref.read(bottomNavVisibleProvider.notifier).show();
    WakelockPlus.disable();
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _exitFullScreen();
    super.dispose();
  }

  Future<void> _loadTokenAndInitialize() async {
    const storage = FlutterSecureStorage();
    _authToken = await storage.read(key: 'access_token');

    // First, get media info to check if transcoding is needed
    await _fetchMediaInfo();
    await _initializePlayer();
  }

  /// Fetch media info from server to check audio codec
  Future<void> _fetchMediaInfo() async {
    try {
      // Extract the file path from the media URL
      final uri = Uri.parse(widget.mediaUrl);
      final pathSegments = uri.pathSegments;

      // Build the info URL - assuming the media URL is like /api/v1/streaming/play/{path}
      // We need to call /api/v1/streaming/info/{path}
      String infoPath = '';
      bool foundPlay = false;
      for (final segment in pathSegments) {
        if (foundPlay) {
          infoPath += '/$segment';
        }
        if (segment == 'play' || segment == 'stream') {
          foundPlay = true;
        }
      }

      if (infoPath.isEmpty) {
        // Fallback: use the full path after the base
        infoPath = uri.path.replaceFirst(
            RegExp(r'/api/v1/(streaming|filemanager)/(play|stream)/'), '/');
      }

      final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';
      final infoUrl = '$baseUrl/api/v1/streaming/info$infoPath';

      debugPrint('[MediaPlayer] Fetching media info from: $infoUrl');

      final response = await http.get(
        Uri.parse(infoUrl),
        headers:
            _authToken != null ? {'Authorization': 'Bearer $_authToken'} : {},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        _mediaInfo = MediaStreamInfo.fromJson(json);
        _originalAudioCodec = _mediaInfo?.audioCodec;

        debugPrint('[MediaPlayer] Media info: codec=${_mediaInfo?.audioCodec}, '
            'needsTranscode=${_mediaInfo?.needsAudioTranscode}');
      }
    } catch (e) {
      debugPrint('[MediaPlayer] Failed to fetch media info: $e');
      // Continue without media info - will try direct playback
    }
  }

  /// Get the appropriate stream URL (transcoded or direct)
  String _getStreamUrl() {
    if (_mediaInfo?.needsAudioTranscode == true &&
        _mediaInfo?.transcodeUrl != null) {
      // Use transcoded stream for DTS/AC3/TrueHD
      final uri = Uri.parse(widget.mediaUrl);
      final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';
      _isTranscoding = true;
      return '$baseUrl${_mediaInfo!.transcodeUrl}';
    }
    return widget.mediaUrl;
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Capture theme colors before async operations
    final primaryColor = Theme.of(context).colorScheme.primary;

    try {
      // Dispose previous controllers if any
      _chewieController?.dispose();
      _videoController?.dispose();

      // Build headers for authentication
      final headers = <String, String>{};
      if (_authToken != null && _authToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_authToken';
      }

      // Get the appropriate stream URL
      final streamUrl = _getStreamUrl();
      debugPrint('[MediaPlayer] Using stream URL: $streamUrl');
      debugPrint('[MediaPlayer] Is transcoding: $_isTranscoding');

      // Create video controller with network URL and headers
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        httpHeaders: headers,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      // Initialize video controller
      await _videoController!.initialize();

      // Create chewie controller with custom options
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        looping: _isLooping,
        showControls: true,
        allowFullScreen: true,
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        playbackSpeeds: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
        errorBuilder: (context, errorMessage) {
          return _buildInlineError(errorMessage);
        },
        // Custom controls material style
        materialProgressColors: ChewieProgressColors(
          playedColor: primaryColor,
          handleColor: primaryColor,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
      );

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[VideoPlayer] Error: $e');

      // If direct playback failed and we haven't tried transcoding yet, try it
      if (!_isTranscoding && _mediaInfo?.needsAudioTranscode == true) {
        debugPrint('[VideoPlayer] Retrying with transcoded stream...');
        _isTranscoding = true;
        await _initializePlayer();
        return;
      }

      if (mounted) {
        setState(() {
          _error = _getErrorMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    // Check for common audio codec issues
    if (errorStr.contains('codec') ||
        errorStr.contains('audio') ||
        errorStr.contains('dts') ||
        errorStr.contains('ac3')) {
      if (_mediaInfo?.needsAudioTranscode == true) {
        return 'Audio transcoding failed.\n'
            'Original codec: ${_originalAudioCodec ?? "unknown"}\n'
            'Please check if FFmpeg is installed on the server.';
      }
      return 'Audio codec not supported.\n'
          'Codec: ${_originalAudioCodec ?? "unknown"}\n'
          'Server transcoding may not be available.';
    }

    if (errorStr.contains('network') || errorStr.contains('connection')) {
      return 'Network error. Please check your connection.';
    }

    if (errorStr.contains('format') || errorStr.contains('container')) {
      return 'Video format not supported.\n'
          'Try converting to MP4 with H.264 video and AAC audio.';
    }

    return 'Failed to load media: $error';
  }

  Widget _buildInlineError(String errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(
              errorMessage,
              style: const TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _toggleLoop() {
    setState(() => _isLooping = !_isLooping);
    _videoController?.setLooping(_isLooping);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isLooping ? 'Loop enabled' : 'Loop disabled'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _downloadFile() async {
    if (_isDownloading) return;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.storage.request();
      if (!status.isGranted && Platform.isAndroid) {
        final ms = await Permission.manageExternalStorage.request();
        if (!ms.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Storage permission required')),
            );
          }
          return;
        }
      }
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    Directory? downloadDir;
    try {
      if (Platform.isAndroid) {
        downloadDir =
            Directory('/storage/emulated/0/Download/RockZeroDownload');
      } else if (Platform.isIOS) {
        final docDir = await getApplicationDocumentsDirectory();
        downloadDir = Directory('${docDir.path}/RockZeroDownload');
      } else {
        final dlDir = await getDownloadsDirectory();
        if (dlDir != null) {
          downloadDir = Directory('${dlDir.path}/RockZeroDownload');
        }
      }

      if (downloadDir == null) {
        throw Exception('No download directory');
      }
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final file = File('${downloadDir.path}/${widget.fileName}');
      final request = http.Request('GET', Uri.parse(widget.mediaUrl));
      if (_authToken != null) {
        request.headers['Authorization'] = 'Bearer $_authToken';
      }

      final client = http.Client();
      final response = await client.send(request);
      final contentLength = response.contentLength ?? 0;
      final sink = file.openWrite();
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0 && mounted) {
          setState(() => _downloadProgress = received / contentLength);
        }
      }

      await sink.close();
      client.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded to ${downloadDir.path}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _exitFullScreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Video player
            _buildVideoPlayer(),

            // Top bar overlay (always visible)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(colorScheme),
            ),

            // Error state
            if (_error != null && !_isLoading) _buildErrorState(),

            // Download progress
            if (_isDownloading) _buildDownloadOverlay(),

            // Transcoding indicator
            if (_isTranscoding && !_isLoading && _error == null)
              _buildTranscodingIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              _isTranscoding ? 'Transcoding audio...' : 'Loading...',
              style: const TextStyle(color: Colors.white),
            ),
            if (_originalAudioCodec != null) ...[
              const SizedBox(height: 8),
              Text(
                'Audio: $_originalAudioCodec',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
        ),
      );
    }

    if (_chewieController != null && _videoController!.value.isInitialized) {
      return Chewie(controller: _chewieController!);
    }

    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }

  Widget _buildTopBar(ColorScheme colorScheme) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  _exitFullScreen();
                  Navigator.pop(context);
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.fileName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_mediaInfo != null) ...[
                      Text(
                        '${_mediaInfo!.videoCodec ?? "?"} / ${_mediaInfo!.audioCodec ?? "?"}${_isTranscoding ? " → AAC" : ""}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Download button
              if (_isDownloading)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      value: _downloadProgress,
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.white),
                  onPressed: _downloadFile,
                ),
              // Loop button
              IconButton(
                icon: Icon(
                  _isLooping ? Icons.repeat_one : Icons.repeat,
                  color: _isLooping ? colorScheme.primary : Colors.white,
                ),
                onPressed: _toggleLoop,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTranscodingIndicator() {
    return Positioned(
      bottom: 80,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.transform,
              color: Colors.orange.shade300,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              '${_originalAudioCodec?.toUpperCase() ?? "DTS"} → AAC',
              style: TextStyle(
                color: Colors.orange.shade300,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _initializePlayer,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _exitFullScreen();
                Navigator.pop(context);
              },
              child: const Text('Go Back'),
            ),
            const SizedBox(height: 24),
            // Audio codec info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Audio Codec Support:',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Direct: AAC, MP3, FLAC, Opus\n'
                    '• Transcoded: DTS, AC3, EAC3, TrueHD\n'
                    '• Current: ${_originalAudioCodec ?? "unknown"}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (_mediaInfo?.needsAudioTranscode == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Server transcoding: ${_isTranscoding ? "Active" : "Available"}',
                      style: TextStyle(
                        color: _isTranscoding ? Colors.green : Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadOverlay() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.download, color: Colors.white),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Downloading...',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                Text(
                  '${(_downloadProgress * 100).toInt()}%',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _downloadProgress,
              backgroundColor: Colors.white24,
            ),
          ],
        ),
      ),
    );
  }
}
