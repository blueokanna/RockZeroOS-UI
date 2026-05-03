import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum HlsMode {
  secure,
}

class HlsConfigService {
  static const String _boxName = 'settings';
  static const String _keyHlsMode = 'hls_mode';

  HlsMode getHlsMode() {
    return HlsMode.secure;
  }

  Future<void> setHlsMode(HlsMode mode) async {
    final box = Hive.box(_boxName);

    await box.put(_keyHlsMode, 'secure');
  }

  bool get isSecureMode => true;
}

final hlsConfigServiceProvider = Provider<HlsConfigService>((ref) {
  return HlsConfigService();
});

final hlsModeProvider = Provider<HlsMode>((ref) {
  return HlsMode.secure;
});
