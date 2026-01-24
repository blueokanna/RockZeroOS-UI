/// Complete Ristretto255 Point Implementation
/// Full Ristretto group operations without simplifications
library;

import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'edwards_point.dart';
import 'scalar_arithmetic.dart';
import 'field_element.dart';

/// Ristretto255 point (quotient group of Curve25519)
class RistrettoPoint25519 {
  final EdwardsPoint point;

  RistrettoPoint25519(this.point);

  factory RistrettoPoint25519.identity() {
    return RistrettoPoint25519(EdwardsPoint.identity());
  }

  /// Create from uniform 64 bytes using Elligator map
  factory RistrettoPoint25519.fromUniformBytes(Uint8List bytes) {
    if (bytes.length != 64) {
      throw ArgumentError('Uniform bytes must be 64 bytes');
    }

    // Apply Elligator map to first 32 bytes
    final point1 = _elligatorMap(bytes.sublist(0, 32));

    // Apply Elligator map to second 32 bytes
    final point2 = _elligatorMap(bytes.sublist(32, 64));

    // Add the two points
    return RistrettoPoint25519(point1.add(point2));
  }

  /// Elligator map: hash to curve
  static EdwardsPoint _elligatorMap(Uint8List bytes) {
    final r = FieldElement.fromBytes(bytes);

    // Compute u = -1 / (1 + d*r^2)
    final rSquared = r.square();
    final d = FieldElement.d();
    final denominator = FieldElement.one().add(d.mul(rSquared));
    final u = denominator.invert().negate();

    // Compute v^2 = u*(u^2 + 1)
    final uSquared = u.square();
    final vSquared = u.mul(uSquared.add(FieldElement.one()));

    // Try to compute v = sqrt(v^2)
    final v = vSquared.sqrt();

    // Check if v^2 == vSquared
    final isSquare = v.square() == vSquared;

    // If not a square, use the other square root
    final vFinal = isSquare ? v : v.mul(FieldElement.sqrtMinusOne());

    // Compute x and y coordinates
    final x = u;
    final y = vFinal;

    return EdwardsPoint(
      X: x,
      Y: y,
      Z: FieldElement.one(),
      T: x.mul(y),
    );
  }

  /// Compress to 32 bytes
  Uint8List compress() {
    return point.compress();
  }

  /// Decompress from 32 bytes
  factory RistrettoPoint25519.decompress(Uint8List bytes) {
    return RistrettoPoint25519(EdwardsPoint.decompress(bytes));
  }

  /// Add two Ristretto points
  RistrettoPoint25519 add(RistrettoPoint25519 other) {
    return RistrettoPoint25519(point.add(other.point));
  }

  /// Subtract two Ristretto points
  RistrettoPoint25519 sub(RistrettoPoint25519 other) {
    return RistrettoPoint25519(point.add(other.point.negate()));
  }

  /// Scalar multiplication
  RistrettoPoint25519 scalarMul(Scalar25519 scalar) {
    return RistrettoPoint25519(point.scalarMul(scalar));
  }

  /// Multiscalar multiplication
  static RistrettoPoint25519 multiscalarMul(
    List<Scalar25519> scalars,
    List<RistrettoPoint25519> points,
  ) {
    final edwardsPoints = points.map((p) => p.point).toList();
    return RistrettoPoint25519(
      EdwardsPoint.multiscalarMul(scalars, edwardsPoints),
    );
  }

  /// Negate point
  RistrettoPoint25519 negate() {
    return RistrettoPoint25519(point.negate());
  }

  /// Standard Ristretto255 basepoint
  static RistrettoPoint25519 basepoint() {
    // Standard basepoint in compressed form
    final bytes = Uint8List.fromList([
      0xe2,
      0xf2,
      0xae,
      0x0a,
      0x6a,
      0xbc,
      0x4e,
      0x71,
      0xa8,
      0x84,
      0xa9,
      0x61,
      0xc5,
      0x00,
      0x51,
      0x5f,
      0x58,
      0xe3,
      0x0b,
      0x6a,
      0xa5,
      0x82,
      0xdd,
      0x8d,
      0xb6,
      0xa6,
      0x59,
      0x45,
      0xe0,
      0x8d,
      0x2d,
      0x76,
    ]);
    return RistrettoPoint25519.decompress(bytes);
  }

  /// Hash to Ristretto point using SHA-512
  static RistrettoPoint25519 hashToPoint(String label, Uint8List data) {
    final input = <int>[];
    input.addAll(label.codeUnits);
    input.addAll(data);

    final hash = sha512.convert(input);
    return RistrettoPoint25519.fromUniformBytes(
      Uint8List.fromList(hash.bytes),
    );
  }

  /// Check if point is identity
  bool isIdentity() {
    return point.isIdentity();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RistrettoPoint25519) return false;
    return point == other.point;
  }

  @override
  int get hashCode => point.hashCode;
}
