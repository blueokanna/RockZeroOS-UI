import 'dart:convert';
import 'dart:typed_data';

import 'package:thirds/blake3.dart' as blake3;

/// HKDF-Blake3 密钥派生
///
/// 使用 Blake3 作为底层哈希实现 HKDF（RFC 5869）的 Extract + Expand 过程。
/// 与 Rust 端 `rockzero_media::session::HkdfBlake3` 完全兼容。
///
/// ## 使用示例
/// ```dart
/// final hkdf = HkdfBlake3.withSessionSalt(sessionId, pmk);
/// final key = hkdf.expand(utf8.encode('hls-master-key'), 32);
/// ```
class HkdfBlake3 {
  /// 提取后的伪随机密钥 (PRK)
  final Uint8List _prk;

  /// 使用 HKDF-Extract 从 IKM 和 salt 生成 PRK
  ///
  /// 与 Rust 端 `HkdfBlake3::new` 一致。
  HkdfBlake3({
    required Uint8List ikm,
    Uint8List? salt,
  }) : _prk = _extract(salt ?? Uint8List(32), ikm);

  /// 使用 session ID 作为 salt 构造
  ///
  /// 与 Rust 端 `HkdfBlake3::new_with_session_salt` 一致：
  /// ```rust
  /// let salt = blake3::hash(session_id.as_bytes());
  /// HkdfBlake3 { prk: Self::extract(salt.as_bytes(), pmk) }
  /// ```
  factory HkdfBlake3.withSessionSalt(String sessionId, Uint8List pmk) {
    final saltHash =
        Uint8List.fromList(blake3.blake3(utf8.encode(sessionId), 32));
    return HkdfBlake3(ikm: pmk, salt: saltHash);
  }

  /// HKDF-Expand：从 PRK 派生指定长度的密钥材料
  ///
  /// 与 Rust 端 `HkdfBlake3::expand` 一致。
  ///
  /// - [info]: 上下文信息字节
  /// - [length]: 输出密钥长度（字节）
  Uint8List expand(Uint8List info, int length) {
    final output = <int>[];
    var t = Uint8List(0);
    var counter = 1;

    while (output.length < length) {
      // T(i) = HMAC-Blake3(PRK, T(i-1) || info || counter)
      final hmacInput = Uint8List.fromList([...t, ...info, counter]);
      t = _blake3KeyedHash(_prk, hmacInput);
      output.addAll(t);
      counter++;
    }

    return Uint8List.fromList(output.sublist(0, length));
  }

  /// HKDF-Extract: PRK = HMAC-Blake3(salt, IKM)
  static Uint8List _extract(Uint8List salt, Uint8List ikm) {
    return _blake3KeyedHash(salt, ikm);
  }

  /// Blake3 keyed hash (HMAC 替代品)
  ///
  /// 与 Rust 端和 SaeClientCurve25519._blake3KeyedHash 一致：
  /// 将 key 规范化为 32 字节，然后 H(key || message)。
  static Uint8List _blake3KeyedHash(Uint8List key, Uint8List message) {
    Uint8List normalizedKey;
    if (key.length == 32) {
      normalizedKey = key;
    } else if (key.length < 32) {
      normalizedKey = Uint8List(32);
      normalizedKey.setRange(0, key.length, key);
    } else {
      normalizedKey = Uint8List.fromList(blake3.blake3(key, 32));
    }

    final input = Uint8List.fromList([...normalizedKey, ...message]);
    return Uint8List.fromList(blake3.blake3(input, 32));
  }
}
