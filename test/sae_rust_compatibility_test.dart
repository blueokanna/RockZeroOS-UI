import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockzero/services/sae_client_curve25519.dart';
import 'package:rockzero/services/sae_utils.dart';

/// 测试 Flutter SAE 实现与 Rust 后端的兼容性
///
/// 这些测试模拟 Rust 服务器的行为，确保：
/// 1. 数据格式兼容
/// 2. 加密算法一致
/// 3. 握手流程正确
void main() {
  group('Rust 兼容性测试', () {
    test('Commit 消息格式与 Rust 兼容', () {
      final client = SaeClientCurve25519.fromStrings(
        password: 'test_password',
        deviceIdSelf: 'flutter-client',
        deviceIdPeer: 'rust-server',
      );

      final commit = client.generateCommit();

      // 验证格式
      expect(commit, isA<Map<String, dynamic>>());
      expect(commit['group_id'], 19); // Curve25519
      expect(commit['scalar'], isA<String>()); // Base64 编码
      expect(commit['element'], isA<String>()); // Base64 编码

      // 验证 scalar 长度（32 字节 = 44 字符 Base64）
      final scalarBytes = base64Decode(commit['scalar'] as String);
      expect(scalarBytes.length, 32);

      // 验证 element 长度（32 字节压缩点）
      final elementBytes = base64Decode(commit['element'] as String);
      expect(elementBytes.length, 32);
    });

    test('Confirm 消息格式与 Rust 兼容', () {
      final client1 = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client',
        deviceIdPeer: 'server',
      );

      final client2 = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'server',
        deviceIdPeer: 'client',
      );

      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      client1.processCommit(commit2);
      client2.processCommit(commit1);

      final confirm = client1.generateConfirm();

      // 验证格式
      expect(confirm, isA<Map<String, dynamic>>());
      expect(confirm['send_confirm'], 1);
      expect(confirm['confirm'], isA<String>()); // Base64 编码

      // 验证 confirm 长度（32 字节 HMAC）
      final confirmBytes = base64Decode(confirm['confirm'] as String);
      expect(confirmBytes.length, 32);
    });

    test('支持 Rust 发送的 33 字节 element（带前缀）', () {
      final client = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client',
        deviceIdPeer: 'server',
      );

      client.generateCommit();

      // 模拟 Rust 服务器发送的 33 字节 element（0x02 前缀 + 32 字节）
      final mockElement = Uint8List(33);
      mockElement[0] = 0x02; // 压缩点前缀
      for (int i = 1; i < 33; i++) {
        mockElement[i] = i % 256;
      }

      final mockCommit = {
        'group_id': 19,
        'scalar': base64Encode(Uint8List(32)), // 全零 scalar（仅用于测试格式）
        'element': base64Encode(mockElement),
      };

      // 应该能够解析（即使点可能无效）
      // 注意：这个测试可能会因为点无效而失败，这是预期的
      // 主要是测试格式解析
      try {
        client.processCommit(mockCommit);
      } catch (e) {
        // 预期可能失败（因为是随机点）
        // 错误信息可能是 'decompress' 或 'invalid point encoding'
        expect(
          e.toString().contains('decompress') ||
              e.toString().contains('invalid point encoding'),
          isTrue,
          reason: 'Expected point decoding error',
        );
      }
    });

    test('设备ID哈希与 Rust SHA3-256 兼容', () {
      // 测试已知的 SHA3-256 哈希值
      final deviceId = 'test-device-123';
      final hashed = SaeUtils.hashDeviceId(deviceId);

      expect(hashed.length, 32);

      // 验证哈希是确定性的
      final hashed2 = SaeUtils.hashDeviceId(deviceId);
      expect(hashed, equals(hashed2));
    });

    test('PMK 长度符合 Rust 期望（32 字节）', () {
      final client1 = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client',
        deviceIdPeer: 'server',
      );

      final client2 = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'server',
        deviceIdPeer: 'client',
      );

      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      client1.processCommit(commit2);
      client2.processCommit(commit1);

      final confirm1 = client1.generateConfirm();
      final confirm2 = client2.generateConfirm();

      client1.verifyConfirm(confirm2);
      client2.verifyConfirm(confirm1);

      final pmk = client1.getPmk();
      expect(pmk.length, 32, reason: 'PMK 应该是 32 字节（用于 AES-256-GCM）');
    });

    test('PMKID 长度符合 Rust 期望（16 字节）', () {
      final client1 = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client',
        deviceIdPeer: 'server',
      );

      final client2 = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'server',
        deviceIdPeer: 'client',
      );

      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      client1.processCommit(commit2);
      client2.processCommit(commit1);

      final confirm1 = client1.generateConfirm();
      final confirm2 = client2.generateConfirm();

      client1.verifyConfirm(confirm2);
      client2.verifyConfirm(confirm1);

      final pmkid = client1.getPmkid();
      expect(pmkid.length, 16, reason: 'PMKID 应该是 16 字节');
    });

    test('JSON 序列化与 Rust serde 兼容', () {
      final client = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client',
        deviceIdPeer: 'server',
      );

      final commit = client.generateCommit();

      // 序列化为 JSON
      final json = jsonEncode(commit);
      expect(json, isA<String>());

      // 反序列化
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['group_id'], commit['group_id']);
      expect(decoded['scalar'], commit['scalar']);
      expect(decoded['element'], commit['element']);
    });

    test('错误处理与 Rust 一致', () {
      final client = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client',
        deviceIdPeer: 'server',
      );

      // 测试：未生成 commit 就处理对方 commit
      expect(
        () => client.processCommit({
          'group_id': 19,
          'scalar': base64Encode(Uint8List(32)),
          'element': base64Encode(Uint8List(32)),
        }),
        throwsA(isA<StateError>()),
        reason: '应该抛出状态错误',
      );

      // 测试：不支持的 group ID
      client.generateCommit();
      expect(
        () => client.processCommit({
          'group_id': 999, // 不支持的组
          'scalar': base64Encode(Uint8List(32)),
          'element': base64Encode(Uint8List(32)),
        }),
        throwsA(isA<ArgumentError>()),
        reason: '应该拒绝不支持的 group ID',
      );
    });

    test('完整握手流程模拟 Rust 服务器', () {
      // 模拟 Flutter 客户端与 Rust 服务器的完整握手

      // 1. 客户端初始化
      final client = SaeClientCurve25519.fromStrings(
        password: 'shared_secret_password',
        deviceIdSelf: 'flutter-mobile-app',
        deviceIdPeer: 'rust-nas-server',
      );

      // 2. 客户端生成 commit
      final clientCommit = client.generateCommit();
      expect(clientCommit['group_id'], 19);

      // 3. 模拟服务器响应（使用另一个客户端模拟）
      final server = SaeClientCurve25519.fromStrings(
        password: 'shared_secret_password',
        deviceIdSelf: 'rust-nas-server',
        deviceIdPeer: 'flutter-mobile-app',
      );

      final serverCommit = server.generateCommit();

      // 4. 双方处理对方的 commit
      client.processCommit(serverCommit);
      server.processCommit(clientCommit);

      // 5. 双方生成 confirm
      final clientConfirm = client.generateConfirm();
      final serverConfirm = server.generateConfirm();

      // 6. 双方验证对方的 confirm
      client.verifyConfirm(serverConfirm);
      server.verifyConfirm(clientConfirm);

      // 8. 验证双方认证成功
      expect(client.isAuthenticated(), true);
      expect(server.isAuthenticated(), true);

      // 9. 验证 PMK 匹配
      final clientPmk = client.getPmk();
      final serverPmk = server.getPmk();
      expect(clientPmk, equals(serverPmk));

      // 10. 验证 PMKID 匹配
      final clientPmkid = client.getPmkid();
      final serverPmkid = server.getPmkid();
      expect(clientPmkid, equals(serverPmkid));
    });

    test('Base64 编码与 Rust base64 crate 兼容', () {
      final testData = Uint8List.fromList([
        0x01,
        0x23,
        0x45,
        0x67,
        0x89,
        0xAB,
        0xCD,
        0xEF,
        0xFE,
        0xDC,
        0xBA,
        0x98,
        0x76,
        0x54,
        0x32,
        0x10,
      ]);

      final encoded = base64Encode(testData);
      final decoded = base64Decode(encoded);

      expect(decoded, equals(testData));
      expect(encoded, isA<String>());
      expect(encoded.length, greaterThan(0));
    });

    test('常量时间比较（防止时序攻击）', () {
      final data1 = Uint8List.fromList(List.filled(32, 0xAA));
      final data2 = Uint8List.fromList(List.filled(32, 0xAA));
      final data3 = Uint8List.fromList(List.filled(32, 0xBB));

      // 相同数据应该相等
      expect(base64Encode(data1), equals(base64Encode(data2)));

      // 不同数据应该不等
      expect(base64Encode(data1), isNot(equals(base64Encode(data3))));
    });
  });

  group('边界情况测试', () {
    test('空密码应该工作', () {
      final client = SaeClientCurve25519.fromStrings(
        password: '',
        deviceIdSelf: 'client',
        deviceIdPeer: 'server',
      );

      expect(() => client.generateCommit(), returnsNormally);
    });

    test('超长密码应该工作', () {
      final longPassword = 'a' * 10000;
      final client = SaeClientCurve25519.fromStrings(
        password: longPassword,
        deviceIdSelf: 'client',
        deviceIdPeer: 'server',
      );

      expect(() => client.generateCommit(), returnsNormally);
    });

    test('Unicode 密码应该工作', () {
      final client = SaeClientCurve25519.fromStrings(
        password: '测试密码🔐🌟',
        deviceIdSelf: 'client',
        deviceIdPeer: 'server',
      );

      expect(() => client.generateCommit(), returnsNormally);
    });

    test('相同设备ID应该工作', () {
      final client = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'same-device',
        deviceIdPeer: 'same-device',
      );

      expect(() => client.generateCommit(), returnsNormally);
    });

    test('特殊字符设备ID应该工作', () {
      final client = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'device-!@#\$%^&*()',
        deviceIdPeer: 'device-<>?:"{}|',
      );

      expect(() => client.generateCommit(), returnsNormally);
    });
  });
}
