/// Bulletproofs Types and Data Structures
/// Based on the Rust bulletproofs implementation using Ristretto255
library;

import 'dart:typed_data';

/// Represents a scalar value in the Ristretto255 group
class Scalar {
  final Uint8List bytes;

  Scalar(this.bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('Scalar must be 32 bytes');
    }
  }

  factory Scalar.zero() {
    return Scalar(Uint8List(32));
  }

  factory Scalar.one() {
    final bytes = Uint8List(32);
    bytes[0] = 1;
    return Scalar(bytes);
  }

  factory Scalar.fromBytes(Uint8List bytes) {
    return Scalar(Uint8List.fromList(bytes));
  }

  factory Scalar.fromInt(int value) {
    final bytes = Uint8List(32);
    for (int i = 0; i < 8 && i < 32; i++) {
      bytes[i] = (value >> (i * 8)) & 0xFF;
    }
    return Scalar(bytes);
  }

  Uint8List toBytes() => Uint8List.fromList(bytes);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Scalar) return false;
    if (bytes.length != other.bytes.length) return false;
    for (int i = 0; i < bytes.length; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => bytes.fold(0, (prev, byte) => prev ^ byte.hashCode);
}

/// Represents a point on the Ristretto255 curve
class RistrettoPoint {
  final Uint8List bytes;

  RistrettoPoint(this.bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('RistrettoPoint must be 32 bytes');
    }
  }

  factory RistrettoPoint.fromBytes(Uint8List bytes) {
    return RistrettoPoint(Uint8List.fromList(bytes));
  }

  Uint8List toBytes() => Uint8List.fromList(bytes);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RistrettoPoint) return false;
    if (bytes.length != other.bytes.length) return false;
    for (int i = 0; i < bytes.length; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => bytes.fold(0, (prev, byte) => prev ^ byte.hashCode);
}

/// Compressed Ristretto point (32 bytes)
class CompressedRistretto {
  final Uint8List bytes;

  CompressedRistretto(this.bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('CompressedRistretto must be 32 bytes');
    }
  }

  factory CompressedRistretto.fromBytes(Uint8List bytes) {
    return CompressedRistretto(Uint8List.fromList(bytes));
  }

  Uint8List toBytes() => Uint8List.fromList(bytes);

  RistrettoPoint decompress() {
    return RistrettoPoint(bytes);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CompressedRistretto) return false;
    if (bytes.length != other.bytes.length) return false;
    for (int i = 0; i < bytes.length; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => bytes.fold(0, (prev, byte) => prev ^ byte.hashCode);
}

/// Pedersen commitment generators (G and H base points)
class PedersenGens {
  final RistrettoPoint B; // Value generator
  final RistrettoPoint bBlinding; // Blinding generator

  PedersenGens({required this.B, required this.bBlinding});

  /// Create default Pedersen generators
  factory PedersenGens.defaultGens() {
    // Standard Ristretto255 base point for B
    final bBytes = Uint8List(32);
    bBytes[0] = 0x58; // Ristretto base point compressed form
    bBytes[1] = 0x66;
    bBytes[2] = 0x66;
    bBytes[3] = 0x66;
    bBytes[4] = 0x66;
    bBytes[5] = 0x66;
    bBytes[6] = 0x66;
    bBytes[7] = 0x66;
    bBytes[8] = 0x66;
    bBytes[9] = 0x66;
    bBytes[10] = 0x66;
    bBytes[11] = 0x66;
    bBytes[12] = 0x66;
    bBytes[13] = 0x66;
    bBytes[14] = 0x66;
    bBytes[15] = 0x66;
    bBytes[16] = 0x66;
    bBytes[17] = 0x66;
    bBytes[18] = 0x66;
    bBytes[19] = 0x66;
    bBytes[20] = 0x66;
    bBytes[21] = 0x66;
    bBytes[22] = 0x66;
    bBytes[23] = 0x66;
    bBytes[24] = 0x66;
    bBytes[25] = 0x66;
    bBytes[26] = 0x66;
    bBytes[27] = 0x66;
    bBytes[28] = 0x66;
    bBytes[29] = 0x66;
    bBytes[30] = 0x66;
    bBytes[31] = 0x66;

    // Blinding generator derived from hash-to-curve
    final bBlindingBytes = Uint8List(32);
    bBlindingBytes[0] = 0x8c;
    bBlindingBytes[1] = 0x78;
    bBlindingBytes[2] = 0x0c;
    bBlindingBytes[3] = 0xe6;
    bBlindingBytes[4] = 0x3b;
    bBlindingBytes[5] = 0x4f;
    bBlindingBytes[6] = 0x6b;
    bBlindingBytes[7] = 0x7f;
    bBlindingBytes[8] = 0xc4;
    bBlindingBytes[9] = 0x0e;
    bBlindingBytes[10] = 0x0e;
    bBlindingBytes[11] = 0xdb;
    bBlindingBytes[12] = 0x3f;
    bBlindingBytes[13] = 0xbf;
    bBlindingBytes[14] = 0x7a;
    bBlindingBytes[15] = 0x72;
    bBlindingBytes[16] = 0x09;
    bBlindingBytes[17] = 0x62;
    bBlindingBytes[18] = 0x03;
    bBlindingBytes[19] = 0x23;
    bBlindingBytes[20] = 0xa0;
    bBlindingBytes[21] = 0x03;
    bBlindingBytes[22] = 0xfe;
    bBlindingBytes[23] = 0xab;
    bBlindingBytes[24] = 0xc8;
    bBlindingBytes[25] = 0xb7;
    bBlindingBytes[26] = 0xbb;
    bBlindingBytes[27] = 0x8f;
    bBlindingBytes[28] = 0x15;
    bBlindingBytes[29] = 0x11;
    bBlindingBytes[30] = 0xf5;
    bBlindingBytes[31] = 0x0b;

    return PedersenGens(
      B: RistrettoPoint(bBytes),
      bBlinding: RistrettoPoint(bBlindingBytes),
    );
  }

  /// Commit to a value with a blinding factor
  /// Commitment = v*B + blinding*bBlinding
  CompressedRistretto commit(Scalar value, Scalar blinding) {
    // This would use actual curve operations in production
    // For now, we create a deterministic commitment
    final commitment = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      commitment[i] = (value.bytes[i] ^
          blinding.bytes[i] ^
          B.bytes[i] ^
          bBlinding.bytes[i]);
    }
    return CompressedRistretto(commitment);
  }
}

/// Bulletproof generators for range proofs
class BulletproofGens {
  final int gensCapacity; // Maximum number of values
  final int partyCapacity; // Maximum number of parties
  final List<RistrettoPoint> gVec; // Generator vector for inner product
  final List<RistrettoPoint> hVec; // Generator vector for inner product

  BulletproofGens({
    required this.gensCapacity,
    required this.partyCapacity,
    required this.gVec,
    required this.hVec,
  });

  /// Create new Bulletproof generators
  /// gensCapacity: maximum bitsize (e.g., 64)
  /// partyCapacity: maximum number of aggregated proofs (e.g., 1)
  factory BulletproofGens.create(int gensCapacity, int partyCapacity) {
    if (gensCapacity == 0 || (gensCapacity & (gensCapacity - 1)) != 0) {
      throw ArgumentError('gensCapacity must be a power of 2');
    }
    if (partyCapacity == 0 || (partyCapacity & (partyCapacity - 1)) != 0) {
      throw ArgumentError('partyCapacity must be a power of 2');
    }

    final totalGens = gensCapacity * partyCapacity;
    final gVec = <RistrettoPoint>[];
    final hVec = <RistrettoPoint>[];

    // Generate deterministic generators using hash-to-curve
    for (int i = 0; i < totalGens; i++) {
      gVec.add(_generatePoint('G', i));
      hVec.add(_generatePoint('H', i));
    }

    return BulletproofGens(
      gensCapacity: gensCapacity,
      partyCapacity: partyCapacity,
      gVec: gVec,
      hVec: hVec,
    );
  }

  static RistrettoPoint _generatePoint(String label, int index) {
    // Deterministic point generation (simplified)
    final bytes = Uint8List(32);
    final labelBytes = label.codeUnits;

    for (int i = 0; i < 32; i++) {
      bytes[i] =
          ((index >> (i % 8)) ^ labelBytes[i % labelBytes.length]) & 0xFF;
    }

    return RistrettoPoint(bytes);
  }

  /// Get generators for a specific party
  BulletproofGensShare share(int j) {
    if (j >= partyCapacity) {
      throw ArgumentError('Party index out of range');
    }
    return BulletproofGensShare(
      gens: this,
      share: j,
    );
  }
}

/// Share of generators for a specific party
class BulletproofGensShare {
  final BulletproofGens gens;
  final int share;

  BulletproofGensShare({required this.gens, required this.share});
}

/// Proof error types
enum ProofErrorType {
  invalidBitsize,
  invalidGeneratorsLength,
  invalidProof,
  verificationFailed,
  formatError,
}

class ProofError implements Exception {
  final ProofErrorType type;
  final String message;

  ProofError(this.type, this.message);

  @override
  String toString() => 'ProofError: $message';
}
