import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// SAE (Simultaneous Authentication of Equals) client
///
/// Complete WPA3-SAE implementation for secure device authentication
class SaeClient {
  final Uint8List password;
  final Uint8List deviceIdSelf;
  final Uint8List deviceIdPeer;

  // Password Element (PWE)
  ECPoint? _pwe;

  // Local commit data
  BigInt? _rand;
  BigInt? _mask;
  BigInt? _scalar;
  ECPoint? _element;

  // Peer commit data
  BigInt? _peerScalar;
  ECPoint? _peerElement;

  // Derived keys
  Uint8List? _kck; // Key Confirmation Key
  Uint8List? _pmk; // Pairwise Master Key

  // State
  bool _committed = false;
  bool _confirmed = false;

  SaeClient({
    required this.password,
    required this.deviceIdSelf,
    required this.deviceIdPeer,
  });

  /// Generate Commit message (Base64 encoded)
  Map<String, dynamic> generateCommit() {
    if (_committed) {
      throw StateError('Already committed');
    }

    _pwe ??= _derivePasswordElement();

    final curve = ECCurve_secp256r1();
    final n = curve.n;

    _rand = _generateRandomScalar(n);
    _mask = _generateRandomScalar(n);

    _scalar = (_rand! + _mask!) % n;
    final gRand = curve.G * _rand!;
    final pweMask = _pwe! * _mask!;
    _element = (gRand! + pweMask!);

    _committed = true;

    return {
      'group_id': 19,
      'scalar': base64Encode(_scalarToBytes(_scalar!)),
      'element': base64Encode(_pointToBytes(_element!)),
    };
  }

  /// Process peer's Commit message (Base64 decoded)
  void processCommit(Map<String, dynamic> peerCommit) {
    if (!_committed) {
      throw StateError('Must generate own commit first');
    }

    final groupId = peerCommit['group_id'] as int;
    if (groupId != 19) {
      throw ArgumentError('Unsupported group ID: $groupId');
    }

    final peerScalarBytes = base64Decode(peerCommit['scalar'] as String);
    final peerElementBytes = base64Decode(peerCommit['element'] as String);

    _peerScalar = _bytesToScalar(peerScalarBytes);
    _peerElement = _bytesToPoint(peerElementBytes);

    if (_peerScalar == _scalar) {
      throw StateError('Peer scalar equals own scalar');
    }

    if (_peerElement == _element) {
      throw StateError('Peer element equals own element');
    }

    final sharedSecret = _computeSharedSecret();
    _deriveKeys(sharedSecret);
  }

  /// Generate Confirm message (Base64 encoded)
  Map<String, dynamic> generateConfirm() {
    if (!_committed || _kck == null) {
      throw StateError('Must process peer commit first');
    }

    final confirm = _computeConfirm(1);

    return {
      'send_confirm': 1,
      'confirm': base64Encode(confirm),
    };
  }

  /// Verify peer's Confirm message (Base64 decoded)
  void verifyConfirm(Map<String, dynamic> peerConfirm) {
    if (_kck == null) {
      throw StateError('Must process peer commit first');
    }

    final sendConfirm = peerConfirm['send_confirm'] as int;
    final peerConfirmBytes = base64Decode(peerConfirm['confirm'] as String);

    final expectedConfirm = _computePeerConfirm(sendConfirm);

    if (!_constantTimeCompare(peerConfirmBytes, expectedConfirm)) {
      throw StateError('Confirm verification failed');
    }

    _confirmed = true;
  }

  /// Get PMK
  Uint8List getPmk() {
    if (_pmk == null) {
      throw StateError('PMK not derived yet');
    }
    return _pmk!;
  }

  /// Check if authentication is complete
  bool isAuthenticated() => _confirmed;

  // ============ Private methods ============

  ECPoint _derivePasswordElement() {
    final curve = ECCurve_secp256r1();

    final input = Uint8List.fromList([
      ...password,
      ...deviceIdSelf,
      ...deviceIdPeer,
    ]);

    final digest = SHA256Digest();
    final hash = digest.process(input);

    // Use hash to derive a scalar and multiply by generator
    final scalar = _bytesToScalar(hash) % curve.n;
    final point = curve.G * scalar;

    if (point == null) {
      throw StateError('Failed to derive password element');
    }

    return point;
  }

  BigInt _generateRandomScalar(BigInt n) {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return _bytesToScalar(bytes) % n;
  }

  Uint8List _computeSharedSecret() {
    final pwePeerScalar = _pwe! * _peerScalar!;
    final temp = _peerElement! + (pwePeerScalar! * BigInt.from(-1));
    final k = temp! * _rand!;
    return _pointToBytes(k!);
  }

  void _deriveKeys(Uint8List sharedSecret) {
    final hkdf = HKDFKeyDerivator(SHA256Digest());

    final info = Uint8List.fromList([
      ..._scalarToBytes(_scalar!),
      ..._scalarToBytes(_peerScalar!),
      ..._pointToBytes(_element!),
      ..._pointToBytes(_peerElement!),
    ]);

    final salt = Uint8List.fromList(utf8.encode('rockzero-sae-v1'));

    hkdf.init(HkdfParameters(sharedSecret, 64, salt, info));

    final derivedKey = Uint8List(64);
    hkdf.deriveKey(null, 0, derivedKey, 0);

    _kck = derivedKey.sublist(0, 32);
    _pmk = derivedKey.sublist(32, 64);
  }

  Uint8List _computeConfirm(int sendConfirm) {
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(_kck!));

    final data = Uint8List.fromList([
      sendConfirm & 0xFF,
      (sendConfirm >> 8) & 0xFF,
      ..._scalarToBytes(_scalar!),
      ..._pointToBytes(_element!),
      ..._scalarToBytes(_peerScalar!),
      ..._pointToBytes(_peerElement!),
    ]);

    final output = Uint8List(32);
    hmac.update(data, 0, data.length);
    hmac.doFinal(output, 0);

    return output;
  }

  Uint8List _computePeerConfirm(int sendConfirm) {
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(_kck!));

    final data = Uint8List.fromList([
      sendConfirm & 0xFF,
      (sendConfirm >> 8) & 0xFF,
      ..._scalarToBytes(_peerScalar!),
      ..._pointToBytes(_peerElement!),
      ..._scalarToBytes(_scalar!),
      ..._pointToBytes(_element!),
    ]);

    final output = Uint8List(32);
    hmac.update(data, 0, data.length);
    hmac.doFinal(output, 0);

    return output;
  }

  Uint8List _scalarToBytes(BigInt scalar) {
    final bytes = Uint8List(32);
    var value = scalar;
    for (int i = 0; i < 32; i++) {
      bytes[i] = (value & BigInt.from(0xFF)).toInt();
      value = value >> 8;
    }
    return bytes;
  }

  BigInt _bytesToScalar(Uint8List bytes) {
    var result = BigInt.zero;
    for (int i = bytes.length - 1; i >= 0; i--) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  Uint8List _pointToBytes(ECPoint point) {
    // Use uncompressed encoding and extract x coordinate (32 bytes)
    // This is compatible with Curve25519
    final encoded = point
        .getEncoded(false); // Uncompressed: 0x04 + x(32) + y(32) = 65 bytes
    // Extract x coordinate (skip first byte 0x04)
    return Uint8List.fromList(encoded.sublist(1, 33));
  }

  ECPoint _bytesToPoint(Uint8List bytes) {
    final curve = ECCurve_secp256r1();

    if (bytes.length == 32) {
      // 32 bytes: x coordinate, need to rebuild complete point
      // Use compressed point format: 0x02 + x (assuming y is even)
      final compressed = Uint8List(33);
      compressed[0] = 0x02; // Assume y is even
      compressed.setRange(1, 33, bytes);
      return curve.curve.decodePoint(compressed)!;
    } else if (bytes.length == 33) {
      // 33 bytes: compressed point encoding
      return curve.curve.decodePoint(bytes)!;
    } else {
      throw ArgumentError('Invalid point bytes length: ${bytes.length}');
    }
  }

  bool _constantTimeCompare(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;

    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }

    return result == 0;
  }
}
