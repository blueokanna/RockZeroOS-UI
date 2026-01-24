import 'dart:typed_data';
import 'dart:math' as math;
import 'bulletproofs_types.dart';
import 'transcript.dart';
import 'range_proof.dart';

/// Main Bulletproofs API
class Bulletproofs {
  /// Create a range proof for a single value
  ///
  /// Proves that `value` is in the range [0, 2^bitLength) without revealing
  /// the actual value.
  ///
  /// Parameters:
  /// - value: The secret value to prove (must be in range)
  /// - bitLength: Number of bits (must be 8, 16, 32, or 64)
  /// - label: Optional label for the transcript
  ///
  /// Returns: BulletproofResult containing proof and commitment
  static BulletproofResult createRangeProof({
    required int value,
    required int bitLength,
    String label = 'bulletproof',
  }) {
    // Validate inputs
    if (bitLength != 8 &&
        bitLength != 16 &&
        bitLength != 32 &&
        bitLength != 64) {
      throw ArgumentError('bitLength must be 8, 16, 32, or 64');
    }

    if (value < 0 || value >= (1 << bitLength)) {
      throw ArgumentError('Value out of range for specified bit length');
    }

    // Setup generators
    final pcGens = PedersenGens.defaultGens();
    final bpGens = BulletproofGens.create(bitLength, 1);

    // Generate random blinding factor
    final blinding = _generateRandomScalar();

    // Create transcript
    final transcript = Transcript(label);

    // Create proof
    final (proof, commitment) = RangeProof.proveSingle(
      bpGens: bpGens,
      pcGens: pcGens,
      transcript: transcript,
      value: value,
      blinding: blinding,
      n: bitLength,
    );

    return BulletproofResult(
      proof: proof,
      commitment: commitment,
      blinding: blinding,
      bitLength: bitLength,
      label: label,
    );
  }

  /// Verify a range proof
  ///
  /// Verifies that the commitment contains a value in [0, 2^bitLength)
  ///
  /// Parameters:
  /// - proof: The range proof to verify
  /// - commitment: The commitment to the value
  /// - bitLength: Number of bits (must match proof creation)
  /// - label: Label for the transcript (must match proof creation)
  ///
  /// Returns: true if proof is valid, false otherwise
  static bool verifyRangeProof({
    required RangeProof proof,
    required CompressedRistretto commitment,
    required int bitLength,
    String label = 'bulletproof',
  }) {
    try {
      // Setup generators (same as prover)
      final pcGens = PedersenGens.defaultGens();
      final bpGens = BulletproofGens.create(bitLength, 1);

      // Create transcript (same label as prover)
      final transcript = Transcript(label);

      // Verify proof
      return proof.verifySingle(
        bpGens: bpGens,
        pcGens: pcGens,
        transcript: transcript,
        commitment: commitment,
        n: bitLength,
      );
    } catch (e) {
      return false;
    }
  }

  /// Create an aggregated range proof for multiple values
  ///
  /// Proves that all values are in [0, 2^bitLength) in a single proof.
  /// This is more efficient than creating individual proofs.
  ///
  /// Parameters:
  /// - values: List of secret values to prove
  /// - bitLength: Number of bits for each value
  /// - label: Optional label for the transcript
  ///
  /// Returns: AggregatedBulletproofResult containing proof and commitments
  static AggregatedBulletproofResult createAggregatedRangeProof({
    required List<int> values,
    required int bitLength,
    String label = 'bulletproof-aggregated',
  }) {
    // Validate inputs
    if (values.isEmpty) {
      throw ArgumentError('Values list cannot be empty');
    }

    final m = values.length;
    if (m & (m - 1) != 0) {
      throw ArgumentError('Number of values must be a power of 2');
    }

    if (bitLength != 8 &&
        bitLength != 16 &&
        bitLength != 32 &&
        bitLength != 64) {
      throw ArgumentError('bitLength must be 8, 16, 32, or 64');
    }

    for (final value in values) {
      if (value < 0 || value >= (1 << bitLength)) {
        throw ArgumentError('Value out of range for specified bit length');
      }
    }

    // Setup generators
    final pcGens = PedersenGens.defaultGens();
    final bpGens = BulletproofGens.create(bitLength, m);

    // Generate random blinding factors
    final blindings = List.generate(m, (_) => _generateRandomScalar());

    // Create transcript
    final transcript = Transcript(label);

    // Create proof
    final (proof, commitments) = RangeProof.proveMultiple(
      bpGens: bpGens,
      pcGens: pcGens,
      transcript: transcript,
      values: values,
      blindings: blindings,
      n: bitLength,
    );

    return AggregatedBulletproofResult(
      proof: proof,
      commitments: commitments,
      blindings: blindings,
      bitLength: bitLength,
      label: label,
    );
  }

  /// Verify an aggregated range proof
  ///
  /// Verifies that all commitments contain values in [0, 2^bitLength)
  ///
  /// Parameters:
  /// - proof: The aggregated range proof to verify
  /// - commitments: List of commitments to verify
  /// - bitLength: Number of bits (must match proof creation)
  /// - label: Label for the transcript (must match proof creation)
  ///
  /// Returns: true if proof is valid, false otherwise
  static bool verifyAggregatedRangeProof({
    required RangeProof proof,
    required List<CompressedRistretto> commitments,
    required int bitLength,
    String label = 'bulletproof-aggregated',
  }) {
    try {
      final m = commitments.length;

      // Setup generators (same as prover)
      final pcGens = PedersenGens.defaultGens();
      final bpGens = BulletproofGens.create(bitLength, m);

      // Create transcript (same label as prover)
      final transcript = Transcript(label);

      // Verify proof
      return proof.verifyMultiple(
        bpGens: bpGens,
        pcGens: pcGens,
        transcript: transcript,
        commitments: commitments,
        n: bitLength,
      );
    } catch (e) {
      return false;
    }
  }

  /// Serialize a proof to bytes for storage or transmission
  static Uint8List serializeProof(RangeProof proof) {
    return proof.toBytes();
  }

  /// Deserialize a proof from bytes
  static RangeProof deserializeProof(Uint8List bytes) {
    return RangeProof.fromBytes(bytes);
  }

  /// Serialize a commitment to bytes
  static Uint8List serializeCommitment(CompressedRistretto commitment) {
    return commitment.toBytes();
  }

  /// Deserialize a commitment from bytes
  static CompressedRistretto deserializeCommitment(Uint8List bytes) {
    return CompressedRistretto.fromBytes(bytes);
  }
}

/// Result of creating a single range proof
class BulletproofResult {
  final RangeProof proof;
  final CompressedRistretto commitment;
  final Scalar blinding;
  final int bitLength;
  final String label;

  BulletproofResult({
    required this.proof,
    required this.commitment,
    required this.blinding,
    required this.bitLength,
    required this.label,
  });

  /// Verify this proof
  bool verify() {
    return Bulletproofs.verifyRangeProof(
      proof: proof,
      commitment: commitment,
      bitLength: bitLength,
      label: label,
    );
  }

  /// Serialize proof to bytes
  Uint8List serializeProof() => proof.toBytes();

  /// Serialize commitment to bytes
  Uint8List serializeCommitment() => commitment.toBytes();
}

/// Result of creating an aggregated range proof
class AggregatedBulletproofResult {
  final RangeProof proof;
  final List<CompressedRistretto> commitments;
  final List<Scalar> blindings;
  final int bitLength;
  final String label;

  AggregatedBulletproofResult({
    required this.proof,
    required this.commitments,
    required this.blindings,
    required this.bitLength,
    required this.label,
  });

  /// Verify this proof
  bool verify() {
    return Bulletproofs.verifyAggregatedRangeProof(
      proof: proof,
      commitments: commitments,
      bitLength: bitLength,
      label: label,
    );
  }

  /// Serialize proof to bytes
  Uint8List serializeProof() => proof.toBytes();

  /// Serialize all commitments to bytes
  List<Uint8List> serializeCommitments() {
    return commitments.map((c) => c.toBytes()).toList();
  }
}

/// Helper function to generate random scalar
Scalar _generateRandomScalar() {
  final random = math.Random.secure();
  final bytes = Uint8List(32);
  for (int i = 0; i < 32; i++) {
    bytes[i] = random.nextInt(256);
  }
  return Scalar.fromBytes(bytes);
}
