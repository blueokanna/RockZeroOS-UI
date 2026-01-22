import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockzero/services/sae_client_curve25519.dart';

void main() {
  group('SaeClientCurve25519 生产级测试', () {
    test('设备ID会被规范化为32字节', () {
      // 任意长度的设备ID都应该可以正常工作
      final client = SaeClientCurve25519(
        password: Uint8List(16),
        deviceIdSelf: Uint8List(16), // 16字节会被哈希为32字节
        deviceIdPeer: Uint8List(32),
      );

      // 应该能正常生成 commit
      final commit = client.generateCommit();
      expect(commit['group_id'], 19);
    });

    test('客户端可以生成 commit', () {
      final client = SaeClientCurve25519.fromStrings(
        password: 'test_password_123',
        deviceIdSelf: 'client-device',
        deviceIdPeer: 'server-device',
      );

      final commit = client.generateCommit();

      expect(commit['group_id'], 19);
      expect(commit['scalar'], isNotNull);
      expect(commit['element'], isNotNull);
      expect(client.isCommitted(), true);
    });

    test('完整握手：两个客户端', () {
      final password = 'test_password_123';

      // 客户端 1
      final client1 = SaeClientCurve25519.fromStrings(
        password: password,
        deviceIdSelf: 'client-1',
        deviceIdPeer: 'client-2',
      );

      // 客户端 2
      final client2 = SaeClientCurve25519.fromStrings(
        password: password,
        deviceIdSelf: 'client-2',
        deviceIdPeer: 'client-1',
      );

      // 步骤 1: 生成 commits
      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      // 步骤 2: 交换 commits
      client1.processCommit(commit2);
      client2.processCommit(commit1);

      // 步骤 3: 生成 confirms
      final confirm1 = client1.generateConfirm();
      final confirm2 = client2.generateConfirm();

      // 步骤 4: 验证 confirms
      client1.verifyConfirm(confirm2);
      client2.verifyConfirm(confirm1);

      // 步骤 5: 验证认证成功
      expect(client1.isAuthenticated(), true);
      expect(client2.isAuthenticated(), true);

      // 步骤 6: 验证 PMK 相同
      final pmk1 = client1.getPmk();
      final pmk2 = client2.getPmk();
      expect(pmk1, equals(pmk2));

      // 步骤 7: 验证 PMKID 相同
      final pmkid1 = client1.getPmkid();
      final pmkid2 = client2.getPmkid();
      expect(pmkid1, equals(pmkid2));

      print('✅ 完整握手成功！');
      print('PMK: ${base64Encode(pmk1)}');
      print('PMKID: ${base64Encode(pmkid1)}');
    });

    test('不同密码产生不同 PMK', () {
      // 客户端 1（密码1）
      final client1 = SaeClientCurve25519.fromStrings(
        password: 'password1',
        deviceIdSelf: 'device-1',
        deviceIdPeer: 'device-2',
      );

      // 客户端 2（密码2）
      final client2 = SaeClientCurve25519.fromStrings(
        password: 'password2',
        deviceIdSelf: 'device-2',
        deviceIdPeer: 'device-1',
      );

      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      client1.processCommit(commit2);
      client2.processCommit(commit1);

      client1.generateConfirm();
      final confirm2 = client2.generateConfirm();

      // 验证应该失败（不同密码）
      expect(
        () => client1.verifyConfirm(confirm2),
        throwsA(isA<StateError>()),
      );
    });

    test('不能在生成 commit 前处理对方 commit', () {
      final client = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client',
        deviceIdPeer: 'server',
      );

      final fakeCommit = {
        'group_id': 19,
        'scalar': base64Encode(Uint8List(32)),
        'element': base64Encode(Uint8List(32)),
      };

      expect(
        () => client.processCommit(fakeCommit),
        throwsA(isA<StateError>()),
      );
    });

    test('Commit 序列化正确', () {
      final client = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client',
        deviceIdPeer: 'server',
      );

      final commit = client.generateCommit();

      // 验证 Base64 编码
      final scalarBytes = base64Decode(commit['scalar'] as String);
      final elementBytes = base64Decode(commit['element'] as String);

      expect(scalarBytes.length, 32);
      expect(elementBytes.length, 32); // Edwards25519 压缩点
    });
  });
}
