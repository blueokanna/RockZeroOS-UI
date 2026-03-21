import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thirds/blake3.dart' as blake3;

import '../../services/bulletproofs_ffi.dart';
import '../network/api_service.dart';

final zkpAuthServiceProvider = Provider<ZkpAuthService>((ref) {
  final api = ref.read(apiServiceProvider);
  return ZkpAuthService(api);
});

class ZkpRegistration {
  final String commitment;
  final String salt;

  ZkpRegistration({required this.commitment, required this.salt});

  factory ZkpRegistration.fromJson(Map<String, dynamic> json) {
    return ZkpRegistration(
      commitment: json['commitment'] ?? '',
      salt: json['salt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'commitment': commitment,
        'salt': salt,
      };

  @override
  String toString() =>
      'ZkpRegistration(commitment: ${commitment.substring(0, min(20, commitment.length))}...)';
}

class RangeProofData {
  final String proof;
  final String commitment;

  RangeProofData({
    required this.proof,
    required this.commitment,
  });

  factory RangeProofData.fromJson(Map<String, dynamic> json) {
    return RangeProofData(
      proof: json['proof'] ?? '',
      commitment: json['commitment'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'proof': proof,
        'commitment': commitment,
      };
}

class EnhancedPasswordProof {
  final RangeProofData passwordRangeProof;
  final RangeProofData entropyRangeProof;
  final int timestamp;
  final String nonce;
  final String context;

  EnhancedPasswordProof({
    required this.passwordRangeProof,
    required this.entropyRangeProof,
    required this.timestamp,
    required this.nonce,
    required this.context,
  });

  factory EnhancedPasswordProof.fromJson(Map<String, dynamic> json) {
    return EnhancedPasswordProof(
      passwordRangeProof:
          RangeProofData.fromJson(json['password_range_proof'] ?? {}),
      entropyRangeProof:
          RangeProofData.fromJson(json['entropy_range_proof'] ?? {}),
      timestamp: json['timestamp'] ?? 0,
      nonce: json['nonce'] ?? '',
      context: json['context'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'password_range_proof': passwordRangeProof.toJson(),
        'entropy_range_proof': entropyRangeProof.toJson(),
        'timestamp': timestamp,
        'nonce': nonce,
        'context': context,
      };
}

class ZkpAuthService {
  final ApiService _api;
  BulletproofsService? _bulletproofsService;

  ZkpAuthService(this._api);

  Future<void> initialize(String baseUrl, String jwtToken) async {
    _bulletproofsService = BulletproofsService(
      baseUrl: baseUrl,
      jwtToken: jwtToken,
    );
    await _bulletproofsService!.initialize();
    debugPrint('[ZKP] Service initialized');
  }

  Future<ZkpRegistration?> getRegistration(String username) async {
    try {
      debugPrint('[ZKP] Getting registration for: $username');
      final response = await _api.post(
        '/api/v1/auth/zkp/registration',
        data: {'username': username},
      );

      if (response.data['success'] == true) {
        return ZkpRegistration.fromJson(response.data);
      }
      return ZkpRegistration.fromJson(response.data);
    } catch (e) {
      debugPrint('[ZKP] Failed to get registration: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> zkpLogin(
    String username,
    String password,
  ) async {
    try {
      debugPrint('[ZKP] Starting ZKP login for: $username');

      final registration = await getRegistration(username);
      if (registration == null) {
        debugPrint('[ZKP] Failed to get registration');
        return {'success': false, 'error': 'Cannot get ZKP registration'};
      }

      final proof = await _generateEnhancedProofViaServer(
        username,
        password,
        registration,
        'login',
      );

      if (proof == null) {
        debugPrint('[ZKP] Failed to generate proof');
        return {'success': false, 'error': 'Failed to generate ZKP proof'};
      }

      final response = await _api.post(
        '/api/v1/auth/zkp/login',
        data: {
          'username': username,
          'proof': proof,
        },
      );

      debugPrint('[ZKP] Login response: ${response.data}');
      return response.data;
    } catch (e) {
      debugPrint('[ZKP] Login failed: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> _generateEnhancedProofViaServer(
    String username,
    String password,
    ZkpRegistration registration,
    String context,
  ) async {
    try {
      debugPrint('[ZKP] Generating proof via server for context: $context');

      final response = await _api.post(
        '/api/v1/zkp/proof/generate',
        data: {
          'username': username,
          'password': password,
          'registration': registration.toJson(),
          'context': context,
        },
      );

      if (response.data['success'] == true) {
        return response.data['proof'];
      }

      debugPrint(
          '[ZKP] Server proof generation failed: ${response.data['error']}');
      return null;
    } catch (e) {
      debugPrint('[ZKP] Server proof generation error: $e');
      return null;
    }
  }

  Future<String?> createSearchToken(String keyword) async {
    try {
      final keywordHash = blake3.blake3(
        utf8.encode(keyword.toLowerCase()),
        32,
      );
      final keywordHashHex =
          keywordHash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      debugPrint(
          '[ZKP] Creating search token for keyword hash: ${keywordHashHex.substring(0, 16)}...');

      final response = await _api.post(
        '/api/v1/zkp/search/token',
        data: {'keyword_hash': keywordHashHex},
      );

      if (response.data['success'] == true) {
        return response.data['token_id'];
      }
      return null;
    } catch (e) {
      debugPrint('[ZKP] Create search token failed: $e');
      return null;
    }
  }

  Future<List<String>?> executeEncryptedSearch(String tokenId) async {
    try {
      debugPrint('[ZKP] Executing encrypted search with token: $tokenId');

      final response = await _api.post(
        '/api/v1/zkp/search/execute',
        data: {'token_id': tokenId},
      );

      if (response.data['success'] == true) {
        final results = response.data['encrypted_results'] as List<dynamic>?;
        return results?.map((e) => e.toString()).toList();
      }
      return null;
    } catch (e) {
      debugPrint('[ZKP] Execute encrypted search failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> createShareProof(
    String fileId,
    String permissionLevel,
  ) async {
    try {
      debugPrint(
          '[ZKP] Creating share proof for file: $fileId, permission: $permissionLevel');

      final response = await _api.post(
        '/api/v1/zkp/share/proof',
        data: {
          'file_id': fileId,
          'permission_level': permissionLevel,
        },
      );

      return response.data;
    } catch (e) {
      debugPrint('[ZKP] Create share proof failed: $e');
      return null;
    }
  }

  Future<bool> verifyShareProof(
    String proofId,
    String fileId,
    String requiredPermission,
  ) async {
    try {
      debugPrint('[ZKP] Verifying share proof: $proofId for file: $fileId');

      final response = await _api.post(
        '/api/v1/zkp/share/verify',
        data: {
          'proof_id': proofId,
          'file_id': fileId,
          'required_permission': requiredPermission,
        },
      );

      return response.data['success'] == true;
    } catch (e) {
      debugPrint('[ZKP] Verify share proof failed: $e');
      return false;
    }
  }

  Future<VideoStreamProof?> createVideoStreamProof({
    required String sessionId,
    required int segmentIndex,
    required Uint8List content,
  }) async {
    if (_bulletproofsService == null) {
      debugPrint('[ZKP] BulletproofsService not initialized');
      return null;
    }

    debugPrint('[ZKP] Creating video stream proof for segment: $segmentIndex');
    return _bulletproofsService!.createVideoStreamProof(
      sessionId: sessionId,
      segmentIndex: segmentIndex,
      content: content,
    );
  }

  Future<bool> verifyVideoStreamProof(VideoStreamProof proof) async {
    if (_bulletproofsService == null) {
      debugPrint('[ZKP] BulletproofsService not initialized');
      return false;
    }

    debugPrint(
        '[ZKP] Verifying video stream proof for segment: ${proof.segmentIndex}');
    return _bulletproofsService!.verifyVideoStreamProof(proof);
  }

  Future<BulletproofsRangeProof?> createRangeProof(int value) async {
    if (_bulletproofsService == null) {
      debugPrint('[ZKP] BulletproofsService not initialized');
      return null;
    }

    debugPrint('[ZKP] Creating range proof for value: $value');
    return _bulletproofsService!.createRangeProof(value);
  }

  Future<bool> verifyRangeProof(BulletproofsRangeProof proof) async {
    if (_bulletproofsService == null) {
      debugPrint('[ZKP] BulletproofsService not initialized');
      return false;
    }

    return _bulletproofsService!.verifyRangeProof(proof);
  }

  static int calculatePasswordEntropy(String password) {
    if (password.isEmpty) return 0;

    final charCounts = <String, int>{};
    for (final char in password.split('')) {
      charCounts[char] = (charCounts[char] ?? 0) + 1;
    }

    final length = password.length.toDouble();
    var entropy = 0.0;
    for (final count in charCounts.values) {
      final probability = count / length;
      entropy -= probability * (probability > 0 ? log2(probability) : 0);
    }

    return ((entropy * length) * 0.7).toInt();
  }

  static double log2(double x) => x > 0 ? (ln(x) / ln(2)) : 0;
  static double ln(double x) => x > 0 ? _ln(x) : 0;

  static double _ln(double x) {
    if (x <= 0) return double.negativeInfinity;
    if (x == 1) return 0;

    var n = 0;
    while (x > 1.5) {
      x /= 2.718281828;
      n++;
    }
    while (x < 0.5) {
      x *= 2.718281828;
      n--;
    }

    final y = x - 1;
    var result = 0.0;
    var term = y;
    for (var i = 1; i <= 20; i++) {
      result += term / i;
      term *= -y;
    }

    return result + n;
  }
}
