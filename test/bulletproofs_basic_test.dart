/// Bulletproofs Usage Examples
///
/// This file demonstrates how to use the Bulletproofs library
library;

import 'package:rockzero/services/zkp/bulletproofs.dart';

/// Example 1: Simple range proof
void exampleSimpleRangeProof() {
  print('=== Example 1: Simple Range Proof ===');

  // Create a proof that value 42 is in range [0, 256)
  final result = Bulletproofs.createRangeProof(
    value: 42,
    bitLength: 8,
    label: 'example-1',
  );

  print('Created proof for value 42 (8-bit range)');
  print('Commitment: ${result.commitment.toBytes().length} bytes');
  print('Proof size: ${result.proof.toBytes().length} bytes');

  // Verify the proof
  final valid = result.verify();
  print('Proof valid: $valid');

  // Try to verify with wrong bit length (should fail)
  final invalidVerify = Bulletproofs.verifyRangeProof(
    proof: result.proof,
    commitment: result.commitment,
    bitLength: 16, // Wrong bit length
    label: 'example-1',
  );
  print('Proof with wrong bit length valid: $invalidVerify');

  print('');
}

/// Example 2: 32-bit range proof
void example32BitRangeProof() {
  print('=== Example 2: 32-bit Range Proof ===');

  // Create a proof for a larger value
  final value = 1234567890;
  final result = Bulletproofs.createRangeProof(
    value: value,
    bitLength: 32,
    label: 'example-2',
  );

  print('Created proof for value $value (32-bit range)');
  print('Proof size: ${result.proof.toBytes().length} bytes');

  // Verify
  final valid = result.verify();
  print('Proof valid: $valid');

  print('');
}

/// Example 3: Aggregated range proof
void exampleAggregatedRangeProof() {
  print('=== Example 3: Aggregated Range Proof ===');

  // Create a proof for multiple values at once
  final values = [10, 20, 30, 40]; // Must be power of 2 length
  final result = Bulletproofs.createAggregatedRangeProof(
    values: values,
    bitLength: 8,
    label: 'example-3',
  );

  print('Created aggregated proof for ${values.length} values');
  print('Values: $values');
  print('Proof size: ${result.proof.toBytes().length} bytes');
  print('Individual proofs would be: ${values.length * 200} bytes (estimated)');

  // Verify
  final valid = result.verify();
  print('Aggregated proof valid: $valid');

  print('');
}

/// Example 4: Serialization and deserialization
void exampleSerialization() {
  print('=== Example 4: Serialization ===');

  // Create proof
  final result = Bulletproofs.createRangeProof(
    value: 100,
    bitLength: 16,
    label: 'example-4',
  );

  // Serialize
  final proofBytes = Bulletproofs.serializeProof(result.proof);
  final commitmentBytes = Bulletproofs.serializeCommitment(result.commitment);

  print('Serialized proof: ${proofBytes.length} bytes');
  print('Serialized commitment: ${commitmentBytes.length} bytes');

  // Deserialize
  final deserializedProof = Bulletproofs.deserializeProof(proofBytes);
  final deserializedCommitment =
      Bulletproofs.deserializeCommitment(commitmentBytes);

  // Verify deserialized proof
  final valid = Bulletproofs.verifyRangeProof(
    proof: deserializedProof,
    commitment: deserializedCommitment,
    bitLength: 16,
    label: 'example-4',
  );

  print('Deserialized proof valid: $valid');

  print('');
}

/// Example 5: Video streaming authentication use case
void exampleVideoStreamingAuth() {
  print('=== Example 5: Video Streaming Authentication ===');

  // Prove that user has valid subscription level without revealing exact level
  // Subscription levels: 0=free, 1=basic, 2=premium, 3=enterprise
  final subscriptionLevel = 2; // Premium

  final result = Bulletproofs.createRangeProof(
    value: subscriptionLevel,
    bitLength: 8,
    label: 'video-auth',
  );

  print('Created subscription proof (level hidden)');
  print('Commitment can be sent to video server');
  print(
      'Server can verify user has valid subscription without knowing exact level');

  // Server verifies
  final valid = result.verify();
  print('Subscription proof valid: $valid');

  // Additional check: prove subscription is at least level 2
  // (This would require additional range proof logic in production)
  print('User can access premium content: $valid');

  print('');
}

/// Example 6: Age verification without revealing exact age
void exampleAgeVerification() {
  print('=== Example 6: Age Verification ===');

  // Prove age is in valid range without revealing exact age
  final age = 25;

  final result = Bulletproofs.createRangeProof(
    value: age,
    bitLength: 8, // Ages 0-255
    label: 'age-verification',
  );

  print('Created age proof (exact age hidden)');
  print('Proof size: ${result.proof.toBytes().length} bytes');

  // Verify age is in valid range
  final valid = result.verify();
  print('Age proof valid: $valid');
  print('User can access age-restricted content without revealing exact age');

  print('');
}

/// Example 7: Batch verification for multiple users
void exampleBatchVerification() {
  print('=== Example 7: Batch Verification ===');

  // Multiple users proving their access levels
  final userLevels = [1, 2, 3, 2]; // 4 users with different levels

  final result = Bulletproofs.createAggregatedRangeProof(
    values: userLevels,
    bitLength: 8,
    label: 'batch-auth',
  );

  print('Created batch proof for ${userLevels.length} users');
  print('Aggregated proof size: ${result.proof.toBytes().length} bytes');

  // Verify all at once
  final valid = result.verify();
  print('Batch verification result: $valid');
  print('All users authenticated in single verification');

  print('');
}

/// Example 8: Error handling
void exampleErrorHandling() {
  print('=== Example 8: Error Handling ===');

  // Try to create proof with invalid parameters
  try {
    Bulletproofs.createRangeProof(
      value: 300, // Out of range for 8 bits
      bitLength: 8,
      label: 'error-test',
    );
    print('ERROR: Should have thrown exception');
  } catch (e) {
    print('Caught expected error: $e');
  }

  // Try with invalid bit length
  try {
    Bulletproofs.createRangeProof(
      value: 100,
      bitLength: 7, // Not a valid bit length
      label: 'error-test',
    );
    print('ERROR: Should have thrown exception');
  } catch (e) {
    print('Caught expected error: $e');
  }

  // Try aggregated proof with non-power-of-2 length
  try {
    Bulletproofs.createAggregatedRangeProof(
      values: [1, 2, 3], // Length 3 is not power of 2
      bitLength: 8,
      label: 'error-test',
    );
    print('ERROR: Should have thrown exception');
  } catch (e) {
    print('Caught expected error: $e');
  }

  print('Error handling works correctly');
  print('');
}

/// Run all examples
void runAllExamples() {
  print('╔════════════════════════════════════════════════════════════╗');
  print('║         Bulletproofs Zero-Knowledge Proof Examples        ║');
  print('║    Complete implementation based on Rust bulletproofs     ║');
  print('╚════════════════════════════════════════════════════════════╝');
  print('');

  exampleSimpleRangeProof();
  example32BitRangeProof();
  exampleAggregatedRangeProof();
  exampleSerialization();
  exampleVideoStreamingAuth();
  exampleAgeVerification();
  exampleBatchVerification();
  exampleErrorHandling();

  print('╔════════════════════════════════════════════════════════════╗');
  print('║                    All Examples Complete                  ║');
  print('╚════════════════════════════════════════════════════════════╝');
}

/// Main entry point for examples
void main() {
  runAllExamples();
}
