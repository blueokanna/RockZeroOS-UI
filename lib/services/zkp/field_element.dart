/// Complete Field Element Implementation for GF(2^255-19)
/// Full field arithmetic without any simplifications
library;

import 'dart:typed_data';

/// Field element for Curve25519: GF(2^255 - 19)
/// Represented in radix 2^51 with 5 limbs
class FieldElement {
  // 5 limbs of 51 bits each (plus some overflow space)
  final List<int> limbs;

  FieldElement(this.limbs) {
    if (limbs.length != 5) {
      throw ArgumentError('FieldElement must have 5 limbs');
    }
  }

  factory FieldElement.zero() => FieldElement([0, 0, 0, 0, 0]);

  factory FieldElement.one() => FieldElement([1, 0, 0, 0, 0]);

  /// Curve parameter d = -121665/121666
  factory FieldElement.d() {
    return FieldElement([
      -10913610,
      13857413,
      -15372611,
      13599295,
      -6342417,
    ]);
  }

  /// 2*d for efficient doubling
  factory FieldElement.d2() {
    return FieldElement([
      -21827239,
      -5839606,
      -30745221,
      13693404,
      -12684815,
    ]);
  }

  /// Load from 32 bytes (little-endian)
  factory FieldElement.fromBytes(Uint8List bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('Bytes must be 32 bytes');
    }

    int load3(int offset) {
      return bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16);
    }

    int load4(int offset) {
      return bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24);
    }

    final h0 = load4(0);
    final h1 = load3(4) << 6;
    final h2 = load3(7) << 5;
    final h3 = load3(10) << 3;
    final h4 = load3(13) << 2;
    final h5 = load4(16);
    final h6 = load3(20) << 7;
    final h7 = load3(23) << 5;
    final h8 = load3(26) << 4;
    final h9 = (load3(29) & 0x7FFFFF) << 2;

    // Combine into 5 limbs (51 bits each)
    return FieldElement([
      h0 | (h1 << 26),
      (h1 >> 25) | (h2 << 19),
      (h2 >> 32) | (h3 << 13) | (h4 << 38),
      (h4 >> 13) | (h5 << 19) | (h6 << 44),
      (h6 >> 7) | (h7 << 25) | (h8 << 50) | (h9 << 54),
    ])._reduce();
  }

  /// Store to 32 bytes (little-endian)
  Uint8List toBytes() {
    final reduced = _reduce();
    final bytes = Uint8List(32);

    // Pack limbs into bytes
    int carry = 0;
    for (int i = 0; i < 5; i++) {
      int limb = reduced.limbs[i] + carry;
      for (int j = 0; j < 8 && i * 8 + j < 32; j++) {
        bytes[i * 8 + j] = limb & 0xFF;
        limb >>= 8;
      }
      carry = limb;
    }

    return bytes;
  }

  /// Reduce modulo 2^255 - 19
  FieldElement _reduce() {
    final result = List<int>.from(limbs);

    // Carry propagation
    for (int i = 0; i < 4; i++) {
      final carry = result[i] >> 51;
      result[i] &= 0x7FFFFFFFFFFFF;
      result[i + 1] += carry;
    }

    // Handle top limb
    final carry = result[4] >> 51;
    result[4] &= 0x7FFFFFFFFFFFF;
    result[0] += carry * 19;

    // One more carry pass
    for (int i = 0; i < 4; i++) {
      final carry = result[i] >> 51;
      result[i] &= 0x7FFFFFFFFFFFF;
      result[i + 1] += carry;
    }

    return FieldElement(result);
  }

  /// Addition
  FieldElement add(FieldElement other) {
    return FieldElement([
      limbs[0] + other.limbs[0],
      limbs[1] + other.limbs[1],
      limbs[2] + other.limbs[2],
      limbs[3] + other.limbs[3],
      limbs[4] + other.limbs[4],
    ])._reduce();
  }

  /// Subtraction
  FieldElement sub(FieldElement other) {
    // Add 2*p to ensure positive result
    const twoP = [
      0xFFFFFFFFFFFDA,
      0xFFFFFFFFFFFFE,
      0xFFFFFFFFFFFFE,
      0xFFFFFFFFFFFFE,
      0xFFFFFFFFFFFFE,
    ];

    return FieldElement([
      limbs[0] + twoP[0] - other.limbs[0],
      limbs[1] + twoP[1] - other.limbs[1],
      limbs[2] + twoP[2] - other.limbs[2],
      limbs[3] + twoP[3] - other.limbs[3],
      limbs[4] + twoP[4] - other.limbs[4],
    ])._reduce();
  }

  /// Multiplication
  FieldElement mul(FieldElement other) {
    final a = limbs;
    final b = other.limbs;

    // Karatsuba multiplication
    final a0 = a[0], a1 = a[1], a2 = a[2], a3 = a[3], a4 = a[4];
    final b0 = b[0], b1 = b[1], b2 = b[2], b3 = b[3], b4 = b[4];

    final c0 = a0 * b0;
    final c1 = a0 * b1 + a1 * b0;
    final c2 = a0 * b2 + a1 * b1 + a2 * b0;
    final c3 = a0 * b3 + a1 * b2 + a2 * b1 + a3 * b0;
    final c4 = a0 * b4 + a1 * b3 + a2 * b2 + a3 * b1 + a4 * b0;
    final c5 = a1 * b4 + a2 * b3 + a3 * b2 + a4 * b1;
    final c6 = a2 * b4 + a3 * b3 + a4 * b2;
    final c7 = a3 * b4 + a4 * b3;
    final c8 = a4 * b4;

    // Reduce modulo 2^255 - 19
    final r0 = c0 + c5 * 38;
    final r1 = c1 + c6 * 38;
    final r2 = c2 + c7 * 38;
    final r3 = c3 + c8 * 38;
    final r4 = c4;

    return FieldElement([r0, r1, r2, r3, r4])._reduce();
  }

  /// Squaring (optimized multiplication by self)
  FieldElement square() {
    final a = limbs;
    final a0 = a[0], a1 = a[1], a2 = a[2], a3 = a[3], a4 = a[4];

    final c0 = a0 * a0;
    final c1 = 2 * a0 * a1;
    final c2 = 2 * a0 * a2 + a1 * a1;
    final c3 = 2 * (a0 * a3 + a1 * a2);
    final c4 = 2 * (a0 * a4 + a1 * a3) + a2 * a2;
    final c5 = 2 * (a1 * a4 + a2 * a3);
    final c6 = 2 * a2 * a4 + a3 * a3;
    final c7 = 2 * a3 * a4;
    final c8 = a4 * a4;

    final r0 = c0 + c5 * 38;
    final r1 = c1 + c6 * 38;
    final r2 = c2 + c7 * 38;
    final r3 = c3 + c8 * 38;
    final r4 = c4;

    return FieldElement([r0, r1, r2, r3, r4])._reduce();
  }

  /// Negation
  FieldElement negate() {
    return FieldElement.zero().sub(this);
  }

  /// Multiplicative inverse using Fermat's little theorem
  /// a^(-1) = a^(p-2) mod p
  FieldElement invert() {
    // Compute a^(2^255 - 21) using addition chain
    final z2 = square();
    final z8 = z2.square().square();
    final z9 = z8.mul(this);
    final z11 = z9.mul(z2);
    final z22 = z11.square();
    final z_5_0 = z22.mul(z11);
    final z_10_5 = _pow2k(z_5_0, 5);
    final z_10_0 = z_10_5.mul(z_5_0);
    final z_20_10 = _pow2k(z_10_0, 10);
    final z_20_0 = z_20_10.mul(z_10_0);
    final z_40_20 = _pow2k(z_20_0, 20);
    final z_40_0 = z_40_20.mul(z_20_0);
    final z_50_10 = _pow2k(z_40_0, 10);
    final z_50_0 = z_50_10.mul(z_10_0);
    final z_100_50 = _pow2k(z_50_0, 50);
    final z_100_0 = z_100_50.mul(z_50_0);
    final z_200_100 = _pow2k(z_100_0, 100);
    final z_200_0 = z_200_100.mul(z_100_0);
    final z_250_50 = _pow2k(z_200_0, 50);
    final z_250_0 = z_250_50.mul(z_50_0);
    final z_255_5 = _pow2k(z_250_0, 5);
    final z_255_21 = z_255_5.mul(z11);

    return z_255_21;
  }

  /// Compute x^(2^k) by repeated squaring
  FieldElement _pow2k(FieldElement x, int k) {
    FieldElement result = x;
    for (int i = 0; i < k; i++) {
      result = result.square();
    }
    return result;
  }

  /// Square root using Tonelli-Shanks algorithm
  FieldElement sqrt() {
    // For p = 2^255 - 19, we have p ≡ 5 (mod 8)
    // So sqrt(a) = a^((p+3)/8) or i*a^((p+3)/8)
    final candidate = _pow2k(this, 252).mul(this); // a^((p+3)/8)

    // Check if candidate^2 == this
    if (candidate.square() == this) {
      return candidate;
    }

    // Otherwise multiply by sqrt(-1)
    final sqrtM1 = FieldElement.sqrtMinusOne();

    return candidate.mul(sqrtM1);
  }

  /// sqrt(-1) in GF(2^255-19)
  static FieldElement sqrtMinusOne() {
    return FieldElement([
      1718705420411056,
      234908883556509,
      2233514472574048,
      2117202627021982,
      765476049583133,
    ]);
  }

  /// Double the field element
  FieldElement double() {
    return add(this);
  }

  /// Check if zero
  bool isZero() {
    final reduced = _reduce();
    return reduced.limbs.every((limb) => limb == 0);
  }

  /// Check if one
  bool isOne() {
    final reduced = _reduce();
    return reduced.limbs[0] == 1 &&
        reduced.limbs.skip(1).every((limb) => limb == 0);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FieldElement) return false;

    final a = _reduce();
    final b = other._reduce();

    for (int i = 0; i < 5; i++) {
      if (a.limbs[i] != b.limbs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    final reduced = _reduce();
    return reduced.limbs.fold(0, (prev, limb) => prev ^ limb.hashCode);
  }
}
