/// Bulletproofs Integration Tests
///
/// Comprehensive tests for the Bulletproofs implementation
import 'package:flutter_test/flutter_test.dart';
import 'package:rockzero/services/zkp/bulletproofs.dart';

void main() {
  group('Bulletproofs Range Proofs', () {
    test('Create and verify 8-bit range proof', () {
      final result = Bulletproofs.createRangeProof(
        value: 42,
        bitLength: 8,
        label: 'test-8bit',
      );

      expect(result.proof, isNotNull);
      expect(result.commitment, isNotNull);
      expect(result.verify(), isTrue);
    });

    test('Create and verify 16-bit range proof', () {
      final result = Bulletproofs.createRangeProof(
        value: 1234,
        bitLength: 16,
        label: 'test-16bit',
      );

      expect(result.verify(), isTrue);
    });

    test('Create and verify 32-bit range proof', () {
      final result = Bulletproofs.createRangeProof(
        value: 1234567,
        bitLength: 32,
        label: 'test-32bit',
      );

      expect(result.verify(), isTrue);
    });

    test('Create and verify 64-bit range proof', () {
      final result = Bulletproofs.createRangeProof(
        value: 123456789,
        bitLength: 64,
        label: 'test-64bit',
      );

      expect(result.verify(), isTrue);
    });

    test('Reject out-of-range value', () {
      expect(
        () => Bulletproofs.createRangeProof(
          value: 256, // Out of range for 8 bits
          bitLength: 8,
        ),
        throwsArgumentError,
      );
    });

    test('Reject invalid bit length', () {
      expect(
        () => Bulletproofs.createRangeProof(
          value: 100,
          bitLength: 7, // Not a valid bit length
        ),
        throwsArgumentError,
      );
    });

    test('Reject negative value', () {
      expect(
        () => Bulletproofs.createRangeProof(
          value: -1,
          bitLength: 8,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Aggregated Range Proofs', () {
    test('Create and verify aggregated proof for 2 values', () {
      final result = Bulletproofs.createAggregatedRangeProof(
        values: [10, 20],
        bitLength: 8,
        label: 'test-agg-2',
      );

      expect(result.proof, isNotNull);
      expect(result.commitments.length, equals(2));
      expect(result.verify(), isTrue);
    });

    test('Create and verify aggregated proof for 4 values', () {
      final result = Bulletproofs.createAggregatedRangeProof(
        values: [10, 20, 30, 40],
        bitLength: 8,
        label: 'test-agg-4',
      );

      expect(result.commitments.length, equals(4));
      expect(result.verify(), isTrue);
    });

    test('Create and verify aggregated proof for 8 values', () {
      final result = Bulletproofs.createAggregatedRangeProof(
        values: [1, 2, 3, 4, 5, 6, 7, 8],
        bitLength: 8,
        label: 'test-agg-8',
      );

      expect(result.commitments.length, equals(8));
      expect(result.verify(), isTrue);
    });

    test('Reject non-power-of-2 length', () {
      expect(
        () => Bulletproofs.createAggregatedRangeProof(
          values: [1, 2, 3], // Length 3 is not power of 2
          bitLength: 8,
        ),
        throwsArgumentError,
      );
    });

    test('Reject empty values list', () {
      expect(
        () => Bulletproofs.createAggregatedRangeProof(
          values: [],
          bitLength: 8,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Serialization', () {
    test('Serialize and deserialize proof', () {
      final result = Bulletproofs.createRangeProof(
        value: 100,
        bitLength: 16,
        label: 'test-serialize',
      );

      final proofBytes = result.serializeProof();
      expect(proofBytes.length, greaterThan(0));

      final deserializedProof = Bulletproofs.deserializeProof(proofBytes);
      expect(deserializedProof, isNotNull);

      // Verify deserialized proof
      final valid = Bulletproofs.verifyRangeProof(
        proof: deserializedProof,
        commitment: result.commitment,
        bitLength: 16,
        label: 'test-serialize',
      );
      expect(valid, isTrue);
    });

    test('Serialize and deserialize commitment', () {
      final result = Bulletproofs.createRangeProof(
        value: 100,
        bitLength: 16,
        label: 'test-commitment',
      );

      final commitmentBytes = result.serializeCommitment();
      expect(commitmentBytes.length, equals(32));

      final deserializedCommitment =
          Bulletproofs.deserializeCommitment(commitmentBytes);
      expect(deserializedCommitment, isNotNull);

      // Verify with deserialized commitment
      final valid = Bulletproofs.verifyRangeProof(
        proof: result.proof,
        commitment: deserializedCommitment,
        bitLength: 16,
        label: 'test-commitment',
      );
      expect(valid, isTrue);
    });

    test('Serialize aggregated proof commitments', () {
      final result = Bulletproofs.createAggregatedRangeProof(
        values: [10, 20, 30, 40],
        bitLength: 8,
        label: 'test-agg-serialize',
      );

      final commitmentsList = result.serializeCommitments();
      expect(commitmentsList.length, equals(4));

      for (final bytes in commitmentsList) {
        expect(bytes.length, equals(32));
      }
    });
  });

  group('Verification Edge Cases', () {
    test('Verification fails with wrong bit length', () {
      final result = Bulletproofs.createRangeProof(
        value: 100,
        bitLength: 16,
        label: 'test-wrong-bitlen',
      );

      // Try to verify with wrong bit length
      final valid = Bulletproofs.verifyRangeProof(
        proof: result.proof,
        commitment: result.commitment,
        bitLength: 32, // Wrong bit length
        label: 'test-wrong-bitlen',
      );
      expect(valid, isFalse);
    });

    test('Verification fails with wrong label', () {
      final result = Bulletproofs.createRangeProof(
        value: 100,
        bitLength: 16,
        label: 'test-label-1',
      );

      // Try to verify with wrong label
      final valid = Bulletproofs.verifyRangeProof(
        proof: result.proof,
        commitment: result.commitment,
        bitLength: 16,
        label: 'test-label-2', // Wrong label
      );
      expect(valid, isFalse);
    });

    test('Verification fails with wrong commitment', () {
      final result1 = Bulletproofs.createRangeProof(
        value: 100,
        bitLength: 16,
        label: 'test-commitment-1',
      );

      final result2 = Bulletproofs.createRangeProof(
        value: 200,
        bitLength: 16,
        label: 'test-commitment-2',
      );

      // Try to verify proof1 with commitment2
      final valid = Bulletproofs.verifyRangeProof(
        proof: result1.proof,
        commitment: result2.commitment, // Wrong commitment
        bitLength: 16,
        label: 'test-commitment-1',
      );
      expect(valid, isFalse);
    });
  });

  group('Real-World Use Cases', () {
    test('Video streaming subscription level proof', () {
      // Subscription levels: 0=free, 1=basic, 2=premium, 3=enterprise
      final subscriptionLevel = 2; // Premium

      final result = Bulletproofs.createRangeProof(
        value: subscriptionLevel,
        bitLength: 8,
        label: 'video-subscription',
      );

      expect(result.verify(), isTrue);

      // Proof size should be reasonable
      final proofSize = result.serializeProof().length;
      expect(proofSize, lessThan(1000)); // Less than 1KB
    });

    test('Age verification proof', () {
      final age = 25;

      final result = Bulletproofs.createRangeProof(
        value: age,
        bitLength: 8,
        label: 'age-verification',
      );

      expect(result.verify(), isTrue);
    });

    test('Financial transaction amount proof', () {
      final amountInCents = 123456; // $1234.56

      final result = Bulletproofs.createRangeProof(
        value: amountInCents,
        bitLength: 32,
        label: 'transaction-amount',
      );

      expect(result.verify(), isTrue);
    });

    test('Batch user authentication', () {
      final userLevels = [1, 2, 3, 2, 1, 3, 2, 1]; // 8 users

      final result = Bulletproofs.createAggregatedRangeProof(
        values: userLevels,
        bitLength: 8,
        label: 'batch-auth',
      );

      expect(result.verify(), isTrue);

      // Aggregated proof should be more efficient than individual proofs
      final aggregatedSize = result.serializeProof().length;
      final individualSize = 700 * userLevels.length; // Estimated
      expect(aggregatedSize, lessThan(individualSize));
    });
  });

  group('Performance Tests', () {
    test('8-bit proof creation is fast', () {
      final stopwatch = Stopwatch()..start();

      Bulletproofs.createRangeProof(
        value: 42,
        bitLength: 8,
      );

      stopwatch.stop();
      print('8-bit proof creation: ${stopwatch.elapsedMilliseconds}ms');

      // Should complete in reasonable time (adjust based on device)
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });

    test('32-bit proof creation is fast', () {
      final stopwatch = Stopwatch()..start();

      Bulletproofs.createRangeProof(
        value: 1234567,
        bitLength: 32,
      );

      stopwatch.stop();
      print('32-bit proof creation: ${stopwatch.elapsedMilliseconds}ms');

      expect(stopwatch.elapsedMilliseconds, lessThan(10000));
    });

    test('Aggregated proof is efficient', () {
      final stopwatch = Stopwatch()..start();

      Bulletproofs.createAggregatedRangeProof(
        values: [1, 2, 3, 4],
        bitLength: 8,
      );

      stopwatch.stop();
      print('Aggregated proof (4 values): ${stopwatch.elapsedMilliseconds}ms');

      expect(stopwatch.elapsedMilliseconds, lessThan(10000));
    });
  });

  group('Proof Size Tests', () {
    test('8-bit proof size is reasonable', () {
      final result = Bulletproofs.createRangeProof(
        value: 42,
        bitLength: 8,
      );

      final proofSize = result.serializeProof().length;
      print('8-bit proof size: $proofSize bytes');

      // Should be around 672 bytes
      expect(proofSize, greaterThan(600));
      expect(proofSize, lessThan(800));
    });

    test('32-bit proof size is reasonable', () {
      final result = Bulletproofs.createRangeProof(
        value: 1234567,
        bitLength: 32,
      );

      final proofSize = result.serializeProof().length;
      print('32-bit proof size: $proofSize bytes');

      // Should be around 800 bytes
      expect(proofSize, greaterThan(700));
      expect(proofSize, lessThan(1000));
    });

    test('Commitment size is always 32 bytes', () {
      final result = Bulletproofs.createRangeProof(
        value: 100,
        bitLength: 16,
      );

      final commitmentSize = result.serializeCommitment().length;
      expect(commitmentSize, equals(32));
    });
  });

  group('Multiple Proofs', () {
    test('Create multiple independent proofs', () {
      final results = <BulletproofResult>[];

      for (int i = 0; i < 5; i++) {
        final result = Bulletproofs.createRangeProof(
          value: i * 10,
          bitLength: 8,
          label: 'test-multi-$i',
        );
        results.add(result);
      }

      // Verify all proofs
      for (final result in results) {
        expect(result.verify(), isTrue);
      }
    });

    test('Proofs with same value but different blinding are different', () {
      final result1 = Bulletproofs.createRangeProof(
        value: 100,
        bitLength: 16,
        label: 'test-same-value-1',
      );

      final result2 = Bulletproofs.createRangeProof(
        value: 100,
        bitLength: 16,
        label: 'test-same-value-2',
      );

      // Commitments should be different (different blinding factors)
      final commitment1Bytes = result1.serializeCommitment();
      final commitment2Bytes = result2.serializeCommitment();

      expect(commitment1Bytes, isNot(equals(commitment2Bytes)));
    });
  });
}
