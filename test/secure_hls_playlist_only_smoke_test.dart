import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/secure_hls_playlist_only_diag.dart' as playlist_only;

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  test(
    'secure hls playlist-only smoke',
    () async {
      final baseUrl =
          Platform.environment['ROCKZERO_BASE_URL'] ?? 'http://127.0.0.1:8080';
      final username =
          Platform.environment['ROCKZERO_SMOKE_USER'] ?? 'smoke_admin';
      final email = Platform.environment['ROCKZERO_SMOKE_EMAIL'] ??
          'smoke_admin@example.com';
      final password =
          Platform.environment['ROCKZERO_SMOKE_PASSWORD'] ?? 'SmokePass123';
      final filePath = Platform.environment['ROCKZERO_SMOKE_FILE'];
      final holdSeconds = int.tryParse(
              Platform.environment['ROCKZERO_PLAYLIST_HOLD_SECONDS'] ?? '') ??
          10;

      expect(filePath, isNotNull,
          reason: 'ROCKZERO_SMOKE_FILE must point to a local media file');
      expect(filePath, isNotEmpty,
          reason: 'ROCKZERO_SMOKE_FILE must not be empty');

      final result = await playlist_only.runSecureHlsPlaylistOnlyDiag(
        baseUrl: baseUrl,
        username: username,
        email: email,
        password: password,
        filePath: filePath!,
        holdSeconds: holdSeconds,
      );

      expect(result['success'], isTrue);
      expect(result['playlist_status'], equals(200));
      expect(result['playlist_length'], greaterThan(0));
      expect(result['health_before'], isTrue);
      expect(result['health_after'], isTrue);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
