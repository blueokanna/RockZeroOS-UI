import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockzero/services/sae_client_curve25519.dart';

void main() {
  group('SAE 基础功能测试', () {
    test('两个客户端可以完成握手', () {
      // 使用固定的设备ID（32字节）
      final deviceId1 = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final deviceId2 = Uint8List.fromList(List.generate(32, (i) => i + 33));
      final password = Uint8List.fromList(utf8.encode('test_password_123'));

      // 创建两个客户端
      final client1 = SaeClientCurve25519(
        password: password,
        deviceIdSelf: deviceId1,
        deviceIdPeer: deviceId2,
      );

      final client2 = SaeClientCurve25519(
        password: password,
        deviceIdSelf: deviceId2,
        deviceIdPeer: deviceId1,
      );

      // 1. 生成 commits
      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      expect(commit1['group_id'], equals(19));
      expect(commit2['group_id'], equals(19));

      // 2. 交换 commits
      client1.processCommit(commit2);
      client2.processCommit(commit1);

      // 3. 验证 PMK 相同
      final pmk1 = client1.getPmk();
      final pmk2 = client2.getPmk();

      expect(pmk1.length, equals(32));
      expect(pmk2.length, equals(32));
      expect(pmk1, equals(pmk2), reason: 'PMK 应该相同');

      // 4. 验证 KCK 相同
      final kck1 = client1.getKck();
      final kck2 = client2.getKck();

      expect(kck1.length, equals(32));
      expect(kck2.length, equals(32));
      expect(kck1, equals(kck2), reason: 'KCK 应该相同');

      // 5. 生成 confirms
      final confirm1 = client1.generateConfirm();
      final confirm2 = client2.generateConfirm();

      // 6. 验证 confirms
      expect(() => client1.verifyConfirm(confirm2), returnsNormally);
      expect(() => client2.verifyConfirm(confirm1), returnsNormally);

      // 7. 验证认证状态
      expect(client1.isAuthenticated(), isTrue);
      expect(client2.isAuthenticated(), isTrue);
    });

    test('不同密码产生不同的 PMK', () {
      final deviceId1 = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final deviceId2 = Uint8List.fromList(List.generate(32, (i) => i + 33));
      final password1 = Uint8List.fromList(utf8.encode('password1'));
      final password2 = Uint8List.fromList(utf8.encode('password2'));

      final client1 = SaeClientCurve25519(
        password: password1,
        deviceIdSelf: deviceId1,
        deviceIdPeer: deviceId2,
      );

      final client2 = SaeClientCurve25519(
        password: password2,
        deviceIdSelf: deviceId2,
        deviceIdPeer: deviceId1,
      );

      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      client1.processCommit(commit2);
      client2.processCommit(commit1);

      final pmk1 = client1.getPmk();
      final pmk2 = client2.getPmk();

      expect(pmk1, isNot(equals(pmk2)), reason: '不同密码应该产生不同的 PMK');
    });

    test('fromStrings 构造函数正常工作', () {
      final client1 = SaeClientCurve25519.fromStrings(
        password: 'test123',
        deviceIdSelf: 'device1',
        deviceIdPeer: 'device2',
      );

      final client2 = SaeClientCurve25519.fromStrings(
        password: 'test123',
        deviceIdSelf: 'device2',
        deviceIdPeer: 'device1',
      );

      // 生成 commits
      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      // 交换 commits
      client1.processCommit(commit2);
      client2.processCommit(commit1);

      // 验证 PMK 相同
      final pmk1 = client1.getPmk();
      final pmk2 = client2.getPmk();

      expect(pmk1, equals(pmk2), reason: 'PMK 应该相同');

      // 验证 confirms
      final confirm1 = client1.generateConfirm();
      final confirm2 = client2.generateConfirm();

      expect(() => client1.verifyConfirm(confirm2), returnsNormally);
      expect(() => client2.verifyConfirm(confirm1), returnsNormally);
    });
  });
}
