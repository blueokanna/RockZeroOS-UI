import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:edwards25519/edwards25519.dart' as ed25519;
import 'package:thirds/blake3.dart' as blake3;

/// 测试 PWE 派生本身的确定性
///
/// 这个测试直接测试 PWE 派生函数，不涉及随机数
void main() {
  group('PWE 派生确定性测试', () {
    test('PWE 派生是确定性的（直接测试）', () {
      const password = 'test_password_123';
      final passwordBytes = Uint8List.fromList(utf8.encode(password));

      final deviceId1 = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        deviceId1[i] = i + 1;
      }

      final deviceId2 = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        deviceId2[i] = i + 33;
      }

      // 派生 PWE 10 次
      final pwes = <Uint8List>[];
      for (int i = 0; i < 10; i++) {
        final pwe = _derivePasswordElement(passwordBytes, deviceId1, deviceId2);
        pwes.add(Uint8List.fromList(pwe.Bytes()));
      }

      // 验证所有 PWE 都相同
      for (int i = 1; i < pwes.length; i++) {
        expect(pwes[i], equals(pwes[0]),
            reason: '第 ${i + 1} 次派生的 PWE 应该与第 1 次相同');
      }

      // ignore: avoid_print
      print('✅ PWE 派生是确定性的！10 次派生的 PWE 完全相同');
      // ignore: avoid_print
      print('PWE: ${base64Encode(pwes[0])}');
    });

    test('不同密码派生不同的 PWE', () {
      final deviceId1 = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        deviceId1[i] = i + 1;
      }

      final deviceId2 = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        deviceId2[i] = i + 33;
      }

      final passwords = ['password1', 'password2', 'password3'];
      final pwes = <Uint8List>[];

      for (final password in passwords) {
        final passwordBytes = Uint8List.fromList(utf8.encode(password));
        final pwe = _derivePasswordElement(passwordBytes, deviceId1, deviceId2);
        pwes.add(Uint8List.fromList(pwe.Bytes()));
      }

      // 验证不同密码产生不同的 PWE
      expect(pwes[0], isNot(equals(pwes[1])));
      expect(pwes[0], isNot(equals(pwes[2])));
      expect(pwes[1], isNot(equals(pwes[2])));

      // ignore: avoid_print
      print('✅ 不同密码产生不同的 PWE');
    });

    test('设备ID顺序不影响 PWE（对称性）', () {
      const password = 'test_password';
      final passwordBytes = Uint8List.fromList(utf8.encode(password));

      final deviceId1 = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        deviceId1[i] = i + 1;
      }

      final deviceId2 = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        deviceId2[i] = i + 33;
      }

      // 正向
      final pwe1 = _derivePasswordElement(passwordBytes, deviceId1, deviceId2);

      // 反向
      final pwe2 = _derivePasswordElement(passwordBytes, deviceId2, deviceId1);

      // 验证 PWE 相同
      expect(Uint8List.fromList(pwe1.Bytes()),
          equals(Uint8List.fromList(pwe2.Bytes())),
          reason: '设备ID顺序不应该影响 PWE');

      // ignore: avoid_print
      print('✅ 设备ID顺序不影响 PWE（对称性验证通过）');
    });
  });
}

/// 复制 SaeClientCurve25519 的 PWE 派生逻辑
ed25519.Point _derivePasswordElement(
  Uint8List password,
  Uint8List deviceIdSelf,
  Uint8List deviceIdPeer,
) {
  // 确保设备ID顺序正确（字典序）
  final List<int> id1;
  final List<int> id2;
  if (_compareBytes(deviceIdSelf, deviceIdPeer) < 0) {
    id1 = deviceIdSelf;
    id2 = deviceIdPeer;
  } else {
    id1 = deviceIdPeer;
    id2 = deviceIdSelf;
  }

  // Hunt-and-Peck 算法
  for (int counter = 1; counter <= 40; counter++) {
    // PWE = Blake3(id1 || id2 || password || counter)
    final counterBytes = Uint8List(4);
    counterBytes.buffer.asByteData().setUint32(0, counter, Endian.little);

    final initialHash = _blake3Hash([
      ...id1,
      ...id2,
      ...password,
      ...counterBytes,
    ]);

    // 尝试多个偏移量以增加找到有效点的概率
    for (int offset = 0; offset < 8; offset++) {
      Uint8List seed;
      if (offset == 0) {
        seed = initialHash;
      } else {
        // 使用 Blake3 派生更多随机数据
        final offsetBytes = Uint8List(4);
        offsetBytes.buffer.asByteData().setUint32(0, offset, Endian.little);

        seed = _blake3Hash([
          ...initialHash,
          ...offsetBytes,
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

Uint8List _blake3Hash(List<int> input) {
  final result = blake3.blake3(input, 32);
  return Uint8List.fromList(result);
}

ed25519.Point? _trySeedToPoint(Uint8List seed) {
  if (seed.length < 32) return null;

  try {
    final yBytes = Uint8List.fromList(seed.sublist(0, 32));
    final point = ed25519.Point.zero();

    try {
      point.setBytes(yBytes);
      if (!ed25519.checkOnCurve([point])) {
        return null;
      }
      return point;
    } catch (_) {
      return null;
    }
  } catch (_) {
    return null;
  }
}

bool _isValidPwe(ed25519.Point point) {
  if (point.equal(ed25519.Point.identity) == 1) {
    return false;
  }
  return ed25519.checkOnCurve([point]);
}

int _compareBytes(List<int> a, List<int> b) {
  final minLen = a.length < b.length ? a.length : b.length;
  for (int i = 0; i < minLen; i++) {
    if (a[i] < b[i]) return -1;
    if (a[i] > b[i]) return 1;
  }
  return a.length.compareTo(b.length);
}
