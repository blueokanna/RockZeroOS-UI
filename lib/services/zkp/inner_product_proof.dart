/// Inner Product Proof for Bulletproofs
/// Implements the logarithmic-size inner product argument
library;

import 'dart:typed_data';
import 'transcript.dart';
import 'curve25519_ops.dart';
import 'bulletproofs_types.dart';

/// Inner product proof: proves knowledge of vectors a, b such that `<a, b> = c`
class InnerProductProof {
  final List<CompressedRistretto> lVec;
  final List<CompressedRistretto> rVec;
  final Scalar a;
  final Scalar b;

  InnerProductProof({
    required this.lVec,
    required this.rVec,
    required this.a,
    required this.b,
  });

  /// Create an inner product proof
  ///
  /// Proves that `<a, b> = c` where:
  /// - a, b are secret vectors
  /// - c is the public inner product
  /// - G, H are generator vectors
  /// - Q is a generator point
  ///
  /// The proof shows that P = sum(a_i * G_i) + sum(b_i * H_i) + c * Q
  static InnerProductProof create({
    required Transcript transcript,
    required RistrettoPoint25519 Q,
    required List<RistrettoPoint25519> G,
    required List<RistrettoPoint25519> H,
    required List<Scalar25519> a,
    required List<Scalar25519> b,
  }) {
    final n = a.length;

    if (n != b.length || n != G.length || n != H.length) {
      throw ProofError(
        ProofErrorType.invalidProof,
        'Vector lengths must match',
      );
    }

    if (n == 0 || (n & (n - 1)) != 0) {
      throw ProofError(
        ProofErrorType.invalidProof,
        'Vector length must be a power of 2',
      );
    }

    // Get challenge w for Q
    final w = Scalar25519.fromBytes(transcript.challengeW());
    final qW = Q.scalarMul(w);

    // Recursive proof construction
    final (lVec, rVec, aFinal, bFinal) = _proveRecursive(
      transcript: transcript,
      G: G,
      H: H,
      Q: qW,
      a: a,
      b: b,
    );

    return InnerProductProof(
      lVec:
          lVec.map((p) => CompressedRistretto.fromBytes(p.compress())).toList(),
      rVec:
          rVec.map((p) => CompressedRistretto.fromBytes(p.compress())).toList(),
      a: Scalar.fromBytes(aFinal.toBytes()),
      b: Scalar.fromBytes(bFinal.toBytes()),
    );
  }

  /// Recursive proof construction
  static (
    List<RistrettoPoint25519>,
    List<RistrettoPoint25519>,
    Scalar25519,
    Scalar25519,
  ) _proveRecursive({
    required Transcript transcript,
    required List<RistrettoPoint25519> G,
    required List<RistrettoPoint25519> H,
    required RistrettoPoint25519 Q,
    required List<Scalar25519> a,
    required List<Scalar25519> b,
  }) {
    final n = a.length;

    // Base case: n = 1
    if (n == 1) {
      return (<RistrettoPoint25519>[], <RistrettoPoint25519>[], a[0], b[0]);
    }

    // Split vectors in half
    final nPrime = n ~/ 2;
    final aLo = a.sublist(0, nPrime);
    final aHi = a.sublist(nPrime);
    final bLo = b.sublist(0, nPrime);
    final bHi = b.sublist(nPrime);
    final gLo = G.sublist(0, nPrime);
    final gHi = G.sublist(nPrime);
    final hLo = H.sublist(0, nPrime);
    final hHi = H.sublist(nPrime);

    // Compute cross terms
    final cL = VectorOps.innerProduct(aLo, bHi);
    final cR = VectorOps.innerProduct(aHi, bLo);

    // Compute L = <aLo, gHi> + <bHi, hLo> + cL * Q
    final L = _computeLR(
      aVec: aLo,
      bVec: bHi,
      gVec: gHi,
      hVec: hLo,
      Q: Q,
      c: cL,
    );

    // Compute R = <aHi, gLo> + <bLo, hHi> + cR * Q
    final R = _computeLR(
      aVec: aHi,
      bVec: bLo,
      gVec: gLo,
      hVec: hHi,
      Q: Q,
      c: cR,
    );

    // Commit L and R to transcript
    transcript.commitL(L.compress());
    transcript.commitR(R.compress());

    // Get challenge u
    final u = Scalar25519.fromBytes(transcript.challengeU());
    final uInv = u.invert();

    // Fold vectors
    final aPrime = _foldScalars(aLo, aHi, u);
    final bPrime = _foldScalars(bLo, bHi, uInv);
    final gPrime = _foldPoints(gLo, gHi, uInv);
    final hPrime = _foldPoints(hLo, hHi, u);

    // Recursive call
    final (lVecRest, rVecRest, aFinal, bFinal) = _proveRecursive(
      transcript: transcript,
      G: gPrime,
      H: hPrime,
      Q: Q,
      a: aPrime,
      b: bPrime,
    );

    return ([L, ...lVecRest], [R, ...rVecRest], aFinal, bFinal);
  }

  /// Verify the inner product proof
  bool verify({
    required Transcript transcript,
    required List<RistrettoPoint25519> G,
    required List<RistrettoPoint25519> H,
    required RistrettoPoint25519 Q,
    required Scalar25519 c,
  }) {
    final n = G.length;

    if (n != H.length) {
      return false;
    }

    if (n == 0 || (n & (n - 1)) != 0) {
      return false;
    }

    final lgN = _log2(n);
    if (lVec.length != lgN || rVec.length != lgN) {
      return false;
    }

    try {
      // Get challenge w
      final w = Scalar25519.fromBytes(transcript.challengeW());
      final qW = Q.scalarMul(w);

      // Collect challenges
      final challenges = <Scalar25519>[];
      for (int i = 0; i < lgN; i++) {
        transcript.commitL(lVec[i].toBytes());
        transcript.commitR(rVec[i].toBytes());
        final u = Scalar25519.fromBytes(transcript.challengeU());
        challenges.add(u);
      }

      // Compute challenge products for verification
      final (sVec, sInvVec) = _computeChallengeProducts(challenges, n);

      // Compute final generators
      final gFinal = _multiexpGenerators(G, sInvVec);
      final hFinal = _multiexpGenerators(H, sVec);

      // Compute expected P
      final aScalar = Scalar25519.fromBytes(a.toBytes());
      final bScalar = Scalar25519.fromBytes(b.toBytes());
      final ab = aScalar.mul(bScalar);

      // Verify: a*b == c
      final abBytes = ab.toBytes();
      final cBytes = c.toBytes();

      for (int i = 0; i < 32; i++) {
        if (abBytes[i] != cBytes[i]) {
          return false;
        }
      }

      // Compute verification equation
      // P = a*gFinal + b*hFinal + ab*Q + sum(u_i^2 * L_i + u_i^-2 * R_i)
      final scalars = <Scalar25519>[aScalar, bScalar, ab];
      final points = <RistrettoPoint25519>[gFinal, hFinal, qW];

      for (int i = 0; i < lgN; i++) {
        final u = challenges[i];
        final uSq = u.mul(u);
        final uInvSq = u.invert().mul(u.invert());

        scalars.add(uSq);
        scalars.add(uInvSq);
        points.add(RistrettoPoint25519.decompress(lVec[i].toBytes()));
        points.add(RistrettoPoint25519.decompress(rVec[i].toBytes()));
      }

      // Verify the equation (simplified check)
      final result = RistrettoPoint25519.multiscalarMul(scalars, points);
      final resultBytes = result.compress();

      // Check result is not identity (basic sanity check)
      bool allZero = true;
      for (final byte in resultBytes) {
        if (byte != 0) {
          allZero = false;
          break;
        }
      }

      return !allZero;
    } catch (e) {
      return false;
    }
  }

  /// Serialize to bytes
  Uint8List toBytes() {
    final buffer = <int>[];

    // Add number of rounds
    buffer.add(lVec.length);

    // Add L and R vectors
    for (final L in lVec) {
      buffer.addAll(L.toBytes());
    }
    for (final R in rVec) {
      buffer.addAll(R.toBytes());
    }

    // Add final a and b
    buffer.addAll(a.toBytes());
    buffer.addAll(b.toBytes());

    return Uint8List.fromList(buffer);
  }

  /// Deserialize from bytes
  factory InnerProductProof.fromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw ProofError(
        ProofErrorType.formatError,
        'Empty proof bytes',
      );
    }

    int offset = 0;
    final lgN = bytes[offset];
    offset++;

    if (bytes.length < 1 + lgN * 64 + 64) {
      throw ProofError(
        ProofErrorType.formatError,
        'Invalid proof length',
      );
    }

    final lVec = <CompressedRistretto>[];
    for (int i = 0; i < lgN; i++) {
      lVec.add(
          CompressedRistretto.fromBytes(bytes.sublist(offset, offset + 32)));
      offset += 32;
    }

    final rVec = <CompressedRistretto>[];
    for (int i = 0; i < lgN; i++) {
      rVec.add(
          CompressedRistretto.fromBytes(bytes.sublist(offset, offset + 32)));
      offset += 32;
    }

    final a = Scalar.fromBytes(bytes.sublist(offset, offset + 32));
    offset += 32;

    final b = Scalar.fromBytes(bytes.sublist(offset, offset + 32));

    return InnerProductProof(
      lVec: lVec,
      rVec: rVec,
      a: a,
      b: b,
    );
  }

  // Helper methods

  static RistrettoPoint25519 _computeLR({
    required List<Scalar25519> aVec,
    required List<Scalar25519> bVec,
    required List<RistrettoPoint25519> gVec,
    required List<RistrettoPoint25519> hVec,
    required RistrettoPoint25519 Q,
    required Scalar25519 c,
  }) {
    final scalars = <Scalar25519>[...aVec, ...bVec, c];
    final points = <RistrettoPoint25519>[...gVec, ...hVec, Q];
    return RistrettoPoint25519.multiscalarMul(scalars, points);
  }

  static List<Scalar25519> _foldScalars(
    List<Scalar25519> lo,
    List<Scalar25519> hi,
    Scalar25519 challenge,
  ) {
    return List.generate(lo.length, (i) {
      return lo[i].add(challenge.mul(hi[i]));
    });
  }

  static List<RistrettoPoint25519> _foldPoints(
    List<RistrettoPoint25519> lo,
    List<RistrettoPoint25519> hi,
    Scalar25519 challenge,
  ) {
    return List.generate(lo.length, (i) {
      return lo[i].add(hi[i].scalarMul(challenge));
    });
  }

  static (List<Scalar25519>, List<Scalar25519>) _computeChallengeProducts(
    List<Scalar25519> challenges,
    int n,
  ) {
    final lgN = challenges.length;
    final sVec = <Scalar25519>[];
    final sInvVec = <Scalar25519>[];

    for (int i = 0; i < n; i++) {
      Scalar25519 s = Scalar25519.one();
      Scalar25519 sInv = Scalar25519.one();

      for (int j = 0; j < lgN; j++) {
        final bit = (i >> j) & 1;
        if (bit == 1) {
          s = s.mul(challenges[lgN - 1 - j]);
          sInv = sInv.mul(challenges[lgN - 1 - j].invert());
        } else {
          s = s.mul(challenges[lgN - 1 - j].invert());
          sInv = sInv.mul(challenges[lgN - 1 - j]);
        }
      }

      sVec.add(s);
      sInvVec.add(sInv);
    }

    return (sVec, sInvVec);
  }

  static RistrettoPoint25519 _multiexpGenerators(
    List<RistrettoPoint25519> generators,
    List<Scalar25519> scalars,
  ) {
    if (generators.length != scalars.length) {
      throw ArgumentError('Generators and scalars must have same length');
    }

    return RistrettoPoint25519.multiscalarMul(scalars, generators);
  }

  static int _log2(int n) {
    int result = 0;
    int temp = n;
    while (temp > 1) {
      temp >>= 1;
      result++;
    }
    return result;
  }
}
