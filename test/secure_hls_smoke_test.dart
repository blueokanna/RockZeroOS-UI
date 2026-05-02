import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/secure_hls_smoke.dart' as smoke;

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  test(
    'secure hls playback chain smoke',
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

      expect(filePath, isNotNull,
          reason: 'ROCKZERO_SMOKE_FILE must point to a local media file');
      expect(filePath, isNotEmpty,
          reason: 'ROCKZERO_SMOKE_FILE must not be empty');

      final result = await smoke.runSecureHlsSmoke(
        baseUrl: baseUrl,
        username: username,
        email: email,
        password: password,
        filePath: filePath!,
      );

      expect(result['success'], isTrue);
      expect(result['playlist_has_segments'], isTrue);
      expect(result['first_segment_bytes'], greaterThan(0));
      expect(result['first_sync_byte'], equals(0x47));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
