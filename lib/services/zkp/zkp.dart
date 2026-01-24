// Export all public APIs
export 'bulletproofs.dart';
export 'bulletproofs_types.dart';
export 'transcript.dart';
export 'range_proof.dart';
export 'hls_bulletproof_auth.dart';
export 'zkp_ffi.dart';

// Re-export commonly used types for convenience
export 'bulletproofs_types.dart'
    show
        Scalar,
        RistrettoPoint,
        CompressedRistretto,
        PedersenGens,
        BulletproofGens,
        ProofError,
        ProofErrorType;

export 'bulletproofs.dart'
    show Bulletproofs, BulletproofResult, AggregatedBulletproofResult;

export 'range_proof.dart' show RangeProof;

export 'transcript.dart' show Transcript;

export 'zkp_ffi.dart'
    show
        RockZeroZkpFfi,
        PasswordRegistration,
        SchnorrProof,
        BoundStrengthProof,
        EnhancedPasswordProof,
        ZkpFfiError;

export 'hls_bulletproof_auth.dart'
    show
        HlsBulletproofAuth,
        HlsProofResult;
