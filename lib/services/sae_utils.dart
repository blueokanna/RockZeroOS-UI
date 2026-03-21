import 'dart:convert';
import 'dart:typed_data';
import 'package:thirds/blake3.dart' as blake3;

/// SAE utility functions
class SaeUtils {
  /// Hash arbitrary length device ID to 32 bytes using Blake3
  ///
  /// Consistent with Rust side, ensures device ID is always 32 bytes
  static Uint8List hashDeviceId(String deviceId) {
    final hash = blake3.blake3(utf8.encode(deviceId), 32);
    return Uint8List.fromList(hash);
  }

  /// Create 32-byte device ID from string
  ///
  /// If input is already a 32-byte hex string, decode directly
  /// Otherwise use Blake3 hash
  static Uint8List deviceIdFromString(String input) {
    // Try to parse as hex
    if (input.length == 64) {
      try {
        final bytes = <int>[];
        for (int i = 0; i < input.length; i += 2) {
          bytes.add(int.parse(input.substring(i, i + 2), radix: 16));
        }
        if (bytes.length == 32) {
          return Uint8List.fromList(bytes);
        }
      } catch (_) {
        // Not valid hex, continue with hash
      }
    }

    // Use Blake3 hash
    return hashDeviceId(input);
  }

  /// Convert 32-byte device ID to hex string
  static String deviceIdToHex(Uint8List deviceId) {
    if (deviceId.length != 32) {
      throw ArgumentError('Device ID must be 32 bytes');
    }
    return deviceId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Validate if device ID is valid (32 bytes)
  static bool isValidDeviceId(Uint8List deviceId) {
    return deviceId.length == 32;
  }

  /// Compare two device IDs lexicographically
  ///
  /// Returns:
  /// - negative: id1 < id2
  /// - 0: id1 == id2
  /// - positive: id1 > id2
  static int compareDeviceIds(Uint8List id1, Uint8List id2) {
    final minLen = id1.length < id2.length ? id1.length : id2.length;
    for (int i = 0; i < minLen; i++) {
      if (id1[i] < id2[i]) return -1;
      if (id1[i] > id2[i]) return 1;
    }
    return id1.length.compareTo(id2.length);
  }

  /// Generate random device ID (for testing)
  static Uint8List generateRandomDeviceId() {
    final random =
        List.generate(32, (_) => DateTime.now().microsecondsSinceEpoch % 256);
    return Uint8List.fromList(random);
  }

  /// Check password strength
  ///
  /// Returns:
  /// - 0: weak password (< 8 characters)
  /// - 1: medium password (8-15 characters)
  /// - 2: strong password (>= 16 characters)
  static int checkPasswordStrength(String password) {
    if (password.length < 8) return 0;
    if (password.length < 16) return 1;
    return 2;
  }

  /// Securely clear sensitive data
  ///
  /// Note: Dart's garbage collection may not immediately clear memory
  /// This is a best-effort clearing
  static void clearSensitiveData(Uint8List data) {
    for (int i = 0; i < data.length; i++) {
      data[i] = 0;
    }
  }

  /// Convert byte array to Base64 (URL safe)
  static String toBase64Url(Uint8List bytes) {
    return base64Url.encode(bytes);
  }

  /// Decode byte array from Base64 (URL safe)
  static Uint8List fromBase64Url(String encoded) {
    return Uint8List.fromList(base64Url.decode(encoded));
  }
}

/// SAE error type
class SaeException implements Exception {
  final String message;
  final SaeErrorType type;

  SaeException(this.message, this.type);

  @override
  String toString() => 'SaeException: $message (type: $type)';
}

/// SAE error type enum
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

/// SAE state enum
enum SaeState {
  nothing,
  committed,
  confirmed,
  accepted,
}

/// SAE configuration
class SaeConfig {
  /// Maximum PWE iteration count
  final int maxPweLoop;

  /// PWE offset iteration count
  final int pweOffsetIterations;

  /// Maximum sync retry count
  final int maxSync;

  /// Elliptic curve group ID
  final int groupId;

  const SaeConfig({
    this.maxPweLoop = 40,
    this.pweOffsetIterations = 8,
    this.maxSync = 3,
    this.groupId = 19, // Curve25519
  });

  /// Default configuration
  static const SaeConfig defaultConfig = SaeConfig();

  /// Fast configuration (for testing, reduced iterations)
  static const SaeConfig fastConfig = SaeConfig(
    maxPweLoop: 10,
    pweOffsetIterations: 4,
  );
}
