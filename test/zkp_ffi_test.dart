/// ZKP FFI Integration Test
///
/// Tests the FFI bindings between Flutter and Rust Bulletproofs implementation.
/// These tests require the native library (rockzero_zkp_ffi.dll) to be available.
///
/// To run these tests:
/// 1. Build the Rust FFI library: cargo build --release --package rockzero-zkp-ffi
/// 2. Copy the DLL to the test directory or set PATH
/// 3. Run: flutter test test/zkp_ffi_test.dart
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockzero/services/zkp/hls_bulletproof_auth.dart';
import 'package:rockzero/services/zkp/zkp_ffi.dart';

void main() {
  // Skip tests if running in CI or if native library is not available
  final bool isNativeLibraryAvailable = _checkNativeLibrary();

  group('ZKP FFI Integration Tests', () {
    late HlsBulletproofAuth auth;

    setUpAll(() {
      if (!isNativeLibraryAvailable) {
        print('⚠️  Native library not found. Skipping FFI tests.');
        print('   Build with: cargo build --release --package rockzero-zkp-ffi');
        return;
      }
    });

    setUp(() {
      if (!isNativeLibraryAvailable) return;
      auth = HlsBulletproofAuth();
    });

    test('Initialize FFI with auto-detection', () {
      if (!isNativeLibraryAvailable) {
        markTestSkipped('Native library not available');
        return;
      }

      final result = auth.initializeAuto();
      expect(result, isTrue, reason: 'FFI should initialize successfully');
      expect(auth.isInitialized, isTrue);
      print('✅ FFI initialized successfully');
      print('   Version: ${auth.version}');
    }, skip: !isNativeLibraryAvailable);

    test('Register password successfully', () {
      if (!isNativeLibraryAvailable) {
        markTestSkipped('Native library not available');
        return;
      }

      expect(auth.initializeAuto(), isTrue);

      // Use a strong password
      const password = 'StrongP@ssw0rd123!';
      final registration = auth.registerPassword(password);

      expect(registration.commitment, isNotEmpty);
      expect(registration.salt, isNotEmpty);
      print('✅ Password registered successfully');
      print('   Commitment: ${registration.commitment.substring(0, 20)}...');
      print('   Salt: ${registration.salt.substring(0, 20)}...');
    }, skip: !isNativeLibraryAvailable);

    test('Weak password is rejected', () {
      if (!isNativeLibraryAvailable) {
        markTestSkipped('Native library not available');
        return;
      }

      expect(auth.initializeAuto(), isTrue);

      // Use a weak password
      const weakPassword = 'weak';

      expect(
        () => auth.registerPassword(weakPassword),
        throwsA(isA<ZkpFfiError>()),
        reason: 'Weak password should be rejected',
      );
      print('✅ Weak password correctly rejected');
    }, skip: !isNativeLibraryAvailable);

    test('Generate and verify enhanced proof', () {
      if (!isNativeLibraryAvailable) {
        markTestSkipped('Native library not available');
        return;
      }

      expect(auth.initializeAuto(), isTrue);

      const password = 'MySecureP@ssw0rd!';
      final registration = auth.registerPassword(password);

      // Generate proof
      final proofBase64 = auth.generateProof(
        password,
        registration,
        context: 'hls_segment_access',
      );

      expect(proofBase64, isNotEmpty);
      expect(proofBase64.length, greaterThan(100));
      print('✅ Enhanced Bulletproofs proof generated');
      print('   Proof size: ${proofBase64.length} chars (base64)');

      // Clear nonces for verification (since we're testing locally)
      auth.clearNonces();

      // Verify proof
      final isValid = auth.verifyProof(
        proofBase64,
        registration,
        expectedContext: 'hls_segment_access',
      );

      expect(isValid, isTrue, reason: 'Proof should be valid');
      print('✅ Proof verified successfully');
    }, skip: !isNativeLibraryAvailable);

    test('Wrong password fails verification', () {
      if (!isNativeLibraryAvailable) {
        markTestSkipped('Native library not available');
        return;
      }

      expect(auth.initializeAuto(), isTrue);

      const correctPassword = 'CorrectP@ssw0rd!';
      const wrongPassword = 'WrongP@ssw0rd!';

      final registration = auth.registerPassword(correctPassword);

      // Try to generate proof with wrong password
      expect(
        () => auth.generateProof(
          wrongPassword,
          registration,
          context: 'hls_segment_access',
        ),
        throwsA(isA<ZkpFfiError>()),
        reason: 'Wrong password should fail',
      );
      print('✅ Wrong password correctly rejected');
    }, skip: !isNativeLibraryAvailable);

    test('Context mismatch fails verification', () {
      if (!isNativeLibraryAvailable) {
        markTestSkipped('Native library not available');
        return;
      }

      expect(auth.initializeAuto(), isTrue);

      const password = 'SecureP@ssw0rd123!';
      final registration = auth.registerPassword(password);

      // Generate proof with one context
      final proofBase64 = auth.generateProof(
        password,
        registration,
        context: 'login',
      );

      auth.clearNonces();

      // Verify with different context
      final isValid = auth.verifyProof(
        proofBase64,
        registration,
        expectedContext: 'hls_segment_access',
      );

      expect(isValid, isFalse, reason: 'Context mismatch should fail');
      print('✅ Context mismatch correctly detected');
    }, skip: !isNativeLibraryAvailable);

    test('Replay attack is prevented', () {
      if (!isNativeLibraryAvailable) {
        markTestSkipped('Native library not available');
        return;
      }

      expect(auth.initializeAuto(), isTrue);

      const password = 'SecureP@ssw0rd!';
      final registration = auth.registerPassword(password);

      // Generate proof
      final proofBase64 = auth.generateProof(
        password,
        registration,
        context: 'test',
      );

      // First verification should succeed
      final isValid1 = auth.verifyProof(
        proofBase64,
        registration,
        expectedContext: 'test',
      );
      expect(isValid1, isTrue);

      // Second verification with same nonce should fail (replay attack)
      final isValid2 = auth.verifyProof(
        proofBase64,
        registration,
        expectedContext: 'test',
      );
      expect(isValid2, isFalse, reason: 'Replay attack should be detected');
      print('✅ Replay attack correctly prevented');
    }, skip: !isNativeLibraryAvailable);

    test('Password entropy calculation', () {
      if (!isNativeLibraryAvailable) {
        markTestSkipped('Native library not available');
        return;
      }

      expect(auth.initializeAuto(), isTrue);

      // Weak passwords
      expect(auth.calculatePasswordEntropy('a'), lessThan(auth.minEntropyBits));
      expect(auth.calculatePasswordEntropy('password'),
          lessThan(auth.minEntropyBits));

      // Strong passwords
      expect(auth.calculatePasswordEntropy('StrongP@ssw0rd123!'),
          greaterThanOrEqualTo(auth.minEntropyBits));

      print('✅ Entropy calculation working correctly');
      print('   Minimum required: ${auth.minEntropyBits} bits');
      print(
          '   "password" entropy: ${auth.calculatePasswordEntropy("password")} bits');
      print(
          '   "StrongP@ssw0rd123!" entropy: ${auth.calculatePasswordEntropy("StrongP@ssw0rd123!")} bits');
    }, skip: !isNativeLibraryAvailable);

    test('Proof structure contains all required fields', () {
      if (!isNativeLibraryAvailable) {
        markTestSkipped('Native library not available');
        return;
      }

      expect(auth.initializeAuto(), isTrue);

      const password = 'MySecureP@ssw0rd!';
      final registration = auth.registerPassword(password);

      final proofBase64 = auth.generateProof(
        password,
        registration,
        context: 'hls_segment_access',
      );

      // Decode and parse the proof
      final proof = EnhancedPasswordProof.fromBase64(proofBase64);

      // Verify structure
      expect(proof.schnorrProof.aPoint, isNotEmpty);
      expect(proof.schnorrProof.challenge, isNotEmpty);
      expect(proof.schnorrProof.responsePassword, isNotEmpty);
      expect(proof.schnorrProof.responseBlinding, isNotEmpty);

      expect(proof.strengthProof.entropyValueCommitment, isNotEmpty);
      expect(proof.strengthProof.rangeProof, isNotEmpty);

      expect(proof.timestamp, greaterThan(0));
      expect(proof.nonce, isNotEmpty);
      expect(proof.context, equals('hls_segment_access'));

      print('✅ Proof structure is complete');
      print('   - Schnorr proof: ✓');
      print('   - Bulletproofs range proof: ✓');
      print('   - Timestamp: ${proof.timestamp}');
      print('   - Nonce: ${proof.nonce.substring(0, 20)}...');
      print('   - Context: ${proof.context}');
    }, skip: !isNativeLibraryAvailable);
  });
}

/// Check if the native library is available
bool _checkNativeLibrary() {
  final paths = <String>[];

  if (Platform.isWindows) {
    paths.addAll([
      'rockzero_zkp_ffi.dll',
      '../target/release/rockzero_zkp_ffi.dll',
      '../target/debug/rockzero_zkp_ffi.dll',
      '../../target/release/rockzero_zkp_ffi.dll',
      '../../target/debug/rockzero_zkp_ffi.dll',
    ]);
  } else if (Platform.isLinux || Platform.isAndroid) {
    paths.addAll([
      'librockzero_zkp_ffi.so',
      '../target/release/librockzero_zkp_ffi.so',
      '../target/debug/librockzero_zkp_ffi.so',
    ]);
  } else if (Platform.isMacOS) {
    paths.addAll([
      'librockzero_zkp_ffi.dylib',
      '../target/release/librockzero_zkp_ffi.dylib',
      '../target/debug/librockzero_zkp_ffi.dylib',
    ]);
  }

  for (final path in paths) {
    if (File(path).existsSync()) {
      print('Found native library at: $path');
      return true;
    }
  }

  return false;
}
