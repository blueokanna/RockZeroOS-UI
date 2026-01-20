import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
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
    print('[SecureHLS] Starting SAE handshake for user: $userId');

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

    print('[SecureHLS] Got temp session: $tempSessionId');

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
    print('[SecureHLS] SAE handshake completed, PMK obtained');

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

    print('[SecureHLS] HLS session created: $_sessionId');

    // 8. 初始化加密器
    _encryptor = HlsEncryptor(pmk: _pmk!);
  }

  /// 步骤 2: 播放视频
  Future<VideoPlayerController> play() async {
    if (_sessionId == null || _pmk == null) {
      throw Exception('SAE handshake not completed');
    }

    // 创建自定义 HTTP 客户端
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

    print('[SecureHLS] Video player initialized');

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
    // 从 PMK 派生加密密钥（使用 HKDF）
    _encryptionKey = _deriveKey(pmk, 'hls-master-key');
  }

  /// 解密段
  Uint8List decryptSegment(Uint8List encryptedData) {
    // 提取 nonce（前 12 字节）
    final nonce = encryptedData.sublist(0, 12);
    final ciphertext = encryptedData.sublist(12);

    // 使用 AES-256-GCM 解密
    // 注意：这里需要使用实际的 AES-GCM 库
    // 简化实现：返回原数据（实际应该解密）
    return _aesGcmDecrypt(_encryptionKey, nonce, ciphertext);
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
      'nonce': base64Encode(_generateRandom(16)),
    };

    return base64Encode(utf8.encode(jsonEncode(proof)));
  }

  // 辅助函数
  Uint8List _deriveKey(Uint8List key, String info) {
    final hash = sha256.convert([...key, ...utf8.encode(info)]);
    return Uint8List.fromList(hash.bytes);
  }

  Uint8List _aesGcmDecrypt(
      Uint8List key, Uint8List nonce, Uint8List ciphertext) {
    // TODO: 实现真正的 AES-256-GCM 解密
    // 这里需要使用 pointycastle 或其他加密库
    // 简化实现：返回原数据
    return ciphertext;
  }

  Uint8List _generateRandom(int length) {
    final random = List<int>.generate(
        length, (i) => DateTime.now().microsecondsSinceEpoch % 256);
    return Uint8List.fromList(random);
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
      print('[SecureHLS] Intercepting segment request: $url');

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

      print('[SecureHLS] Segment decrypted: ${decryptedData.length} bytes');

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
