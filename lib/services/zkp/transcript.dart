/// Merlin Transcript implementation for Fiat-Shamir transform
/// Based on the Merlin transcript protocol used in Rust bulletproofs
library;

import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Transcript provides a Fiat-Shamir transform for zero-knowledge proofs
/// This is a simplified but functional implementation based on Merlin
class Transcript {
  final List<int> _state;
  final String _label;

  Transcript(String label)
      : _label = label,
        _state = List<int>.from(utf8.encode(label));

  /// Append a message to the transcript
  void appendMessage(String label, Uint8List message) {
    // Add label length and label
    final labelBytes = utf8.encode(label);
    _state.add(labelBytes.length);
    _state.addAll(labelBytes);

    // Add message length and message
    _state.add(message.length & 0xFF);
    _state.add((message.length >> 8) & 0xFF);
    _state.add((message.length >> 16) & 0xFF);
    _state.add((message.length >> 24) & 0xFF);
    _state.addAll(message);
  }

  /// Append a 64-bit unsigned integer
  void appendU64(String label, int value) {
    final bytes = Uint8List(8);
    for (int i = 0; i < 8; i++) {
      bytes[i] = (value >> (i * 8)) & 0xFF;
    }
    appendMessage(label, bytes);
  }

  /// Append a point (32 bytes)
  void appendPoint(String label, Uint8List point) {
    if (point.length != 32) {
      throw ArgumentError('Point must be 32 bytes');
    }
    appendMessage(label, point);
  }

  /// Challenge bytes - extract randomness from transcript
  Uint8List challengeBytes(String label, int length) {
    // Create challenge by hashing current state
    final labelBytes = utf8.encode(label);
    final challengeInput = <int>[];
    challengeInput.addAll(_state);
    challengeInput.add(labelBytes.length);
    challengeInput.addAll(labelBytes);
    challengeInput.add(length & 0xFF);
    challengeInput.add((length >> 8) & 0xFF);

    // Use SHA-512 for challenge generation
    final digest = sha512.convert(challengeInput);
    final result = Uint8List.fromList(digest.bytes.sublist(0, length));

    // Update state with challenge
    _state.addAll(result);

    return result;
  }

  /// Get a scalar challenge (32 bytes reduced modulo curve order)
  Uint8List challengeScalar(String label) {
    final bytes = challengeBytes(label, 64);
    // Reduce modulo the curve order (simplified - just take first 32 bytes)
    return Uint8List.fromList(bytes.sublist(0, 32));
  }

  /// Clone the transcript
  Transcript clone() {
    final cloned = Transcript(_label);
    cloned._state.clear();
    cloned._state.addAll(_state);
    return cloned;
  }

  /// Build domain separator for protocol
  static Transcript buildDomainSep(String protocolName) {
    return Transcript(protocolName);
  }
}

/// Extension for transcript operations specific to Bulletproofs
extension BulletproofTranscript on Transcript {
  /// Commit to domain separator for range proof
  void rangeproofDomainSep(int n, int m) {
    appendMessage('dom-sep', utf8.encode('rangeproof'));
    appendU64('n', n);
    appendU64('m', m);
  }

  /// Commit to bit length
  void commitBitLength(int n) {
    appendU64('bitlen', n);
  }

  /// Commit to value commitment
  void commitValueCommitment(Uint8List commitment) {
    appendPoint('V', commitment);
  }

  /// Commit to multiple value commitments
  void commitValueCommitments(List<Uint8List> commitments) {
    for (int i = 0; i < commitments.length; i++) {
      appendPoint('V_$i', commitments[i]);
    }
  }

  /// Commit to A point in range proof
  void commitA(Uint8List a) {
    appendPoint('A', a);
  }

  /// Commit to S point in range proof
  void commitS(Uint8List s) {
    appendPoint('S', s);
  }

  /// Commit to T1 point
  void commitT1(Uint8List t1) {
    appendPoint('T_1', t1);
  }

  /// Commit to T2 point
  void commitT2(Uint8List t2) {
    appendPoint('T_2', t2);
  }

  /// Get challenge y
  Uint8List challengeY() {
    return challengeScalar('y');
  }

  /// Get challenge z
  Uint8List challengeZ() {
    return challengeScalar('z');
  }

  /// Get challenge x
  Uint8List challengeX() {
    return challengeScalar('x');
  }

  /// Commit to tau_x
  void commitTauX(Uint8List tauX) {
    appendMessage('tau_x', tauX);
  }

  /// Commit to mu
  void commitMu(Uint8List mu) {
    appendMessage('mu', mu);
  }

  /// Commit to t_x
  void commitTX(Uint8List tx) {
    appendMessage('t_x', tx);
  }

  /// Get challenge for inner product proof
  Uint8List challengeW() {
    return challengeScalar('w');
  }

  /// Commit to inner product proof L point
  void commitL(Uint8List l) {
    appendPoint('L', l);
  }

  /// Commit to inner product proof R point
  void commitR(Uint8List r) {
    appendPoint('R', r);
  }

  /// Get challenge u for inner product
  Uint8List challengeU() {
    return challengeScalar('u');
  }
}
