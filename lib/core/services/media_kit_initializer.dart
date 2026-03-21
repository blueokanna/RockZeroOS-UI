import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

class MediaKitInitializer {
  static bool _initialized = false;

  static const String _desktopAssetsPath = '../../assets';

  static Future<void> initialize() async {
    if (_initialized) {
      debugPrint('[MediaKit] Already initialized');
      return;
    }

    try {
      debugPrint('[MediaKit] Starting initialization...');
      debugPrint('[MediaKit] Platform: ${Platform.operatingSystem}');

      if (Platform.isWindows) {
        await _initializeWindows();
      } else if (Platform.isLinux) {
        await _initializeLinux();
      } else if (Platform.isAndroid) {
        await _initializeAndroid();
      } else if (Platform.isMacOS) {
        await _initializeMacOS();
      } else if (Platform.isIOS) {
        await _initializeIOS();
      }

      MediaKit.ensureInitialized();

      _initialized = true;
      debugPrint('[MediaKit] Initialization completed successfully');
    } catch (e, stack) {
      debugPrint('[MediaKit] Initialization failed: $e');
      debugPrint('[MediaKit] Stack trace: $stack');

      try {
        MediaKit.ensureInitialized();
        _initialized = true;
        debugPrint('[MediaKit] Fallback initialization succeeded');
      } catch (fallbackError) {
        debugPrint(
            '[MediaKit] Fallback initialization also failed: $fallbackError');
        rethrow;
      }
    }
  }

  static Future<void> _initializeWindows() async {
    debugPrint('[MediaKit] Initializing for Windows...');

    final ffmpegPath = '$_desktopAssetsPath\\ffmpeg.exe';
    final ffmpegFile = File(ffmpegPath);

    if (await ffmpegFile.exists()) {
      debugPrint('[MediaKit] Found local ffmpeg: $ffmpegPath');
      final currentPath = Platform.environment['PATH'] ?? '';
      if (!currentPath.contains(_desktopAssetsPath)) {
        debugPrint('[MediaKit] Local assets path: $_desktopAssetsPath');
      }
    } else {
      debugPrint('[MediaKit] Local ffmpeg not found, using system ffmpeg');
    }
  }

  static Future<void> _initializeLinux() async {
    debugPrint('[MediaKit] Initializing for Linux...');

    final archivePath =
        '$_desktopAssetsPath/ffmpeg-release-arm64-static.tar.xz';
    final archiveFile = File(archivePath);

    if (await archiveFile.exists()) {
      debugPrint('[MediaKit] Found local ffmpeg archive: $archivePath');

      final appDir = await getApplicationSupportDirectory();
      final ffmpegDir = Directory('${appDir.path}/ffmpeg');
      final ffmpegBinary = File('${ffmpegDir.path}/ffmpeg');

      if (!await ffmpegBinary.exists()) {
        debugPrint('[MediaKit] Extracting ffmpeg from archive...');
        await _extractTarXz(archivePath, ffmpegDir.path);
      }

      if (await ffmpegBinary.exists()) {
        debugPrint('[MediaKit] ffmpeg binary ready: ${ffmpegBinary.path}');
      }
    } else {
      debugPrint('[MediaKit] Local ffmpeg archive not found at: $archivePath');
      debugPrint('[MediaKit] Will use system ffmpeg if available');
    }
  }

  static Future<void> _initializeAndroid() async {
    debugPrint('[MediaKit] Initializing for Android...');

    try {
      final appDir = await getApplicationSupportDirectory();
      debugPrint('[MediaKit] App support directory: ${appDir.path}');
    } catch (e) {
      debugPrint('[MediaKit] Could not get app directory: $e');
    }

    debugPrint(
        '[MediaKit] Android native libraries (.so) will be loaded from APK');
    debugPrint('[MediaKit] Libraries location: lib/<abi>/ inside APK');
  }

  static Future<void> _initializeMacOS() async {
    debugPrint('[MediaKit] Initializing for macOS...');
  }

  static Future<void> _initializeIOS() async {
    debugPrint('[MediaKit] Initializing for iOS...');
  }

  static Future<void> _extractTarXz(String archivePath, String destPath) async {
    if (!Platform.isLinux) return;

    final destDir = Directory(destPath);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    final result = await Process.run(
      'tar',
      ['-xJf', archivePath, '-C', destPath, '--strip-components=1'],
    );

    if (result.exitCode != 0) {
      debugPrint('[MediaKit] tar extraction failed: ${result.stderr}');
      throw Exception('Failed to extract ffmpeg archive: ${result.stderr}');
    }

    final ffmpegBinary = File('$destPath/ffmpeg');
    if (await ffmpegBinary.exists()) {
      await Process.run('chmod', ['+x', ffmpegBinary.path]);
    }

    final ffprobeBinary = File('$destPath/ffprobe');
    if (await ffprobeBinary.exists()) {
      await Process.run('chmod', ['+x', ffprobeBinary.path]);
    }

    debugPrint('[MediaKit] ffmpeg extracted successfully');
  }

  static bool get isInitialized => _initialized;

  static Future<String?> getFfmpegPath() async {
    // Android 和 iOS 不使用 FFmpeg 可执行文件
    if (Platform.isAndroid || Platform.isIOS) {
      debugPrint('[MediaKit] FFmpeg path not applicable for mobile platforms');
      return null;
    }

    // Windows 桌面
    if (Platform.isWindows) {
      final ffmpegPath = '$_desktopAssetsPath\\ffmpeg.exe';
      if (await File(ffmpegPath).exists()) {
        return ffmpegPath;
      }
    }

    // Linux 桌面
    else if (Platform.isLinux) {
      try {
        final appDir = await getApplicationSupportDirectory();
        final ffmpegPath = '${appDir.path}/ffmpeg/ffmpeg';
        if (await File(ffmpegPath).exists()) {
          return ffmpegPath;
        }
      } catch (e) {
        debugPrint('[MediaKit] Error accessing app directory: $e');
      }
    }

    // 尝试查找系统 FFmpeg
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['ffmpeg'],
      );
      if (result.exitCode == 0) {
        return result.stdout.toString().trim().split('\n').first;
      }
    } catch (e) {
      debugPrint('[MediaKit] Error finding system ffmpeg: $e');
    }

    return null;
  }
}
