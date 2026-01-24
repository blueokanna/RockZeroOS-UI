/// HLS Bulletproofs Authentication Service
///
/// Production-grade implementation using Rust FFI for complete Bulletproofs support.
/// This ensures perfect compatibility between Flutter and Rust ZKP operations.
///
/// ## Security Features
/// - Complete Bulletproofs range proofs (not simplified)
/// - Schnorr proofs for password knowledge
/// - PBKDF key stretching (100,000 iterations)
/// - Merlin transcript for Fiat-Shamir transform
/// - Replay attack prevention (timestamp + nonce)
///
/// ## Usage
/// ```dart
/// final auth = HlsBulletproofAuth();
/// auth.initialize();
///
/// // Register a password (during user registration)
/// final registration = auth.registerPassword('MySecureP@ssw0rd!');
///
/// // Generate proof for HLS segment access
/// final proofBase64 = auth.generateProof(
///   'MySecureP@ssw0rd!',
///   registration,
///   context: 'hls_segment_access',
/// );
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'zkp_ffi.dart';

// Re-export types from FFI
export 'zkp_ffi.dart'
    show
        PasswordRegistration,
        SchnorrProof,
        BoundStrengthProof,
        EnhancedPasswordProof,
        ZkpFfiError;

/// HLS Bulletproofs Authentication Context
///
/// Provides methods to:
/// 1. Register a password (generate PasswordRegistration for storage)
/// 2. Generate enhanced password proofs with full Bulletproofs for authentication
///
/// This implementation uses Rust FFI to ensure complete compatibility
/// with the Rust server's Bulletproofs verification.
class HlsBulletproofAuth {
  RockZeroZkpFfi? _ffi;
  bool _initialized = false;
  String? _lastError;

  /// Get the last error message (if any)
  String? get lastError => _lastError;

  /// Check if FFI is initialized
  bool get isInitialized => _initialized;

  /// Initialize the FFI interface
  ///
  /// [libraryPath] - Optional path to the native library.
  /// If not provided, the library will be loaded from the default location.
  ///
  /// Returns true if initialization was successful.
  bool initialize({String? libraryPath}) {
    if (_initialized) {
      return true;
    }

    try {
      _ffi = RockZeroZkpFfi(libraryPath: libraryPath);
      _initialized = true;
      _lastError = null;
      debugPrint('[HlsBulletproofAuth] FFI initialized successfully');
      debugPrint('[HlsBulletproofAuth] Library version: ${_ffi!.version}');
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('[HlsBulletproofAuth] FFI initialization failed: $e');
      return false;
    }
  }

  /// Initialize with automatic library path detection
  ///
  /// Attempts to find the native library in common locations.
  bool initializeAuto() {
    // Try common library paths
    final paths = _getLibraryPaths();

    for (final path in paths) {
      if (File(path).existsSync()) {
        debugPrint('[HlsBulletproofAuth] Found library at: $path');
        if (initialize(libraryPath: path)) {
          return true;
        }
      }
    }

    // Try default loading (system path)
    return initialize();
  }

  /// Get platform-specific library paths to search
  List<String> _getLibraryPaths() {
    final paths = <String>[];

    if (Platform.isWindows) {
      paths.addAll([
        'rockzero_zkp_ffi.dll',
        'lib/rockzero_zkp_ffi.dll',
        'assets/rockzero_zkp_ffi.dll',
        '../target/release/rockzero_zkp_ffi.dll',
        '../target/debug/rockzero_zkp_ffi.dll',
      ]);
    } else if (Platform.isLinux || Platform.isAndroid) {
      paths.addAll([
        'librockzero_zkp_ffi.so',
        'lib/librockzero_zkp_ffi.so',
        'assets/librockzero_zkp_ffi.so',
        '../target/release/librockzero_zkp_ffi.so',
        '../target/debug/librockzero_zkp_ffi.so',
      ]);
    } else if (Platform.isMacOS) {
      paths.addAll([
        'librockzero_zkp_ffi.dylib',
        'lib/librockzero_zkp_ffi.dylib',
        'assets/librockzero_zkp_ffi.dylib',
        '../target/release/librockzero_zkp_ffi.dylib',
        '../target/debug/librockzero_zkp_ffi.dylib',
      ]);
    }

    return paths;
  }

  /// Ensure FFI is initialized
  void _ensureInitialized() {
    if (!_initialized) {
      throw ZkpFfiError(
        'HlsBulletproofAuth not initialized. Call initialize() first.',
      );
    }
  }

  /// Register a password and generate PasswordRegistration
  ///
  /// This is called during user registration. The PasswordRegistration
  /// should be stored on the server for future ZKP verification.
  ///
  /// Throws [ZkpFfiError] if password is too weak or FFI not initialized.
  PasswordRegistration registerPassword(String password) {
    _ensureInitialized();

    debugPrint('[HlsBulletproofAuth] Registering password...');

    try {
      final registration = _ffi!.registerPassword(password);
      debugPrint('[HlsBulletproofAuth] ✅ Password registered successfully');
      return registration;
    } catch (e) {
      debugPrint('[HlsBulletproofAuth] ❌ Registration failed: $e');
      rethrow;
    }
  }

  /// Generate enhanced password proof with full Bulletproofs range proof
  ///
  /// This generates a complete ZKP that includes:
  /// - Schnorr proof of password knowledge
  /// - Bulletproofs range proof for password entropy
  /// - Replay attack protection (timestamp + nonce)
  /// - Context binding
  ///
  /// [password] - The user's password
  /// [registration] - The PasswordRegistration from server
  /// [context] - Context string (default: "hls_segment_access")
  ///
  /// Returns the proof as a Base64-encoded string ready for transmission.
  ///
  /// Throws [ZkpFfiError] if password doesn't match registration or FFI not initialized.
  String generateProof(
    String password,
    PasswordRegistration registration, {
    String context = 'hls_segment_access',
  }) {
    _ensureInitialized();

    debugPrint('[HlsBulletproofAuth] Generating enhanced Bulletproofs proof...');
    debugPrint('[HlsBulletproofAuth]   Context: $context');

    try {
      final proofBase64 = _ffi!.generateEnhancedProof(
        password,
        registration,
        context: context,
      );

      debugPrint('[HlsBulletproofAuth] ✅ Enhanced Bulletproofs proof generated');
      debugPrint(
          '[HlsBulletproofAuth]   Proof size: ${proofBase64.length} chars (base64)');

      return proofBase64;
    } catch (e) {
      debugPrint('[HlsBulletproofAuth] ❌ Proof generation failed: $e');
      rethrow;
    }
  }

  /// Verify enhanced password proof (for testing purposes)
  ///
  /// Note: In production, verification is done on the Rust server.
  /// This method is provided for local testing only.
  ///
  /// [proofBase64] - The Base64-encoded proof
  /// [registration] - The PasswordRegistration
  /// [expectedContext] - Expected context string
  /// [maxAgeSeconds] - Maximum proof age in seconds
  ///
  /// Returns true if the proof is valid.
  bool verifyProof(
    String proofBase64,
    PasswordRegistration registration, {
    String expectedContext = 'hls_segment_access',
    int maxAgeSeconds = 300,
  }) {
    _ensureInitialized();

    debugPrint('[HlsBulletproofAuth] Verifying Bulletproofs proof...');

    try {
      final valid = _ffi!.verifyEnhancedProof(
        proofBase64,
        registration,
        expectedContext: expectedContext,
        maxAgeSeconds: maxAgeSeconds,
      );

      debugPrint('[HlsBulletproofAuth] Verification result: $valid');
      return valid;
    } catch (e) {
      debugPrint('[HlsBulletproofAuth] ❌ Verification failed: $e');
      return false;
    }
  }

  /// Calculate password entropy in bits
  int calculatePasswordEntropy(String password) {
    _ensureInitialized();
    return _ffi!.calculateEntropy(password);
  }

  /// Get minimum required password entropy in bits
  int get minEntropyBits {
    _ensureInitialized();
    return _ffi!.minEntropyBits;
  }

  /// Get library version
  String get version {
    _ensureInitialized();
    return _ffi!.version;
  }

  /// Clear used nonces (for testing purposes)
  void clearNonces() {
    _ensureInitialized();
    _ffi!.clearNonces();
  }
}

/// Wrapper for proof data with additional metadata
///
/// This class wraps the Base64-encoded proof with additional
/// information useful for debugging and logging.
class HlsProofResult {
  /// The Base64-encoded proof ready for transmission
  final String proofBase64;

  /// The context used for the proof
  final String context;

  /// The timestamp when the proof was generated
  final DateTime generatedAt;

  HlsProofResult({
    required this.proofBase64,
    required this.context,
    required this.generatedAt,
  });

  /// Get the decoded proof structure
  EnhancedPasswordProof get proof => EnhancedPasswordProof.fromBase64(proofBase64);

  /// Get the proof size in bytes
  int get sizeBytes => base64Decode(proofBase64).length;

  @override
  String toString() {
    return 'HlsProofResult(context: $context, size: $sizeBytes bytes, generated: $generatedAt)';
  }
}
