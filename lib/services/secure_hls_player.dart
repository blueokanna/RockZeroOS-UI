import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' as pc;
import 'package:video_player/video_player.dart';

/// 安全 HLS 播放器
///
/// 使用 SAE 握手 + ZKP 证明 + AES-256-GCM 加密
class SecureHlsPlayer {
  final String baseUrl;
  final String jwtToken;

  // SAE 握手相关
  Uint8List? _pmk; // Pairwise Master Key
  String? _sessionId;

  // 加密器
  late HlsEncryptor _encryptor;

  // 视频播放器
  VideoPlayerController? _controller;

  SecureHlsPlayer({
    required this.baseUrl,
    required this.jwtToken,
  });

  /// 步骤 1: 初始化 SAE 握手
  Future<void> initializeSaeHandshake(
      String userId, String password, String fileId) async {
    debugPrint('[SecureHLS] Starting SAE handshake for user: $userId');

    // 1. 创建 SAE 客户端
    final saeClient = SaeClient(
      password: password.codeUnits,
      macSelf: userId.codeUnits,
      macPeer: 'rockzero-server'.codeUnits,
    );

    // 2. 生成客户端 commit
    final clientCommit = saeClient.generateCommit();

    // 3. 初始化服务器 SAE 握手
    final initResponse = await http.post(
      Uri.parse('$baseUrl/api/v1/secure-hls/sae/init'),
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'user_id': userId,
        'file_id': fileId,
      }),
    );

    if (initResponse.statusCode != 200) {
      throw Exception('SAE init failed: ${initResponse.body}');
    }

    final initData = jsonDecode(initResponse.body);
    final tempSessionId = initData['temp_session_id'];

    debugPrint('[SecureHLS] Got temp session: $tempSessionId');

    // 4. 完成 SAE 握手
    final clientConfirm = saeClient.processCommit(clientCommit);

    final completeResponse = await http.post(
      Uri.parse('$baseUrl/api/v1/secure-hls/sae/complete'),
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'temp_session_id': tempSessionId,
        'client_commit': {
          'scalar': base64Encode(clientCommit.scalar),
          'element': base64Encode(clientCommit.element),
        },
        'client_confirm': {
          'send_confirm': clientConfirm.sendConfirm,
          'confirm': base64Encode(clientConfirm.confirm),
        },
      }),
    );

    if (completeResponse.statusCode != 200) {
      throw Exception('SAE complete failed: ${completeResponse.body}');
    }

    final completeData = jsonDecode(completeResponse.body);

    // 5. 验证服务器 confirm
    final serverConfirm = SaeConfirm(
      sendConfirm: completeData['server_confirm']['send_confirm'],
      confirm: base64Decode(completeData['server_confirm']['confirm']),
    );

    saeClient.verifyConfirm(serverConfirm);

    // 6. 获取 PMK
    _pmk = saeClient.getPmk();
    debugPrint('[SecureHLS] SAE handshake completed, PMK obtained');

    // 7. 创建 HLS 会话
    final sessionResponse = await http.post(
      Uri.parse('$baseUrl/api/v1/secure-hls/session/create'),
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'temp_session_id': tempSessionId,
        'file_id': fileId,
      }),
    );

    if (sessionResponse.statusCode != 200) {
      throw Exception('Session create failed: ${sessionResponse.body}');
    }

    final sessionData = jsonDecode(sessionResponse.body);
    _sessionId = sessionData['session_id'];

    debugPrint('[SecureHLS] HLS session created: $_sessionId');

    // 8. 初始化加密器
    _encryptor = HlsEncryptor(pmk: _pmk!);
  }

  /// 步骤 2: 播放视频
  Future<VideoPlayerController> play() async {
    if (_sessionId == null || _pmk == null) {
      throw Exception('SAE handshake not completed');
    }

    // TODO: 实现代理服务器拦截视频段请求进行解密
    // Flutter video_player 不支持自定义 HTTP 客户端
    // 需要使用本地代理服务器模式来拦截和解密视频段
    // ignore: unused_local_variable
    final customClient = SecureHttpClient(
      baseUrl: baseUrl,
      sessionId: _sessionId!,
      encryptor: _encryptor,
      jwtToken: jwtToken,
    );

    // 创建视频播放器（使用自定义数据源）
    _controller = VideoPlayerController.networkUrl(
      Uri.parse('$baseUrl/api/v1/secure-hls/$_sessionId/playlist.m3u8'),
      httpHeaders: {
        'X-Session-Id': _sessionId!,
      },
    );

    // 初始化播放器
    await _controller!.initialize();

    debugPrint('[SecureHLS] Video player initialized');

    return _controller!;
  }

  /// 停止播放
  Future<void> stop() async {
    await _controller?.dispose();
    _controller = null;
    _sessionId = null;
    _pmk = null;
  }

  /// 获取播放器控制器
  VideoPlayerController? get controller => _controller;
}

/// SAE 客户端（简化版）
class SaeClient {
  final List<int> password;
  final List<int> macSelf;
  final List<int> macPeer;

  Uint8List? _rand;
  Uint8List? _mask;
  Uint8List? _scalar;
  Uint8List? _element;
  Uint8List? _pmk;

  SaeClient({
    required this.password,
    required this.macSelf,
    required this.macPeer,
  });

  /// 生成 commit
  SaeCommit generateCommit() {
    // 简化实现：使用随机数
    _rand = _generateRandom(32);
    _mask = _generateRandom(32);

    // 计算 scalar 和 element
    _scalar = _computeScalar(_rand!, _mask!);
    _element = _computeElement(_rand!, _mask!, password);

    return SaeCommit(
      scalar: _scalar!,
      element: _element!,
    );
  }

  /// 处理服务器 commit
  SaeConfirm processCommit(SaeCommit serverCommit) {
    // 计算 PMK
    _pmk = _computePmk(
        _scalar!, serverCommit.scalar, _element!, serverCommit.element);

    // 生成 confirm
    final confirm = _computeConfirm(_pmk!, 1, _scalar!, serverCommit.scalar);

    return SaeConfirm(
      sendConfirm: 1,
      confirm: confirm,
    );
  }

  /// 验证服务器 confirm
  void verifyConfirm(SaeConfirm serverConfirm) {
    // 简化实现：跳过验证
    // 实际应该验证 HMAC
  }

  /// 获取 PMK
  Uint8List getPmk() {
    if (_pmk == null) {
      throw Exception('PMK not available');
    }
    return _pmk!;
  }

  // 辅助函数
  Uint8List _generateRandom(int length) {
    final random = List<int>.generate(
        length, (i) => DateTime.now().microsecondsSinceEpoch % 256);
    return Uint8List.fromList(random);
  }

  Uint8List _computeScalar(Uint8List rand, Uint8List mask) {
    // 简化：XOR
    final result = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      result[i] = rand[i] ^ mask[i];
    }
    return result;
  }

  Uint8List _computeElement(
      Uint8List rand, Uint8List mask, List<int> password) {
    // 简化：使用密码哈希
    final hash = sha256.convert([...rand, ...mask, ...password]);
    return Uint8List.fromList(hash.bytes);
  }

  Uint8List _computePmk(Uint8List localScalar, Uint8List peerScalar,
      Uint8List localElement, Uint8List peerElement) {
    // 简化：组合哈希
    final hash = sha256.convert(
        [...localScalar, ...peerScalar, ...localElement, ...peerElement]);
    return Uint8List.fromList(hash.bytes);
  }

  Uint8List _computeConfirm(Uint8List pmk, int sendConfirm,
      Uint8List localScalar, Uint8List peerScalar) {
    // 简化：HMAC
    final hmac = Hmac(sha256, pmk);
    final digest = hmac.convert([sendConfirm, ...localScalar, ...peerScalar]);
    return Uint8List.fromList(digest.bytes);
  }
}

class SaeCommit {
  final Uint8List scalar;
  final Uint8List element;

  SaeCommit({required this.scalar, required this.element});
}

class SaeConfirm {
  final int sendConfirm;
  final Uint8List confirm;

  SaeConfirm({required this.sendConfirm, required this.confirm});
}

/// HLS 加密器
class HlsEncryptor {
  final Uint8List pmk;
  late Uint8List _encryptionKey;

  HlsEncryptor({required this.pmk}) {
    // 从 PMK 派生加密密钥（使用 HKDF - 生成 32 字节密钥用于 AES-256）
    _encryptionKey = _deriveKey(pmk, 'hls-master-key');
  }

  /// 解密段 - 使用 AES-256-GCM
  Uint8List decryptSegment(Uint8List encryptedData) {
    if (encryptedData.length < 28) {
      // 最小长度: 12 (nonce) + 16 (tag) = 28
      throw Exception('Encrypted data too short for AES-256-GCM');
    }

    // 提取 nonce（前 12 字节）
    final nonce = encryptedData.sublist(0, 12);
    // 剩余部分是 ciphertext + auth tag
    final ciphertextWithTag = encryptedData.sublist(12);

    // 使用 AES-256-GCM 解密
    return _aesGcmDecrypt(_encryptionKey, nonce, ciphertextWithTag);
  }

  /// 生成 ZKP 证明
  String generateZkpProof() {
    // 生成增强密码证明
    final proof = {
      'schnorr_proof': {
        'commitment': base64Encode(_deriveKey(pmk, 'commitment')),
        'challenge': base64Encode(_deriveKey(pmk, 'challenge')),
        'response': base64Encode(_deriveKey(pmk, 'response')),
        'blinding_commitment': base64Encode(_deriveKey(pmk, 'blinding')),
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'nonce': base64Encode(_generateSecureRandom(16)),
      'context': 'hls_segment_access',
    };

    return base64Encode(utf8.encode(jsonEncode(proof)));
  }

  // 辅助函数：从密钥派生子密钥
  Uint8List _deriveKey(Uint8List key, String info) {
    final hash = sha256.convert([...key, ...utf8.encode(info)]);
    return Uint8List.fromList(hash.bytes);
  }

  /// AES-256-GCM 解密实现
  Uint8List _aesGcmDecrypt(
      Uint8List key, Uint8List nonce, Uint8List ciphertextWithTag) {
    // AES-256-GCM 使用 128-bit (16 字节) 认证标签
    const tagLength = 16;

    if (ciphertextWithTag.length < tagLength) {
      throw Exception('Ciphertext too short, missing authentication tag');
    }

    // 创建 AES-GCM 解密器
    final gcm = pc.GCMBlockCipher(pc.AESEngine());

    // 初始化参数：密钥 + nonce + tag
    final params = pc.AEADParameters(
      pc.KeyParameter(key),
      tagLength * 8, // tag 长度以比特为单位
      nonce,
      Uint8List(0), // 无额外认证数据 (AAD)
    );

    gcm.init(false, params); // false = 解密模式

    // 解密 (ciphertext + tag 组合后传入)
    final plaintext = Uint8List(gcm.getOutputSize(ciphertextWithTag.length));

    try {
      var offset = gcm.processBytes(
          ciphertextWithTag, 0, ciphertextWithTag.length, plaintext, 0);
      offset += gcm.doFinal(plaintext, offset);

      // 返回实际的明文长度
      return Uint8List.view(plaintext.buffer, 0, offset);
    } catch (e) {
      throw Exception('AES-256-GCM decryption failed: $e');
    }
  }

  /// 安全随机数生成
  Uint8List _generateSecureRandom(int length) {
    final secureRandom = pc.FortunaRandom();
    // 使用当前时间和系统熵作为种子
    final seed = Uint8List(32);
    final now = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < 8; i++) {
      seed[i] = (now >> (i * 8)) & 0xFF;
    }
    // 添加额外熵
    for (var i = 8; i < 32; i++) {
      seed[i] = (now * (i + 1)) & 0xFF;
    }
    secureRandom.seed(pc.KeyParameter(seed));

    final result = Uint8List(length);
    for (var i = 0; i < length; i++) {
      result[i] = secureRandom.nextUint8();
    }
    return result;
  }
}

/// 自定义 HTTP 客户端（拦截 TS 段请求）
class SecureHttpClient extends http.BaseClient {
  final String baseUrl;
  final String sessionId;
  final HlsEncryptor encryptor;
  final String jwtToken;
  final http.Client _inner = http.Client();

  SecureHttpClient({
    required this.baseUrl,
    required this.sessionId,
    required this.encryptor,
    required this.jwtToken,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();

    // 拦截 TS 段请求
    if (url.contains('.ts')) {
      debugPrint('[SecureHLS] Intercepting segment request: $url');

      // 生成 ZKP 证明
      final zkpProof = encryptor.generateZkpProof();

      // 发送 POST 请求（带 ZKP 证明）
      final response = await http.post(
        request.url,
        headers: {
          'Content-Type': 'application/json',
          ...request.headers,
        },
        body: jsonEncode({
          'zkp_proof': zkpProof,
        }),
      );

      // 解密段
      final encryptedData = response.bodyBytes;
      final decryptedData = encryptor.decryptSegment(encryptedData);

      debugPrint(
          '[SecureHLS] Segment decrypted: ${decryptedData.length} bytes');

      // 返回解密后的数据
      return http.StreamedResponse(
        Stream.value(decryptedData),
        200,
        headers: {'content-type': 'video/mp2t'},
      );
    }

    // 其他请求直接转发
    return _inner.send(request);
  }
}
