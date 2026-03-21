import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef BulletproofsCreateRangeProofNative = Int32 Function(
  Uint64 value,
  Pointer<Pointer<Uint8>> outProof,
  Pointer<IntPtr> outProofLen,
);
typedef BulletproofsCreateRangeProofDart = int Function(
  int value,
  Pointer<Pointer<Uint8>> outProof,
  Pointer<IntPtr> outProofLen,
);

typedef BulletproofsVerifyRangeProofNative = Int32 Function(
  Pointer<Uint8> proofJson,
  IntPtr proofJsonLen,
);
typedef BulletproofsVerifyRangeProofDart = int Function(
  Pointer<Uint8> proofJson,
  int proofJsonLen,
);

typedef BulletproofsFreeNative = Void Function(Pointer<Uint8> ptr, IntPtr len);
typedef BulletproofsFreeDart = void Function(Pointer<Uint8> ptr, int len);

class BulletproofsRangeProof {
  final String proof;
  final String commitment;
  final String valueBlinding;

  BulletproofsRangeProof({
    required this.proof,
    required this.commitment,
    required this.valueBlinding,
  });

  factory BulletproofsRangeProof.fromJson(Map<String, dynamic> json) {
    return BulletproofsRangeProof(
      proof: json['proof'] ?? '',
      commitment: json['commitment'] ?? '',
      valueBlinding: json['value_blinding'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'proof': proof,
        'commitment': commitment,
        'value_blinding': valueBlinding,
      };

  @override
  String toString() =>
      'BulletproofsRangeProof(proof: ${proof.substring(0, 20)}..., commitment: ${commitment.substring(0, 20)}...)';
}

class VideoStreamProof {
  final String sessionId;
  final int segmentIndex;
  final int timestamp;
  final BulletproofsRangeProof rangeProof;
  final String contentHash;
  final String signature;

  VideoStreamProof({
    required this.sessionId,
    required this.segmentIndex,
    required this.timestamp,
    required this.rangeProof,
    required this.contentHash,
    required this.signature,
  });

  factory VideoStreamProof.fromJson(Map<String, dynamic> json) {
    return VideoStreamProof(
      sessionId: json['session_id'] ?? '',
      segmentIndex: json['segment_index'] ?? 0,
      timestamp: json['timestamp'] ?? 0,
      rangeProof: BulletproofsRangeProof.fromJson(json['range_proof'] ?? {}),
      contentHash: json['content_hash'] ?? '',
      signature: json['signature'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'segment_index': segmentIndex,
        'timestamp': timestamp,
        'range_proof': rangeProof.toJson(),
        'content_hash': contentHash,
        'signature': signature,
      };

  @override
  String toString() =>
      'VideoStreamProof(sessionId: $sessionId, segmentIndex: $segmentIndex)';
}

class BulletproofsFFI {
  static BulletproofsFFI? _instance;
  DynamicLibrary? _lib;
  bool _isInitialized = false;

  BulletproofsCreateRangeProofDart? _createRangeProof;
  BulletproofsVerifyRangeProofDart? _verifyRangeProof;
  BulletproofsFreeDart? _free;

  BulletproofsFFI._();

  static BulletproofsFFI get instance {
    _instance ??= BulletproofsFFI._();
    return _instance!;
  }

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _lib = _loadLibrary();
      if (_lib == null) {
        debugPrint('[BulletproofsFFI] Library not found, using HTTP fallback');
        return;
      }

      _createRangeProof = _lib!
          .lookup<NativeFunction<BulletproofsCreateRangeProofNative>>(
              'bulletproofs_create_range_proof')
          .asFunction<BulletproofsCreateRangeProofDart>();

      _verifyRangeProof = _lib!
          .lookup<NativeFunction<BulletproofsVerifyRangeProofNative>>(
              'bulletproofs_verify_range_proof')
          .asFunction<BulletproofsVerifyRangeProofDart>();

      _free = _lib!
          .lookup<NativeFunction<BulletproofsFreeNative>>('bulletproofs_free')
          .asFunction<BulletproofsFreeDart>();

      _isInitialized = true;
      debugPrint('[BulletproofsFFI] Native library loaded successfully');
    } catch (e) {
      debugPrint('[BulletproofsFFI] Failed to load native library: $e');
    }
  }

  DynamicLibrary? _loadLibrary() {
    try {
      if (Platform.isAndroid) {
        return DynamicLibrary.open('librockzero_crypto.so');
      } else if (Platform.isIOS) {
        return DynamicLibrary.process();
      } else if (Platform.isLinux) {
        return DynamicLibrary.open('librockzero_crypto.so');
      } else if (Platform.isMacOS) {
        return DynamicLibrary.open('librockzero_crypto.dylib');
      } else if (Platform.isWindows) {
        return DynamicLibrary.open('rockzero_crypto.dll');
      }
    } catch (e) {
      debugPrint('[BulletproofsFFI] Library load error: $e');
    }
    return null;
  }

  BulletproofsRangeProof? createRangeProofNative(int value) {
    if (!_isInitialized || _createRangeProof == null) {
      return null;
    }

    final outProof = calloc<Pointer<Uint8>>();
    final outProofLen = calloc<IntPtr>();

    try {
      final result = _createRangeProof!(value, outProof, outProofLen);

      if (result != 0) {
        debugPrint('[BulletproofsFFI] createRangeProof failed: $result');
        return null;
      }

      final proofPtr = outProof.value;
      final proofLen = outProofLen.value;

      if (proofPtr == nullptr || proofLen == 0) {
        return null;
      }

      final jsonBytes = proofPtr.asTypedList(proofLen);
      final jsonStr = utf8.decode(jsonBytes);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      _free?.call(proofPtr, proofLen);

      return BulletproofsRangeProof.fromJson(json);
    } finally {
      calloc.free(outProof);
      calloc.free(outProofLen);
    }
  }

  bool verifyRangeProofNative(BulletproofsRangeProof proof) {
    if (!_isInitialized || _verifyRangeProof == null) {
      return false;
    }

    final jsonStr = jsonEncode(proof.toJson());
    final jsonBytes = utf8.encode(jsonStr);
    final jsonPtr = calloc<Uint8>(jsonBytes.length);

    try {
      for (var i = 0; i < jsonBytes.length; i++) {
        jsonPtr[i] = jsonBytes[i];
      }

      final result = _verifyRangeProof!(jsonPtr, jsonBytes.length);
      return result == 1;
    } finally {
      calloc.free(jsonPtr);
    }
  }
}

class BulletproofsService {
  final String baseUrl;
  final String jwtToken;
  final BulletproofsFFI _ffi = BulletproofsFFI.instance;

  BulletproofsService({
    required this.baseUrl,
    required this.jwtToken,
  });

  Future<void> initialize() async {
    await _ffi.initialize();
    debugPrint(
        '[BulletproofsService] Initialized (FFI: ${_ffi.isInitialized})');
  }

  Future<BulletproofsRangeProof?> createRangeProof(int value) async {
    if (_ffi.isInitialized) {
      final proof = _ffi.createRangeProofNative(value);
      if (proof != null) {
        debugPrint('[BulletproofsService] Range proof created via FFI');
        return proof;
      }
    }

    return _createRangeProofHttp(value);
  }

  Future<bool> verifyRangeProof(BulletproofsRangeProof proof) async {
    if (_ffi.isInitialized) {
      final result = _ffi.verifyRangeProofNative(proof);
      debugPrint('[BulletproofsService] Range proof verified via FFI: $result');
      return result;
    }

    return _verifyRangeProofHttp(proof);
  }

  Future<VideoStreamProof?> createVideoStreamProof({
    required String sessionId,
    required int segmentIndex,
    required Uint8List content,
  }) async {
    try {
      debugPrint(
          '[BulletproofsService] Creating video stream proof for segment $segmentIndex');

      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/zkp/video/proof'),
        headers: {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'session_id': sessionId,
          'segment_index': segmentIndex,
          'content_hash': base64Encode(content),
        }),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final proof = VideoStreamProof.fromJson(json);
        debugPrint('[BulletproofsService] Video stream proof created: $proof');
        return proof;
      } else {
        debugPrint(
            '[BulletproofsService] createVideoStreamProof failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[BulletproofsService] createVideoStreamProof error: $e');
    }
    return null;
  }

  Future<bool> verifyVideoStreamProof(VideoStreamProof proof) async {
    try {
      debugPrint(
          '[BulletproofsService] Verifying video stream proof for segment ${proof.segmentIndex}');

      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/zkp/video/verify'),
        headers: {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(proof.toJson()),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final valid = json['valid'] == true;
        debugPrint('[BulletproofsService] Video stream proof valid: $valid');
        return valid;
      } else {
        debugPrint(
            '[BulletproofsService] verifyVideoStreamProof failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[BulletproofsService] verifyVideoStreamProof error: $e');
    }
    return false;
  }

  Future<BulletproofsRangeProof?> _createRangeProofHttp(int value) async {
    try {
      debugPrint(
          '[BulletproofsService] Creating range proof via HTTP for value: $value');

      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/zkp/range-proof/create'),
        headers: {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'value': value}),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['success'] == true && json['proof'] != null) {
          final proof = BulletproofsRangeProof.fromJson(json['proof']);
          debugPrint('[BulletproofsService] Range proof created via HTTP');
          return proof;
        }
      } else {
        debugPrint(
            '[BulletproofsService] _createRangeProofHttp failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[BulletproofsService] _createRangeProofHttp error: $e');
    }
    return null;
  }

  Future<bool> _verifyRangeProofHttp(BulletproofsRangeProof proof) async {
    try {
      debugPrint('[BulletproofsService] Verifying range proof via HTTP');

      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/zkp/range-proof/verify'),
        headers: {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(proof.toJson()),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final valid = json['valid'] == true;
        debugPrint('[BulletproofsService] Range proof valid via HTTP: $valid');
        return valid;
      } else {
        debugPrint(
            '[BulletproofsService] _verifyRangeProofHttp failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[BulletproofsService] _verifyRangeProofHttp error: $e');
    }
    return false;
  }
}
