library;

import 'dart:typed_data';

/// Curve order: l = 2^252 + 27742317777372353535851937790883648493
const List<int> curveOrderL = [
  0xed,
  0xd3,
  0xf5,
  0x5c,
  0x1a,
  0x63,
  0x12,
  0x58,
  0xd6,
  0x9c,
  0xf7,
  0xa2,
  0xde,
  0xf9,
  0xde,
  0x14,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x10,
];

/// Scalar for Curve25519 (mod curve order l)
class Scalar25519 {
  final Uint8List bytes;

  Scalar25519(this.bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('Scalar must be 32 bytes');
    }
  }

  factory Scalar25519.zero() => Scalar25519(Uint8List(32));

  factory Scalar25519.one() {
    final bytes = Uint8List(32);
    bytes[0] = 1;
    return Scalar25519(bytes);
  }

  factory Scalar25519.fromBytes(Uint8List bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('Scalar must be 32 bytes');
    }
    return Scalar25519(Uint8List.fromList(bytes));
  }

  factory Scalar25519.fromU64(int value) {
    final bytes = Uint8List(32);
    for (int i = 0; i < 8; i++) {
      bytes[i] = (value >> (i * 8)) & 0xFF;
    }
    return Scalar25519(bytes);
  }

  /// Reduce a 64-byte hash to a scalar modulo curve order
  factory Scalar25519.fromBytesModOrder(Uint8List input) {
    if (input.length != 64) {
      throw ArgumentError('Input must be 64 bytes');
    }
    return Scalar25519(_reduce64BytesModL(input));
  }

  /// Reduce a 64-byte wide hash to a scalar modulo curve order
  /// This matches Rust's Scalar::from_bytes_mod_order_wide
  factory Scalar25519.fromBytesModOrderWide(Uint8List input) {
    if (input.length != 64) {
      throw ArgumentError('Input must be 64 bytes for wide reduction');
    }
    return Scalar25519(_reduce64BytesModL(input));
  }

  /// Create scalar from 32-byte input, reducing modulo curve order if needed
  /// This matches Rust's Scalar::from_bytes_mod_order (32-byte version)
  factory Scalar25519.fromBytesModOrder32(Uint8List input) {
    if (input.length != 32) {
      throw ArgumentError('Input must be 32 bytes');
    }
    return Scalar25519(_reduceModL(input));
  }

  /// Add two scalars modulo l
  Scalar25519 add(Scalar25519 other) {
    return Scalar25519(_scalarAdd(bytes, other.bytes));
  }

  /// Subtract two scalars modulo l
  Scalar25519 sub(Scalar25519 other) {
    return Scalar25519(_scalarSub(bytes, other.bytes));
  }

  /// Multiply two scalars modulo l
  Scalar25519 mul(Scalar25519 other) {
    return Scalar25519(_scalarMul(bytes, other.bytes));
  }

  /// Negate scalar modulo l
  Scalar25519 negate() {
    return Scalar25519(_scalarNegate(bytes));
  }

  /// Compute multiplicative inverse modulo l
  Scalar25519 invert() {
    return Scalar25519(_scalarInvert(bytes));
  }

  Uint8List toBytes() => Uint8List.fromList(bytes);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Scalar25519) return false;
    if (bytes.length != other.bytes.length) return false;
    for (int i = 0; i < bytes.length; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => bytes.fold(0, (prev, byte) => prev ^ byte.hashCode);
}

/// Reduce 64 bytes modulo curve order l
Uint8List _reduce64BytesModL(Uint8List input) {
  // Convert to limbs (64-bit)
  final limbs = List<int>.filled(9, 0);

  for (int i = 0; i < 8; i++) {
    limbs[i] = _load8(input, i * 8);
  }

  // Reduce using the curve order
  _reduceLimbs(limbs);

  // Convert back to bytes
  final result = Uint8List(32);
  for (int i = 0; i < 4; i++) {
    _store8(result, i * 8, limbs[i]);
  }

  return result;
}

/// Load 8 bytes as 64-bit integer (little-endian)
int _load8(Uint8List bytes, int offset) {
  int result = 0;
  for (int i = 0; i < 8 && offset + i < bytes.length; i++) {
    result |= bytes[offset + i] << (i * 8);
  }
  return result;
}

/// Store 64-bit integer as 8 bytes (little-endian)
void _store8(Uint8List bytes, int offset, int value) {
  for (int i = 0; i < 8 && offset + i < bytes.length; i++) {
    bytes[offset + i] = (value >> (i * 8)) & 0xFF;
  }
}

/// Reduce limbs modulo l
void _reduceLimbs(List<int> limbs) {
  // Curve order l as 64-bit limbs
  final l = [
    0x5812631a5cf5d3ed,
    0x14def9dea2f79cd6,
    0x0000000000000000,
    0x1000000000000000,
  ];

  // Perform reduction
  for (int i = 0; i < 100; i++) {
    int borrow = 0;
    final temp = List<int>.filled(4, 0);

    for (int j = 0; j < 4; j++) {
      final diff = limbs[j] - l[j] - borrow;
      temp[j] = diff & 0xFFFFFFFFFFFFFFFF;
      borrow = (diff < 0) ? 1 : 0;
    }

    if (borrow == 0) {
      for (int j = 0; j < 4; j++) {
        limbs[j] = temp[j];
      }
    }
  }
}

/// Add two scalars modulo l
Uint8List _scalarAdd(Uint8List a, Uint8List b) {
  final result = Uint8List(32);
  int carry = 0;

  for (int i = 0; i < 32; i++) {
    final sum = a[i] + b[i] + carry;
    result[i] = sum & 0xFF;
    carry = sum >> 8;
  }

  return _reduceModL(result);
}

/// Subtract two scalars modulo l
Uint8List _scalarSub(Uint8List a, Uint8List b) {
  // Add (l - b) to a
  final negB = _scalarNegate(b);
  return _scalarAdd(a, negB);
}

/// Multiply two scalars modulo l using Montgomery multiplication
Uint8List _scalarMul(Uint8List a, Uint8List b) {
  // Convert to limbs
  final aLimbs = List<int>.filled(4, 0);
  final bLimbs = List<int>.filled(4, 0);

  for (int i = 0; i < 4; i++) {
    aLimbs[i] = _load8(a, i * 8);
    bLimbs[i] = _load8(b, i * 8);
  }

  // Schoolbook multiplication
  final product = List<int>.filled(8, 0);
  for (int i = 0; i < 4; i++) {
    int carry = 0;
    for (int j = 0; j < 4; j++) {
      final prod = aLimbs[i] * bLimbs[j] + product[i + j] + carry;
      product[i + j] = prod & 0xFFFFFFFFFFFFFFFF;
      carry = prod >> 64;
    }
    product[i + 4] = carry;
  }

  // Reduce modulo l
  _reduceLimbs(product);

  // Convert back to bytes
  final result = Uint8List(32);
  for (int i = 0; i < 4; i++) {
    _store8(result, i * 8, product[i]);
  }

  return result;
}

/// Negate scalar modulo l
Uint8List _scalarNegate(Uint8List a) {
  final result = Uint8List(32);
  int borrow = 0;

  for (int i = 0; i < 32; i++) {
    final diff = curveOrderL[i] - a[i] - borrow;
    result[i] = diff & 0xFF;
    borrow = (diff < 0) ? 1 : 0;
  }

  return result;
}

/// Compute multiplicative inverse using Fermat's little theorem
/// a^(-1) = a^(l-2) mod l
Uint8List _scalarInvert(Uint8List a) {
  // Check if a is zero
  bool isZero = true;
  for (final byte in a) {
    if (byte != 0) {
      isZero = false;
      break;
    }
  }
  if (isZero) {
    throw ArgumentError('Cannot invert zero');
  }

  // Compute a^(l-2) using square-and-multiply
  final lMinus2 = Uint8List.fromList(curveOrderL);
  lMinus2[0] -= 2;

  Uint8List result = Uint8List(32);
  result[0] = 1;
  Uint8List base = Uint8List.fromList(a);

  for (int i = 0; i < 252; i++) {
    final bit = (lMinus2[i ~/ 8] >> (i % 8)) & 1;
    if (bit == 1) {
      result = _scalarMul(result, base);
    }
    base = _scalarMul(base, base);
  }

  return result;
}

/// Reduce 32 bytes modulo l
Uint8List _reduceModL(Uint8List input) {
  final limbs = List<int>.filled(4, 0);
  for (int i = 0; i < 4; i++) {
    limbs[i] = _load8(input, i * 8);
  }

  _reduceLimbs(limbs);

  final result = Uint8List(32);
  for (int i = 0; i < 4; i++) {
    _store8(result, i * 8, limbs[i]);
  }

  return result;
}
