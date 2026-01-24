/// RockZero ZKP FFI Bindings
///
/// Production-grade FFI bindings for Bulletproofs Zero-Knowledge Proofs.
/// This library provides Dart bindings to the Rust ZKP implementation.
///
/// ## Features
/// - Complete Bulletproofs range proofs (not simplified)
/// - Schnorr proofs for password knowledge
/// - PBKDF key stretching (100,000 iterations)
/// - Merlin transcript for Fiat-Shamir transform
/// - Replay attack prevention (timestamp + nonce)
///
/// ## Usage
/// ```dart
/// final zkp = RockZeroZkpFfi();
///
/// // Register a password
/// final registration = zkp.registerPassword('MySecureP@ssw0rd!');
///
/// // Generate proof for authentication
/// final proof = zkp.generateEnhancedProof(
///   'MySecureP@ssw0rd!',
///   registration,
///   context: 'hls_segment_access',
/// );
/// ```
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// FFI Result structure matching Rust FfiResult
final class FfiResult extends Struct {
  @Int32()
  external int success;

  external Pointer<Utf8> data;

  external Pointer<Utf8> error;
}

/// Native function type definitions
typedef RzZkpRegisterPasswordNative = FfiResult Function(Pointer<Utf8> password);
typedef RzZkpRegisterPassword = FfiResult Function(Pointer<Utf8> password);

typedef RzZkpGenerateEnhancedProofNative = FfiResult Function(
  Pointer<Utf8> password,
  Pointer<Utf8> registrationJson,
  Pointer<Utf8> context,
);
typedef RzZkpGenerateEnhancedProof = FfiResult Function(
  Pointer<Utf8> password,
  Pointer<Utf8> registrationJson,
  Pointer<Utf8> context,
);

typedef RzZkpVerifyEnhancedProofNative = FfiResult Function(
  Pointer<Utf8> proofBase64,
  Pointer<Utf8> registrationJson,
  Pointer<Utf8> expectedContext,
  Int64 maxAgeSeconds,
);
typedef RzZkpVerifyEnhancedProof = FfiResult Function(
  Pointer<Utf8> proofBase64,
  Pointer<Utf8> registrationJson,
  Pointer<Utf8> expectedContext,
  int maxAgeSeconds,
);

typedef RzZkpCalculateEntropyNative = Int64 Function(Pointer<Utf8> password);
typedef RzZkpCalculateEntropy = int Function(Pointer<Utf8> password);

typedef RzZkpMinEntropyBitsNative = Int64 Function();
typedef RzZkpMinEntropyBits = int Function();

typedef RzZkpFreeStringNative = Void Function(Pointer<Utf8> ptr);
typedef RzZkpFreeString = void Function(Pointer<Utf8> ptr);

typedef RzZkpFreeResultNative = Void Function(FfiResult result);
typedef RzZkpFreeResult = void Function(FfiResult result);

typedef RzZkpClearNoncesNative = Void Function();
typedef RzZkpClearNonces = void Function();

typedef RzZkpVersionNative = Pointer<Utf8> Function();
typedef RzZkpVersion = Pointer<Utf8> Function();

/// Password Registration data
///
/// Contains the Pedersen commitment and salt needed for ZKP verification.
/// This structure matches the Rust PasswordRegistration in zkp.rs
class PasswordRegistration {
  /// The Pedersen commitment to the password: C = g^password * h^blinding
  final String commitment;

  /// Salt used for password derivation (randomly generated during registration)
  final String salt;

  PasswordRegistration({
    required this.commitment,
    required this.salt,
  });

  factory PasswordRegistration.fromJson(Map<String, dynamic> json) {
    return PasswordRegistration(
      commitment: json['commitment'] as String,
      salt: json['salt'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'commitment': commitment,
        'salt': salt,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// Schnorr proof data
class SchnorrProof {
  final String aPoint;
  final String challenge;
  final String responsePassword;
  final String responseBlinding;

  SchnorrProof({
    required this.aPoint,
    required this.challenge,
    required this.responsePassword,
    required this.responseBlinding,
  });

  factory SchnorrProof.fromJson(Map<String, dynamic> json) {
    return SchnorrProof(
      aPoint: json['a_point'] as String,
      challenge: json['challenge'] as String,
      responsePassword: json['response_password'] as String,
      responseBlinding: json['response_blinding'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'a_point': aPoint,
        'challenge': challenge,
        'response_password': responsePassword,
        'response_blinding': responseBlinding,
      };
}

/// Bound strength proof with Bulletproofs range proof
class BoundStrengthProof {
  final String entropyValueCommitment;
  final String rangeProof;

  BoundStrengthProof({
    required this.entropyValueCommitment,
    required this.rangeProof,
  });

  factory BoundStrengthProof.fromJson(Map<String, dynamic> json) {
    return BoundStrengthProof(
      entropyValueCommitment: json['entropy_value_commitment'] as String,
      rangeProof: json['range_proof'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'entropy_value_commitment': entropyValueCommitment,
        'range_proof': rangeProof,
      };
}

/// Enhanced password proof with full Bulletproofs range proof
///
/// This is the complete, production-grade proof structure that includes:
/// - Schnorr proof of password knowledge
/// - Bulletproofs range proof for password entropy
/// - Replay attack protection (timestamp + nonce)
/// - Context binding
class EnhancedPasswordProof {
  final SchnorrProof schnorrProof;
  final BoundStrengthProof strengthProof;
  final int timestamp;
  final String nonce;
  final String context;

  EnhancedPasswordProof({
    required this.schnorrProof,
    required this.strengthProof,
    required this.timestamp,
    required this.nonce,
    required this.context,
  });

  factory EnhancedPasswordProof.fromJson(Map<String, dynamic> json) {
    return EnhancedPasswordProof(
      schnorrProof: SchnorrProof.fromJson(json['schnorr_proof']),
      strengthProof: BoundStrengthProof.fromJson(json['strength_proof']),
      timestamp: json['timestamp'] as int,
      nonce: json['nonce'] as String,
      context: json['context'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'schnorr_proof': schnorrProof.toJson(),
        'strength_proof': strengthProof.toJson(),
        'timestamp': timestamp,
        'nonce': nonce,
        'context': context,
      };

  /// Serialize to Base64 encoded JSON for transmission
  String toBase64() {
    final jsonStr = jsonEncode(toJson());
    return base64Encode(utf8.encode(jsonStr));
  }

  /// Deserialize from Base64 encoded JSON
  factory EnhancedPasswordProof.fromBase64(String encoded) {
    final jsonStr = utf8.decode(base64Decode(encoded));
    return EnhancedPasswordProof.fromJson(jsonDecode(jsonStr));
  }
}

/// ZKP FFI Error
class ZkpFfiError implements Exception {
  final String message;

  ZkpFfiError(this.message);

  @override
  String toString() => 'ZkpFfiError: $message';
}

/// RockZero ZKP FFI Interface
///
/// Provides Dart bindings to the Rust Bulletproofs implementation.
/// This ensures complete compatibility between Flutter and Rust ZKP operations.
class RockZeroZkpFfi {
  late final DynamicLibrary _lib;

  // Function pointers
  late final RzZkpRegisterPassword _registerPassword;
  late final RzZkpGenerateEnhancedProof _generateEnhancedProof;
  late final RzZkpVerifyEnhancedProof _verifyEnhancedProof;
  late final RzZkpCalculateEntropy _calculateEntropy;
  late final RzZkpMinEntropyBits _minEntropyBits;
  late final RzZkpFreeString _freeString;
  late final RzZkpClearNonces _clearNonces;
  late final RzZkpVersion _version;

  /// Create a new ZKP FFI instance
  ///
  /// [libraryPath] - Optional path to the native library.
  /// If not provided, the library will be loaded from the default location.
  RockZeroZkpFfi({String? libraryPath}) {
    _lib = _loadLibrary(libraryPath);
    _bindFunctions();
  }

  /// Load the native library
  DynamicLibrary _loadLibrary(String? libraryPath) {
    if (libraryPath != null) {
      return DynamicLibrary.open(libraryPath);
    }

    // Platform-specific library names
    if (Platform.isWindows) {
      return DynamicLibrary.open('rockzero_zkp_ffi.dll');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('librockzero_zkp_ffi.so');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('librockzero_zkp_ffi.dylib');
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('librockzero_zkp_ffi.so');
    } else if (Platform.isIOS) {
      // iOS uses static linking
      return DynamicLibrary.process();
    } else {
      throw ZkpFfiError('Unsupported platform: ${Platform.operatingSystem}');
    }
  }

  /// Bind native functions
  void _bindFunctions() {
    _registerPassword = _lib
        .lookup<NativeFunction<RzZkpRegisterPasswordNative>>(
            'rz_zkp_register_password')
        .asFunction();

    _generateEnhancedProof = _lib
        .lookup<NativeFunction<RzZkpGenerateEnhancedProofNative>>(
            'rz_zkp_generate_enhanced_proof')
        .asFunction();

    _verifyEnhancedProof = _lib
        .lookup<NativeFunction<RzZkpVerifyEnhancedProofNative>>(
            'rz_zkp_verify_enhanced_proof')
        .asFunction();

    _calculateEntropy = _lib
        .lookup<NativeFunction<RzZkpCalculateEntropyNative>>(
            'rz_zkp_calculate_entropy')
        .asFunction();

    _minEntropyBits = _lib
        .lookup<NativeFunction<RzZkpMinEntropyBitsNative>>(
            'rz_zkp_min_entropy_bits')
        .asFunction();

    _freeString = _lib
        .lookup<NativeFunction<RzZkpFreeStringNative>>('rz_zkp_free_string')
        .asFunction();

    _clearNonces = _lib
        .lookup<NativeFunction<RzZkpClearNoncesNative>>('rz_zkp_clear_nonces')
        .asFunction();

    _version = _lib
        .lookup<NativeFunction<RzZkpVersionNative>>('rz_zkp_version')
        .asFunction();
  }

  /// Process FFI result and free memory
  String _processResult(FfiResult result) {
    try {
      if (result.success == 1) {
        final data = result.data.toDartString();
        return data;
      } else {
        final error = result.error.toDartString();
        throw ZkpFfiError(error);
      }
    } finally {
      // Free the result strings
      if (result.data != nullptr) {
        _freeString(result.data);
      }
      if (result.error != nullptr) {
        _freeString(result.error);
      }
    }
  }

  /// Register a password and generate PasswordRegistration
  ///
  /// This is called during user registration. The PasswordRegistration
  /// should be stored on the server for future ZKP verification.
  ///
  /// Throws [ZkpFfiError] if password is too weak.
  PasswordRegistration registerPassword(String password) {
    final passwordPtr = password.toNativeUtf8();
    try {
      final result = _registerPassword(passwordPtr);
      final json = _processResult(result);
      return PasswordRegistration.fromJson(jsonDecode(json));
    } finally {
      calloc.free(passwordPtr);
    }
  }

  /// Generate enhanced password proof with full Bulletproofs range proof
  ///
  /// This generates a complete ZKP that includes:
  /// - Schnorr proof of password knowledge
  /// - Bulletproofs range proof for password entropy
  /// - Replay attack protection
  ///
  /// [password] - The user's password
  /// [registration] - The PasswordRegistration from server
  /// [context] - Context string (default: "hls_segment_access")
  ///
  /// Returns the proof as a Base64-encoded string ready for transmission.
  ///
  /// Throws [ZkpFfiError] if password doesn't match registration.
  String generateEnhancedProof(
    String password,
    PasswordRegistration registration, {
    String context = 'hls_segment_access',
  }) {
    final passwordPtr = password.toNativeUtf8();
    final registrationPtr = registration.toJsonString().toNativeUtf8();
    final contextPtr = context.toNativeUtf8();

    try {
      final result = _generateEnhancedProof(
        passwordPtr,
        registrationPtr,
        contextPtr,
      );
      return _processResult(result);
    } finally {
      calloc.free(passwordPtr);
      calloc.free(registrationPtr);
      calloc.free(contextPtr);
    }
  }

  /// Verify enhanced password proof
  ///
  /// [proofBase64] - The Base64-encoded proof
  /// [registration] - The PasswordRegistration from server
  /// [expectedContext] - Expected context string
  /// [maxAgeSeconds] - Maximum proof age in seconds
  ///
  /// Returns true if the proof is valid.
  ///
  /// Throws [ZkpFfiError] if verification fails.
  bool verifyEnhancedProof(
    String proofBase64,
    PasswordRegistration registration, {
    String expectedContext = 'hls_segment_access',
    int maxAgeSeconds = 300,
  }) {
    final proofPtr = proofBase64.toNativeUtf8();
    final registrationPtr = registration.toJsonString().toNativeUtf8();
    final contextPtr = expectedContext.toNativeUtf8();

    try {
      final result = _verifyEnhancedProof(
        proofPtr,
        registrationPtr,
        contextPtr,
        maxAgeSeconds,
      );
      final data = _processResult(result);
      return data == 'true';
    } finally {
      calloc.free(proofPtr);
      calloc.free(registrationPtr);
      calloc.free(contextPtr);
    }
  }

  /// Calculate password entropy in bits
  int calculateEntropy(String password) {
    final passwordPtr = password.toNativeUtf8();
    try {
      return _calculateEntropy(passwordPtr);
    } finally {
      calloc.free(passwordPtr);
    }
  }

  /// Get minimum required password entropy in bits
  int get minEntropyBits => _minEntropyBits();

  /// Clear used nonces (for testing purposes)
  void clearNonces() => _clearNonces();

  /// Get library version
  String get version => _version().toDartString();
}
