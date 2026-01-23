// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:edwards25519/edwards25519.dart' as ed25519;
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:thirds/blake3.dart' as blake3;

/// SAE (Simultaneous Authentication of Equals) 客户端
///
/// 完整的 WPA3-SAE 实现，基于 Edwards25519 曲线
/// 与 Rust 端 `rockzero-sae` crate 完全对齐
///
/// 使用的加密算法：
/// - 椭圆曲线：Edwards25519（与 curve25519_dalek 兼容）
/// - PWE 派生：Blake3（Hunt-and-Peck 方法）
/// - HMAC：SHA3-256
/// - HKDF：SHA3-256
class SaeClientCurve25519 {
  /// 椭圆曲线组 ID（19 = Curve25519）
  static const int GROUP_ID = 19;

  /// PWE 最大迭代次数
  static const int SAE_MAX_PWE_LOOP = 40;

  /// PWE 内部偏移量迭代次数
  static const int SAE_PWE_OFFSET_ITERATIONS = 8;

  final Uint8List password;
  final Uint8List _deviceIdSelf32;
  final Uint8List _deviceIdPeer32;

  // 保留原始设备ID用于调试
  final Uint8List deviceIdSelf;
  final Uint8List deviceIdPeer;

  // 密码元素（PWE）
  ed25519.Point? _pwe;

  // 本地 commit 数据
  ed25519.Scalar? _rand;
  ed25519.Scalar? _mask;
  ed25519.Scalar? _scalar;
  ed25519.Point? _element;

  // 对方 commit 数据
  ed25519.Scalar? _peerScalar;
  ed25519.Point? _peerElement;

  // 派生的密钥
  Uint8List? _kck; // Key Confirmation Key (32 bytes)
  Uint8List? _pmk; // Pairwise Master Key (32 bytes)
  Uint8List? _pmkid; // PMK ID (16 bytes)

  // 状态
  bool _committed = false;
  bool _confirmed = false;

  // Confirm 计数器
  int _sendConfirm = 1;

  /// 将任意长度的设备ID规范化为32字节
  ///
  /// 与 Rust 端保持一致：使用 Blake3 哈希
  /// - 如果输入已经是32字节，直接使用
  /// - 否则使用 Blake3 哈希
  static Uint8List _normalizeDeviceId(Uint8List input) {
    if (input.length == 32) {
      return Uint8List.fromList(input);
    }
    // 使用 Blake3 哈希（与 Rust 端 blake3::hash() 一致）
    final hash = blake3.blake3(input, 32);
    return Uint8List.fromList(hash);
  }

  /// 创建 SAE 客户端
  ///
  /// 参数：
  /// - password: 共享密码
  /// - deviceIdSelf: 本地设备ID（任意长度，会被规范化到32字节）
  /// - deviceIdPeer: 对方设备ID（任意长度，会被规范化到32字节）
  SaeClientCurve25519({
    required this.password,
    required this.deviceIdSelf,
    required this.deviceIdPeer,
  })  : _deviceIdSelf32 = _normalizeDeviceId(deviceIdSelf),
        _deviceIdPeer32 = _normalizeDeviceId(deviceIdPeer);

  /// 便捷构造函数：从字符串创建
  ///
  /// 设备ID会被 UTF-8 编码后哈希为32字节
  factory SaeClientCurve25519.fromStrings({
    required String password,
    required String deviceIdSelf,
    required String deviceIdPeer,
  }) {
    return SaeClientCurve25519(
      password: Uint8List.fromList(utf8.encode(password)),
      deviceIdSelf: Uint8List.fromList(utf8.encode(deviceIdSelf)),
      deviceIdPeer: Uint8List.fromList(utf8.encode(deviceIdPeer)),
    );
  }

  /// 生成 Commit 消息（Base64 编码）
  ///
  /// 返回格式：
  /// ```json
  /// {
  ///   "group_id": 19,
  ///   "scalar": "<base64>",
  ///   "element": "<base64>"
  /// }
  /// ```
  Map<String, dynamic> generateCommit() {
    if (_committed) {
      throw StateError('Already committed');
    }

    // 1. 派生密码元素（PWE）
    _pwe ??= _derivePasswordElement();

    // 2. 生成随机数和掩码
    _rand = _generateRandomScalar();
    _mask = _generateRandomScalar();

    // 3. 计算 commit scalar: scalar = (rand + mask) mod q
    _scalar = ed25519.Scalar()..add(_rand!, _mask!);

    // 4. 计算 commit element: element = -mask * PWE
    // 根据 SAE 标准，element = inverse(mask * PWE) = -mask * PWE
    final maskNeg = ed25519.Scalar()..negate(_mask!);
    _element = ed25519.Point.zero()..scalarMult(maskNeg, _pwe!);

    _committed = true;

    return {
      'group_id': GROUP_ID,
      'scalar': base64Encode(_scalarToBytes(_scalar!)),
      'element': base64Encode(_pointToBytes(_element!)),
    };
  }

  /// 处理对方的 Commit 消息（Base64 解码）
  ///
  /// 此方法会：
  /// 1. 解析对方的 scalar 和 element
  /// 2. 计算共享密钥
  /// 3. 派生 KCK 和 PMK
  void processCommit(Map<String, dynamic> peerCommit) {
    if (!_committed) {
      throw StateError('Must generate own commit first');
    }

    // 1. 验证 group ID
    final groupId = peerCommit['group_id'] as int;
    if (groupId != GROUP_ID) {
      throw ArgumentError(
          'Unsupported group ID: $groupId (expected $GROUP_ID)');
    }

    // 2. 解析对方的 scalar
    final peerScalarBytes = base64Decode(peerCommit['scalar'] as String);
    _peerScalar = _bytesToScalar(peerScalarBytes);

    // 3. 解析对方的 element（兼容 32 字节和 33 字节格式）
    final peerElementBytes = base64Decode(peerCommit['element'] as String);
    _peerElement = _bytesToPoint(peerElementBytes);

    // 4. 验证对方的值不等于自己的
    if (_peerScalar!.equal(_scalar!) == 1) {
      throw StateError('Peer scalar equals own scalar');
    }

    if (_peerElement!.equal(_element!) == 1) {
      throw StateError('Peer element equals own element');
    }

    // 5. 计算共享密钥
    // K = local_rand * (peer_element + peer_scalar * PWE)
    final sharedSecret = _computeSharedSecret();

    // 6. 派生 KCK 和 PMK
    _deriveKeys(sharedSecret);

    // 7. 计算 PMKID
    _pmkid = _computePmkid();
  }

  /// 生成 Confirm 消息（Base64 编码）
  ///
  /// 返回格式：
  /// ```json
  /// {
  ///   "send_confirm": 1,
  ///   "confirm": "<base64>"
  /// }
  /// ```
  Map<String, dynamic> generateConfirm() {
    if (!_committed || _kck == null) {
      throw StateError('Must process peer commit first');
    }

    final confirm = _computeConfirm(_sendConfirm);

    return {
      'send_confirm': _sendConfirm,
      'confirm': base64Encode(confirm),
    };
  }

  /// 验证对方的 Confirm 消息（Base64 解码）
  void verifyConfirm(Map<String, dynamic> peerConfirm) {
    if (_kck == null) {
      throw StateError('Must process peer commit first');
    }

    final sendConfirm = peerConfirm['send_confirm'] as int;
    final peerConfirmBytes = base64Decode(peerConfirm['confirm'] as String);

    final expectedConfirm = _computePeerConfirm(sendConfirm);

    if (!_constantTimeCompare(peerConfirmBytes, expectedConfirm)) {
      throw StateError('Confirm verification failed');
    }

    _confirmed = true;
  }

  /// 获取 PMK（Pairwise Master Key）
  Uint8List getPmk() {
    if (_pmk == null) {
      throw StateError('PMK not derived yet');
    }
    return Uint8List.fromList(_pmk!);
  }

  /// 获取 KCK（Key Confirmation Key）
  Uint8List getKck() {
    if (_kck == null) {
      throw StateError('KCK not derived yet');
    }
    return Uint8List.fromList(_kck!);
  }

  /// 获取 PMKID
  Uint8List getPmkid() {
    if (_pmkid == null) {
      throw StateError('PMKID not derived yet');
    }
    return Uint8List.fromList(_pmkid!);
  }

  /// 检查是否已完成认证
  bool isAuthenticated() => _confirmed;

  /// 检查是否已提交
  bool isCommitted() => _committed;

  // ============ 私有方法 ============

  /// 派生密码元素（PWE）- Hunt-and-Peck 方法
  ///
  /// 与 Rust 端 `password_to_element` 函数对齐
  /// 使用 Blake3 进行哈希
  ed25519.Point _derivePasswordElement() {
    // 使用规范化的32字节设备ID
    // 确保设备ID顺序正确（字典序）
    final List<int> id1;
    final List<int> id2;
    if (_compareBytes(_deviceIdSelf32, _deviceIdPeer32) < 0) {
      id1 = _deviceIdSelf32;
      id2 = _deviceIdPeer32;
    } else {
      id1 = _deviceIdPeer32;
      id2 = _deviceIdSelf32;
    }

    // Hunt-and-Peck 算法
    for (int counter = 1; counter <= SAE_MAX_PWE_LOOP; counter++) {
      final initialHash = _blake3Hash([
        ...id1,
        ...id2,
        ...password,
        ...Uint8List(4)
          ..buffer.asByteData().setInt32(0, counter, Endian.little),
      ]);

      // 尝试多个偏移量以增加找到有效点的概率
      for (int offset = 0; offset < SAE_PWE_OFFSET_ITERATIONS; offset++) {
        Uint8List seed;
        if (offset == 0) {
          seed = initialHash;
        } else {
          // 使用 Blake3 派生更多随机数据
          seed = _blake3Hash([
            ...initialHash,
            ...Uint8List(4)
              ..buffer.asByteData().setInt32(0, offset, Endian.little),
          ]);
        }

        // 尝试将种子转换为有效的曲线点
        final point = _trySeedToPoint(seed);
        if (point != null && _isValidPwe(point)) {
          return point;
        }
      }
    }

    throw StateError('Failed to derive PWE after maximum iterations');
  }

  /// Blake3 哈希（32字节输出）
  ///
  /// 与 Rust 端 `blake3::Hasher` 完全兼容
  Uint8List _blake3Hash(List<int> input) {
    final result = blake3.blake3(input, 32);
    return Uint8List.fromList(result);
  }

  /// 尝试将种子转换为曲线点
  ///
  /// 与 Rust 端 `try_seed_to_point` 函数完全对齐：
  /// 直接将哈希值作为 y 坐标压缩点进行解压缩
  /// 注意：不进行余因子乘法，这与 Rust 端行为一致
  ed25519.Point? _trySeedToPoint(Uint8List seed) {
    if (seed.length < 32) return null;

    try {
      // 使用种子作为 y 坐标压缩点（与 Rust CompressedEdwardsY 一致）
      final yBytes = Uint8List.fromList(seed.sublist(0, 32));
      final point = ed25519.Point.zero();
      point.setBytes(yBytes);

      // 直接返回解压缩的点，不进行余因子乘法
      // Rust 端的 try_seed_to_point 也是直接返回 decompress() 的结果
      return point;
    } catch (_) {
      return null;
    }
  }

  /// 验证 PWE 是否有效
  ///
  /// 与 Rust 端 `is_valid_pwe` 函数完全对齐：
  /// 1. 检查点不是单位元
  /// 2. 检查点是 torsion-free（无小阶分量）
  bool _isValidPwe(ed25519.Point point) {
    // 检查点不是单位元
    if (point.equal(ed25519.Point.identity) == 1) {
      return false;
    }

    // 验证点在曲线上
    if (!ed25519.checkOnCurve([point])) {
      return false;
    }

    // 检查点是否 torsion-free
    // 与 Rust 端 is_torsion_free() 等效：
    // 乘以余因子后如果得到单位元，说明原始点有小阶分量
    // 但我们需要的是：乘以余因子后不是单位元的点
    final cofactorResult = ed25519.Point.zero();
    cofactorResult.multByCofactor(point);

    // 如果乘以余因子后变成单位元，说明原始点有小阶分量，不是 torsion-free
    if (cofactorResult.equal(ed25519.Point.identity) == 1) {
      return false;
    }

    return true;
  }

  /// 生成随机标量
  ed25519.Scalar _generateRandomScalar() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    final scalar = ed25519.Scalar();
    scalar.setUniformBytes(Uint8List.fromList([...bytes, ...bytes])); // 64 字节输入
    return scalar;
  }

  /// 计算共享密钥
  ///
  /// K = local_rand * (peer_element + peer_scalar * PWE)
  Uint8List _computeSharedSecret() {
    // 1. 计算 peer_scalar * PWE
    final peerScalarPwe = ed25519.Point.zero();
    peerScalarPwe.scalarMult(_peerScalar!, _pwe!);

    // 2. 计算 peer_element + peer_scalar * PWE
    final temp = ed25519.Point.zero();
    temp.add(_peerElement!, peerScalarPwe);

    // 3. 计算 K = local_rand * temp
    final sharedSecret = ed25519.Point.zero();
    sharedSecret.scalarMult(_rand!, temp);

    // 4. 将共享密钥点转换为字节
    return Uint8List.fromList(sharedSecret.Bytes());
  }

  /// 派生 KCK 和 PMK
  ///
  /// 与 Rust 端 `derive_kck_pmk` 函数对齐
  /// 使用 SHA3-256 进行 HMAC 和 HKDF
  void _deriveKeys(Uint8List sharedSecret) {
    // 1. 计算 keyseed = HMAC-SHA3-256(zero_key, shared_secret)
    final zeroKey = Uint8List(32);
    final keyseed = _hmacSha3_256(zeroKey, sharedSecret);

    // 2. 计算 value = (local_scalar + peer_scalar) mod q
    // 注意：Scalar 的加法自动 mod q
    final value = ed25519.Scalar()..add(_scalar!, _peerScalar!);
    final valueBytes = _scalarToBytes(value);

    // 3. 使用 HKDF-SHA3-256 派生 KCK 和 PMK
    // KCK || PMK = HKDF(keyseed, "SAE KCK and PMK", value)
    final info =
        Uint8List.fromList([...utf8.encode('SAE KCK and PMK'), ...valueBytes]);
    final kckPmk = _hkdfSha3_256(keyseed, info, 64);

    _kck = Uint8List.fromList(kckPmk.sublist(0, 32));
    _pmk = Uint8List.fromList(kckPmk.sublist(32, 64));
  }

  /// 计算本地 Confirm
  ///
  /// confirm = HMAC-SHA3-256(KCK, send_confirm || my_scalar || peer_scalar || my_element || peer_element)
  Uint8List _computeConfirm(int sendConfirm) {
    final data = Uint8List.fromList([
      sendConfirm & 0xFF,
      (sendConfirm >> 8) & 0xFF,
      ..._scalarToBytes(_scalar!),
      ..._scalarToBytes(_peerScalar!),
      ..._pointToBytes(_element!),
      ..._pointToBytes(_peerElement!),
    ]);

    return _hmacSha3_256(_kck!, data);
  }

  /// 计算对方 Confirm（用于验证）
  ///
  /// 对方生成 confirm 时使用的顺序是：
  /// (peer_scalar, my_scalar, peer_element, my_element)
  /// 所以我们验证时也要用相同的顺序
  Uint8List _computePeerConfirm(int sendConfirm) {
    final data = Uint8List.fromList([
      sendConfirm & 0xFF,
      (sendConfirm >> 8) & 0xFF,
      ..._scalarToBytes(_peerScalar!),
      ..._scalarToBytes(_scalar!),
      ..._pointToBytes(_peerElement!),
      ..._pointToBytes(_element!),
    ]);

    return _hmacSha3_256(_kck!, data);
  }

  /// 计算 PMKID
  ///
  /// PMKID = HMAC-SHA3-256(PMK, "PMK Name" || device_id1 || device_id2)[0..16]
  /// 使用字典序排序的设备ID以确保双方计算结果一致
  Uint8List _computePmkid() {
    // 使用排序后的设备ID以确保双方一致
    final List<int> id1;
    final List<int> id2;
    if (_compareBytes(_deviceIdSelf32, _deviceIdPeer32) < 0) {
      id1 = _deviceIdSelf32;
      id2 = _deviceIdPeer32;
    } else {
      id1 = _deviceIdPeer32;
      id2 = _deviceIdSelf32;
    }

    final data = Uint8List.fromList([
      ...utf8.encode('PMK Name'),
      ...id1,
      ...id2,
    ]);

    final fullHash = _hmacSha3_256(_pmk!, data);
    return Uint8List.fromList(fullHash.sublist(0, 16));
  }

  /// HMAC-SHA3-256
  Uint8List _hmacSha3_256(Uint8List key, Uint8List message) {
    final hmac = hashlib.HMAC(hashlib.sha3_256).by(key);
    final digest = hmac.convert(message);
    return Uint8List.fromList(digest.bytes);
  }

  /// HKDF-SHA3-256
  ///
  /// 完整的 HKDF 实现，与 Rust 端 `Hkdf::new(None, ...)` 对齐
  /// 包含 Extract 和 Expand 两个阶段
  Uint8List _hkdfSha3_256(Uint8List ikm, Uint8List info, int length) {
    // HKDF-Extract: PRK = HMAC-Hash(salt, IKM)
    // 当 salt = None 时，使用全零 salt（与 Rust hkdf crate 行为一致）
    final salt = Uint8List(32); // 32 字节全零（SHA3-256 的块大小）
    final prk = _hmacSha3_256(salt, ikm);

    // HKDF-Expand: OKM = T(1) || T(2) || ... || T(N)
    // T(0) = empty
    // T(i) = HMAC-SHA3-256(PRK, T(i-1) || info || i)
    final output = <int>[];
    var t = Uint8List(0);
    var counter = 1;

    while (output.length < length) {
      final hmacInput = Uint8List.fromList([...t, ...info, counter]);
      t = _hmacSha3_256(prk, hmacInput);
      output.addAll(t);
      counter++;
    }

    return Uint8List.fromList(output.sublist(0, length));
  }

  /// Scalar 转字节（小端序，32字节）
  Uint8List _scalarToBytes(ed25519.Scalar scalar) {
    return scalar.Bytes();
  }

  /// 字节转 Scalar
  ed25519.Scalar _bytesToScalar(Uint8List bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('Scalar must be 32 bytes, got ${bytes.length}');
    }
    final scalar = ed25519.Scalar();
    scalar.setCanonicalBytes(bytes);
    return scalar;
  }

  /// Point 转字节（压缩 Edwards Y 坐标，32字节）
  Uint8List _pointToBytes(ed25519.Point point) {
    return Uint8List.fromList(point.Bytes());
  }

  /// 字节转 Point
  ///
  /// 支持：
  /// - 32 字节：Edwards Y 坐标压缩格式
  /// - 33 字节：带前缀的压缩格式（提取后32字节）
  ed25519.Point _bytesToPoint(Uint8List bytes) {
    Uint8List elementBytes;

    if (bytes.length == 32) {
      // 32 字节：直接作为 Edwards Y 坐标使用
      elementBytes = bytes;
    } else if (bytes.length == 33) {
      // 33 字节：带前缀的压缩格式
      // 跳过第一个字节（前缀）
      elementBytes = Uint8List.fromList(bytes.sublist(1, 33));
    } else {
      throw ArgumentError(
          'Invalid element length: ${bytes.length} (expected 32 or 33)');
    }

    final point = ed25519.Point.zero();
    point.setBytes(elementBytes);
    return point;
  }

  /// 常量时间比较
  bool _constantTimeCompare(Uint8List a, Uint8List b) {
    return ed25519.constantTimeCompare(a, b) == 1;
  }

  /// 字节数组比较（用于排序）
  int _compareBytes(List<int> a, List<int> b) {
    final minLen = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < minLen; i++) {
      if (a[i] < b[i]) return -1;
      if (a[i] > b[i]) return 1;
    }
    return a.length.compareTo(b.length);
  }
}

/// SAE Commit 数据结构
class SaeCommitData {
  final int groupId;
  final Uint8List scalar;
  final Uint8List element;

  SaeCommitData({
    required this.groupId,
    required this.scalar,
    required this.element,
  });

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'scalar': base64Encode(scalar),
        'element': base64Encode(element),
      };

  factory SaeCommitData.fromJson(Map<String, dynamic> json) {
    return SaeCommitData(
      groupId: json['group_id'] as int,
      scalar: base64Decode(json['scalar'] as String),
      element: base64Decode(json['element'] as String),
    );
  }
}

/// SAE Confirm 数据结构
class SaeConfirmData {
  final int sendConfirm;
  final Uint8List confirm;

  SaeConfirmData({
    required this.sendConfirm,
    required this.confirm,
  });

  Map<String, dynamic> toJson() => {
        'send_confirm': sendConfirm,
        'confirm': base64Encode(confirm),
      };

  factory SaeConfirmData.fromJson(Map<String, dynamic> json) {
    return SaeConfirmData(
      sendConfirm: json['send_confirm'] as int,
      confirm: base64Decode(json['confirm'] as String),
    );
  }
}
