import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

class MediaKitInitializer {
  static bool _initialized = false;

  static const String localAssetsPath =
      r'D:\RustProject\RockZeroOS-Service\assets';

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

    final ffmpegPath = '$localAssetsPath\\ffmpeg.exe';
    final ffmpegFile = File(ffmpegPath);

    if (await ffmpegFile.exists()) {
      debugPrint('[MediaKit] Found local ffmpeg: $ffmpegPath');
      final currentPath = Platform.environment['PATH'] ?? '';
      if (!currentPath.contains(localAssetsPath)) {
        debugPrint('[MediaKit] Local assets path: $localAssetsPath');
      }
    } else {
      debugPrint('[MediaKit] Local ffmpeg not found, using system ffmpeg');
    }
  }

  static Future<void> _initializeLinux() async {
    debugPrint('[MediaKit] Initializing for Linux...');

    final archivePath = '$localAssetsPath/ffmpeg-release-arm64-static.tar.xz';
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
      debugPrint('[MediaKit] Local ffmpeg archive not found');
    }
  }

  static Future<void> _initializeAndroid() async {
    debugPrint('[MediaKit] Initializing for Android...');

    final appDir = await getApplicationSupportDirectory();
    debugPrint('[MediaKit] App support directory: ${appDir.path}');
    debugPrint('[MediaKit] Android native libraries will be loaded from APK');
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
    if (Platform.isWindows) {
      final ffmpegPath = '$localAssetsPath\\ffmpeg.exe';
      if (await File(ffmpegPath).exists()) {
        return ffmpegPath;
      }
    } else if (Platform.isLinux) {
      final appDir = await getApplicationSupportDirectory();
      final ffmpegPath = '${appDir.path}/ffmpeg/ffmpeg';
      if (await File(ffmpegPath).exists()) {
        return ffmpegPath;
      }
    }

    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['ffmpeg'],
      );
      if (result.exitCode == 0) {
        return result.stdout.toString().trim().split('\n').first;
      }
    } catch (_) {}

    return null;
  }
}
