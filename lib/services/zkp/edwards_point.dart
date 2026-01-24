library;

import 'dart:typed_data';
import 'field_element.dart';
import 'scalar_arithmetic.dart';

/// Point on the twisted Edwards curve in extended coordinates
/// Curve equation: -x^2 + y^2 = 1 + d*x^2*y^2
/// where d = -121665/121666
class EdwardsPoint {
  final FieldElement X;
  final FieldElement Y;
  final FieldElement Z;
  final FieldElement T; // T = X*Y/Z

  EdwardsPoint({
    required this.X,
    required this.Y,
    required this.Z,
    required this.T,
  });

  /// Identity point (0, 1)
  factory EdwardsPoint.identity() {
    return EdwardsPoint(
      X: FieldElement.zero(),
      Y: FieldElement.one(),
      Z: FieldElement.one(),
      T: FieldElement.zero(),
    );
  }

  /// Compress point to 32 bytes
  Uint8List compress() {
    final recip = Z.invert();
    final x = X.mul(recip);
    final y = Y.mul(recip);

    final bytes = y.toBytes();
    // Set sign bit based on x
    final xBytes = x.toBytes();
    bytes[31] ^= (xBytes[0] & 1) << 7;

    return bytes;
  }

  /// Decompress point from 32 bytes
  factory EdwardsPoint.decompress(Uint8List bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('Compressed point must be 32 bytes');
    }

    // Extract sign bit
    final sign = (bytes[31] >> 7) & 1;

    // Clear sign bit and load y
    final yBytes = Uint8List.fromList(bytes);
    yBytes[31] &= 0x7F;
    final y = FieldElement.fromBytes(yBytes);

    // Recover x from y using curve equation
    // x^2 = (y^2 - 1) / (d*y^2 + 1)
    final ySquared = y.square();
    final one = FieldElement.one();
    final d = FieldElement.d();

    final numerator = ySquared.sub(one);
    final denominator = d.mul(ySquared).add(one);
    final xSquared = numerator.mul(denominator.invert());

    // Compute square root
    final x = xSquared.sqrt();

    // Adjust sign
    final xBytes = x.toBytes();
    final xSign = xBytes[0] & 1;
    final xFinal = (xSign == sign) ? x : x.negate();

    return EdwardsPoint(
      X: xFinal,
      Y: y,
      Z: one,
      T: xFinal.mul(y),
    );
  }

  /// Add two points using extended twisted Edwards addition
  EdwardsPoint add(EdwardsPoint other) {
    // Extended twisted Edwards addition formula
    // Cost: 8M + 1*k + 1*2
    final A = X.mul(other.X);
    final B = Y.mul(other.Y);
    final C = T.mul(other.T).mul(FieldElement.d2());
    final D = Z.mul(other.Z);
    final E = (X.add(Y)).mul(other.X.add(other.Y)).sub(A).sub(B);
    final F = D.sub(C);
    final G = D.add(C);
    final H = B.sub(A);

    return EdwardsPoint(
      X: E.mul(F),
      Y: G.mul(H),
      Z: F.mul(G),
      T: E.mul(H),
    );
  }

  /// Double a point
  EdwardsPoint double() {
    // Extended twisted Edwards doubling formula
    // Cost: 4M + 4S + 1*a + 6add + 1*2
    final A = X.square();
    final B = Y.square();
    final C = Z.square().double();
    final D = A.negate();
    final E = (X.add(Y)).square().sub(A).sub(B);
    final G = D.add(B);
    final F = G.sub(C);
    final H = D.sub(B);

    return EdwardsPoint(
      X: E.mul(F),
      Y: G.mul(H),
      Z: F.mul(G),
      T: E.mul(H),
    );
  }

  /// Scalar multiplication using double-and-add
  EdwardsPoint scalarMul(Scalar25519 scalar) {
    EdwardsPoint result = EdwardsPoint.identity();
    EdwardsPoint temp = this;

    final scalarBytes = scalar.toBytes();
    for (int i = 0; i < 256; i++) {
      final bit = (scalarBytes[i ~/ 8] >> (i % 8)) & 1;
      if (bit == 1) {
        result = result.add(temp);
      }
      temp = temp.double();
    }

    return result;
  }

  /// Multiscalar multiplication: sum of scalar_i * point_i
  /// Uses Straus's algorithm for efficiency
  static EdwardsPoint multiscalarMul(
    List<Scalar25519> scalars,
    List<EdwardsPoint> points,
  ) {
    if (scalars.length != points.length) {
      throw ArgumentError('Scalars and points must have same length');
    }

    if (scalars.isEmpty) {
      return EdwardsPoint.identity();
    }

    // Precompute lookup tables for each point
    final tables = <List<EdwardsPoint>>[];
    for (final point in points) {
      final table = <EdwardsPoint>[EdwardsPoint.identity()];
      for (int i = 1; i < 16; i++) {
        table.add(table[i - 1].add(point));
      }
      tables.add(table);
    }

    // Process 4 bits at a time
    EdwardsPoint result = EdwardsPoint.identity();

    for (int i = 63; i >= 0; i--) {
      // Double 4 times
      result = result.double().double().double().double();

      // Add contributions from each scalar/point pair
      for (int j = 0; j < scalars.length; j++) {
        final scalarBytes = scalars[j].toBytes();
        final nibble = _getNibble(scalarBytes, i);
        if (nibble != 0) {
          result = result.add(tables[j][nibble]);
        }
      }
    }

    return result;
  }

  /// Get 4-bit nibble from scalar bytes
  static int _getNibble(Uint8List bytes, int index) {
    final byteIndex = index ~/ 2;
    final shift = (index % 2) * 4;
    if (byteIndex >= bytes.length) return 0;
    return (bytes[byteIndex] >> shift) & 0x0F;
  }

  /// Negate point
  EdwardsPoint negate() {
    return EdwardsPoint(
      X: X.negate(),
      Y: Y,
      Z: Z,
      T: T.negate(),
    );
  }

  /// Check if point is identity
  bool isIdentity() {
    final recip = Z.invert();
    final x = X.mul(recip);
    final y = Y.mul(recip);
    return x.isZero() && y.isOne();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EdwardsPoint) return false;

    // Compare in affine coordinates
    final x1 = X.mul(other.Z);
    final x2 = other.X.mul(Z);
    final y1 = Y.mul(other.Z);
    final y2 = other.Y.mul(Z);

    return x1 == x2 && y1 == y2;
  }

  @override
  int get hashCode => X.hashCode ^ Y.hashCode ^ Z.hashCode ^ T.hashCode;
}
