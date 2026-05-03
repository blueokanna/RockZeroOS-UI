import 'dart:convert';
import 'dart:typed_data';
import 'package:thirds/blake3.dart' as blake3;

class SaeUtils {
  static Uint8List hashDeviceId(String deviceId) {
    final hash = blake3.blake3(utf8.encode(deviceId), 32);
    return Uint8List.fromList(hash);
  }

  static Uint8List deviceIdFromString(String input) {
    if (input.length == 64) {
      try {
        final bytes = <int>[];
        for (int i = 0; i < input.length; i += 2) {
          bytes.add(int.parse(input.substring(i, i + 2), radix: 16));
        }
        if (bytes.length == 32) {
          return Uint8List.fromList(bytes);
        }
      } catch (_) {}
    }

    return hashDeviceId(input);
  }

  static String deviceIdToHex(Uint8List deviceId) {
    if (deviceId.length != 32) {
      throw ArgumentError('Device ID must be 32 bytes');
    }
    return deviceId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool isValidDeviceId(Uint8List deviceId) {
    return deviceId.length == 32;
  }

  static int compareDeviceIds(Uint8List id1, Uint8List id2) {
    final minLen = id1.length < id2.length ? id1.length : id2.length;
    for (int i = 0; i < minLen; i++) {
      if (id1[i] < id2[i]) return -1;
      if (id1[i] > id2[i]) return 1;
    }
    return id1.length.compareTo(id2.length);
  }

  static Uint8List generateRandomDeviceId() {
    final random =
        List.generate(32, (_) => DateTime.now().microsecondsSinceEpoch % 256);
    return Uint8List.fromList(random);
  }

  static int checkPasswordStrength(String password) {
    if (password.length < 8) return 0;
    if (password.length < 16) return 1;
    return 2;
  }

  static void clearSensitiveData(Uint8List data) {
    for (int i = 0; i < data.length; i++) {
      data[i] = 0;
    }
  }

  static String toBase64Url(Uint8List bytes) {
    return base64Url.encode(bytes);
  }

  static Uint8List fromBase64Url(String encoded) {
    return Uint8List.fromList(base64Url.decode(encoded));
  }
}

class SaeException implements Exception {
  final String message;
  final SaeErrorType type;

  SaeException(this.message, this.type);

  @override
  String toString() => 'SaeException: $message (type: $type)';
}

enum SaeErrorType {
  cryptoError,
  invalidState,
  invalidCommit,
  unsupportedGroup,
  confirmVerificationFailed,
  maxSyncReached,
  invalidCredentials,
  protocolError,
  networkError,
}

enum SaeState {
  nothing,
  committed,
  confirmed,
  accepted,
}

class SaeConfig {
  final int maxPweLoop;

  final int pweOffsetIterations;

  final int maxSync;

  final int groupId;

  const SaeConfig({
    this.maxPweLoop = 40,
    this.pweOffsetIterations = 8,
    this.maxSync = 3,
    this.groupId = 19,
  });

  static const SaeConfig defaultConfig = SaeConfig();

  static const SaeConfig fastConfig = SaeConfig(
    maxPweLoop: 10,
    pweOffsetIterations: 4,
  );
}
