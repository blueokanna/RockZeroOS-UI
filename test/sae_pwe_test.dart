import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockzero/services/sae_client_curve25519.dart';
import 'package:rockzero/services/sae_utils.dart';
import 'dart:typed_data';

void main() {
  group('PWE 派生一致性测试', () {
    test('相同密码和设备ID应该派生相同的PMK', () {
      final password = 'test123';
      final deviceId1Str = 'client-1';
      final deviceId2Str = 'client-2';

      // 使用工具函数哈希设备ID
      final deviceId1 = SaeUtils.hashDeviceId(deviceId1Str);
      final deviceId2 = SaeUtils.hashDeviceId(deviceId2Str);

      // 创建两个客户端（设备ID顺序相反）
      final client1 = SaeClientCurve25519(
        password: Uint8List.fromList(utf8.encode(password)),
        deviceIdSelf: deviceId1,
        deviceIdPeer: deviceId2,
      );

      final client2 = SaeClientCurve25519(
        password: Uint8List.fromList(utf8.encode(password)),
        deviceIdSelf: deviceId2,
        deviceIdPeer: deviceId1,
      );

      // 生成 commits（这会触发 PWE 派生）
      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      // 验证 commits 格式正确
      expect(commit1['group_id'], 19);
      expect(commit2['group_id'], 19);
      expect(commit1['scalar'], isNotNull);
      expect(commit1['element'], isNotNull);
      expect(commit2['scalar'], isNotNull);
      expect(commit2['element'], isNotNull);

      // 注意：scalar 和 element 应该不同（因为是随机生成的）
      expect(commit1['scalar'], isNot(equals(commit2['scalar'])));
      expect(commit1['element'], isNot(equals(commit2['element'])));

      // 交换 commits
      client1.processCommit(commit2);
      client2.processCommit(commit1);

      // 生成和验证 confirms
      final confirm1 = client1.generateConfirm();
      final confirm2 = client2.generateConfirm();

      client1.verifyConfirm(confirm2);
      client2.verifyConfirm(confirm1);

      // 检查 PMK
      final pmk1 = client1.getPmk();
      final pmk2 = client2.getPmk();

      // PMK 应该完全相同
      expect(pmk1, equals(pmk2), reason: 'PMK 应该匹配，表明 PWE 派生正确');

      // 检查 PMKID
      final pmkid1 = client1.getPmkid();
      final pmkid2 = client2.getPmkid();

      expect(pmkid1, equals(pmkid2), reason: 'PMKID 应该匹配');

      // 验证认证状态
      expect(client1.isAuthenticated(), true);
      expect(client2.isAuthenticated(), true);
    });

    test('不同密码应该派生不同的PMK', () {
      final deviceId1 = SaeUtils.hashDeviceId('device-1');
      final deviceId2 = SaeUtils.hashDeviceId('device-2');

      final client1 = SaeClientCurve25519(
        password: Uint8List.fromList(utf8.encode('password1')),
        deviceIdSelf: deviceId1,
        deviceIdPeer: deviceId2,
      );

      final client2 = SaeClientCurve25519(
        password: Uint8List.fromList(utf8.encode('password2')),
        deviceIdSelf: deviceId2,
        deviceIdPeer: deviceId1,
      );

      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      client1.processCommit(commit2);
      client2.processCommit(commit1);

      final confirm1 = client1.generateConfirm();
      final confirm2 = client2.generateConfirm();

      // 验证应该失败，因为密码不同
      expect(
        () => client1.verifyConfirm(confirm2),
        throwsA(isA<StateError>()),
        reason: '不同密码应该导致 confirm 验证失败',
      );

      // 同样，反向验证也应该失败
      expect(
        () => client2.verifyConfirm(confirm1),
        throwsA(isA<StateError>()),
        reason: '不同密码应该导致 confirm 验证失败',
      );
    });

    test('设备ID顺序不影响PWE派生', () {
      final password = Uint8List.fromList(utf8.encode('shared_password'));
      final deviceId1 = SaeUtils.hashDeviceId('device-A');
      final deviceId2 = SaeUtils.hashDeviceId('device-B');

      // 正序
      final clientForward = SaeClientCurve25519(
        password: password,
        deviceIdSelf: deviceId1,
        deviceIdPeer: deviceId2,
      );

      // 反序
      final clientReverse = SaeClientCurve25519(
        password: password,
        deviceIdSelf: deviceId2,
        deviceIdPeer: deviceId1,
      );

      final commitForward = clientForward.generateCommit();
      final commitReverse = clientReverse.generateCommit();

      clientForward.processCommit(commitReverse);
      clientReverse.processCommit(commitForward);

      final confirmForward = clientForward.generateConfirm();
      final confirmReverse = clientReverse.generateConfirm();

      clientForward.verifyConfirm(confirmReverse);
      clientReverse.verifyConfirm(confirmForward);

      final pmkForward = clientForward.getPmk();
      final pmkReverse = clientReverse.getPmk();

      expect(pmkForward, equals(pmkReverse), reason: '设备ID顺序不应影响最终的PMK');
    });
  });
}
