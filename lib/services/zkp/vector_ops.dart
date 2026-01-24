library;

import 'scalar_arithmetic.dart';

/// Vector operations for inner product proofs
class VectorOps {
  /// Inner product of two scalar vectors
  static Scalar25519 innerProduct(
    List<Scalar25519> a,
    List<Scalar25519> b,
  ) {
    if (a.length != b.length) {
      throw ArgumentError('Vectors must have same length');
    }

    Scalar25519 result = Scalar25519.zero();
    for (int i = 0; i < a.length; i++) {
      result = result.add(a[i].mul(b[i]));
    }
    return result;
  }

  /// Hadamard product (element-wise multiplication)
  static List<Scalar25519> hadamardProduct(
    List<Scalar25519> a,
    List<Scalar25519> b,
  ) {
    if (a.length != b.length) {
      throw ArgumentError('Vectors must have same length');
    }

    return List.generate(a.length, (i) => a[i].mul(b[i]));
  }

  /// Scalar-vector multiplication
  static List<Scalar25519> scalarMul(
    Scalar25519 scalar,
    List<Scalar25519> vector,
  ) {
    return vector.map((v) => scalar.mul(v)).toList();
  }

  /// Vector addition
  static List<Scalar25519> add(
    List<Scalar25519> a,
    List<Scalar25519> b,
  ) {
    if (a.length != b.length) {
      throw ArgumentError('Vectors must have same length');
    }

    return List.generate(a.length, (i) => a[i].add(b[i]));
  }

  /// Vector subtraction
  static List<Scalar25519> sub(
    List<Scalar25519> a,
    List<Scalar25519> b,
  ) {
    if (a.length != b.length) {
      throw ArgumentError('Vectors must have same length');
    }

    return List.generate(a.length, (i) => a[i].sub(b[i]));
  }

  /// Compute powers of a scalar: [1, x, x^2, x^3, ...]
  static List<Scalar25519> powers(Scalar25519 x, int n) {
    final result = <Scalar25519>[];
    Scalar25519 current = Scalar25519.one();

    for (int i = 0; i < n; i++) {
      result.add(current);
      current = current.mul(x);
    }

    return result;
  }

  /// Sum of all elements in a vector
  static Scalar25519 sum(List<Scalar25519> vector) {
    Scalar25519 result = Scalar25519.zero();
    for (final element in vector) {
      result = result.add(element);
    }
    return result;
  }

  /// Compute weighted sum: sum(weights[i] * vector[i])
  static Scalar25519 weightedSum(
    List<Scalar25519> weights,
    List<Scalar25519> vector,
  ) {
    if (weights.length != vector.length) {
      throw ArgumentError('Weights and vector must have same length');
    }

    Scalar25519 result = Scalar25519.zero();
    for (int i = 0; i < weights.length; i++) {
      result = result.add(weights[i].mul(vector[i]));
    }
    return result;
  }
}
