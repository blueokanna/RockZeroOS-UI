import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:thirds/blake3.dart' as blake3;

import '../bulletproofs_ffi.dart';

class PasswordRegistration {
  final String commitment;

  final String salt;

  PasswordRegistration({
    required this.commitment,
    required this.salt,
  });

  factory PasswordRegistration.fromJson(Map<String, dynamic> json) {
    return PasswordRegistration(
      commitment: json['commitment'] as String? ?? '',
      salt: json['salt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'commitment': commitment,
        'salt': salt,
      };
}

class _SchnorrProof {
  final String aPoint;
  final String challenge;
  final String responsePassword;
  final String responseBlinding;

  _SchnorrProof({
    required this.aPoint,
    required this.challenge,
    required this.responsePassword,
    required this.responseBlinding,
  });

  Map<String, dynamic> toJson() => {
        'a_point': aPoint,
        'challenge': challenge,
        'response_password': responsePassword,
        'response_blinding': responseBlinding,
      };
}

class _BoundStrengthProof {
  final String entropyValueCommitment;
  final String rangeProof;

  _BoundStrengthProof({
    required this.entropyValueCommitment,
    required this.rangeProof,
  });

  Map<String, dynamic> toJson() => {
        'entropy_value_commitment': entropyValueCommitment,
        'range_proof': rangeProof,
      };
}

class _EnhancedPasswordProof {
  final _SchnorrProof schnorrProof;
  final _BoundStrengthProof strengthProof;
  final int timestamp;
  final String nonce;
  final String context;

  _EnhancedPasswordProof({
    required this.schnorrProof,
    required this.strengthProof,
    required this.timestamp,
    required this.nonce,
    required this.context,
  });

  Map<String, dynamic> toJson() => {
        'schnorr_proof': schnorrProof.toJson(),
        'strength_proof': strengthProof.toJson(),
        'timestamp': timestamp,
        'nonce': nonce,
        'context': context,
      };
}

class HlsBulletproofAuth {
  static const String _passwordDomain = 'RockZero-Password-ZKP-v1';
  static const String _blindingDomain = 'RockZero-Blinding-Derive-v1';
  static const int _pbkdfIterations = 100000;
  static const int _minPasswordEntropyBits = 28;

  final BulletproofsFFI _ffi = BulletproofsFFI.instance;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  bool initializeAuto() {
    try {
      _ffi.initialize();
      _initialized = true;
      debugPrint('[HlsBulletproofAuth] Initialized with FFI support');
    } catch (e) {
      _initialized = true;
      debugPrint(
          '[HlsBulletproofAuth] Initialized in pure-Dart mode (FFI unavailable: $e)');
    }
    return _initialized;
  }

  PasswordRegistration registerPassword(String password) {
    final salt = _generateSalt();

    final passwordScalar = _passwordToScalar(password, salt);

    final blinding = _deriveBlinding(password, salt);

    final commitment = _pedersenCommit(passwordScalar, blinding);

    return PasswordRegistration(
      commitment: base64Encode(commitment),
      salt: base64Encode(salt),
    );
  }

  String generateProof(
    String password,
    PasswordRegistration registration, {
    String context = 'hls_segment_access',
  }) {
    final salt = base64Decode(registration.salt);

    final passwordScalar = _passwordToScalar(password, salt);
    final blinding = _deriveBlinding(password, salt);

    final schnorr = _generateSchnorrProof(passwordScalar, blinding);

    final entropy = calculatePasswordEntropy(password);

    final strengthProof =
        _generateBoundStrengthProof(entropy, _minPasswordEntropyBits);

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final nonce = _generateNonce();

    final proof = _EnhancedPasswordProof(
      schnorrProof: schnorr,
      strengthProof: strengthProof,
      timestamp: timestamp,
      nonce: nonce,
      context: context,
    );

    final jsonStr = jsonEncode(proof.toJson());
    return base64Encode(utf8.encode(jsonStr));
  }

  int calculatePasswordEntropy(String password) {
    if (password.isEmpty) return 0;

    int charsetSize = 0;
    bool hasLower = false,
        hasUpper = false,
        hasDigit = false,
        hasSpecial = false;

    for (final c in password.codeUnits) {
      if (c >= 0x61 && c <= 0x7A) {
        hasLower = true;
      } else if (c >= 0x41 && c <= 0x5A) {
        hasUpper = true;
      } else if (c >= 0x30 && c <= 0x39) {
        hasDigit = true;
      } else {
        hasSpecial = true;
      }
    }

    if (hasLower) charsetSize += 26;
    if (hasUpper) charsetSize += 26;
    if (hasDigit) charsetSize += 10;
    if (hasSpecial) charsetSize += 32;

    if (charsetSize == 0) charsetSize = 1;

    final log2Charset = log(charsetSize) / log(2);
    final rawEntropy = password.length * log2Charset;
    return (rawEntropy * 0.7).floor();
  }

  Uint8List _passwordToScalar(String password, Uint8List salt) {
    final input = Uint8List.fromList([
      ...utf8.encode(_passwordDomain),
      ...utf8.encode(password),
      ...salt,
    ]);

    var hash = Uint8List.fromList(blake3.blake3(input, 32));

    for (int i = 0; i < _pbkdfIterations; i++) {
      hash = Uint8List.fromList(blake3.blake3([...hash, ...salt], 32));
    }
    return hash;
  }

  Uint8List _deriveBlinding(String password, Uint8List salt) {
    final input = Uint8List.fromList([
      ...utf8.encode(_blindingDomain),
      ...utf8.encode(password),
      ...salt,
    ]);
    return Uint8List.fromList(blake3.blake3(input, 32));
  }

  Uint8List _pedersenCommit(Uint8List passwordScalar, Uint8List blinding) {
    final gHash =
        Uint8List.fromList(blake3.blake3([0x67, ...passwordScalar], 32));
    final hHash = Uint8List.fromList(blake3.blake3([0x68, ...blinding], 32));

    final result = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      result[i] = gHash[i] ^ hHash[i];
    }
    return result;
  }

  _SchnorrProof _generateSchnorrProof(
      Uint8List passwordScalar, Uint8List blinding) {
    final kPassword = _randomBytes(32);
    final kBlinding = _randomBytes(32);

    final aPassword =
        Uint8List.fromList(blake3.blake3([0x67, ...kPassword], 32));
    final aBlinding =
        Uint8List.fromList(blake3.blake3([0x68, ...kBlinding], 32));

    final aPoint = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      aPoint[i] = aPassword[i] ^ aBlinding[i];
    }

    final challenge = Uint8List.fromList(
        blake3.blake3([...aPoint, ...utf8.encode('schnorr-challenge')], 32));

    final responsePassword =
        _scalarAdd(kPassword, _scalarMul(challenge, passwordScalar));
    final responseBlinding =
        _scalarAdd(kBlinding, _scalarMul(challenge, blinding));

    return _SchnorrProof(
      aPoint: base64Encode(aPoint),
      challenge: base64Encode(challenge),
      responsePassword: base64Encode(responsePassword),
      responseBlinding: base64Encode(responseBlinding),
    );
  }

  _BoundStrengthProof _generateBoundStrengthProof(
      int entropyValue, int threshold) {
    if (_ffi.isInitialized && entropyValue >= threshold) {
      final nativeProof = _ffi.createRangeProofNative(entropyValue);
      if (nativeProof != null) {
        return _BoundStrengthProof(
          entropyValueCommitment: nativeProof.commitment,
          rangeProof: nativeProof.proof,
        );
      }
    }

    final valueBytes = Uint8List(8)
      ..buffer.asByteData().setUint64(0, entropyValue, Endian.little);
    final blinding = _randomBytes(32);

    final commitment =
        Uint8List.fromList(blake3.blake3([...valueBytes, ...blinding], 32));

    final proofData = <String, dynamic>{
      'bits': 64,
      'commitment': base64Encode(commitment),
      'blinding_hash':
          base64Encode(Uint8List.fromList(blake3.blake3(blinding, 32))),
      'value_above_threshold': entropyValue >= threshold,
    };

    return _BoundStrengthProof(
      entropyValueCommitment: base64Encode(commitment),
      rangeProof: base64Encode(utf8.encode(jsonEncode(proofData))),
    );
  }

  String _generateNonce() {
    final bytes = _randomBytes(16);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uint8List _generateSalt() => _randomBytes(32);

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List.generate(length, (_) => random.nextInt(256)));
  }

  Uint8List _scalarAdd(Uint8List a, Uint8List b) {
    final result = Uint8List(32);
    int carry = 0;
    for (int i = 0; i < 32; i++) {
      final sum = a[i] + b[i] + carry;
      result[i] = sum & 0xFF;
      carry = sum >> 8;
    }
    return result;
  }

  Uint8List _scalarMul(Uint8List a, Uint8List b) {
    return Uint8List.fromList(blake3.blake3([...a, ...b], 32));
  }
}
