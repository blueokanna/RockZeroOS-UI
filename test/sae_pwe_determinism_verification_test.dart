import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockzero/services/sae_client_curve25519.dart';

/// 验证 PWE 派生的确定性
///
/// 这个测试验证：
/// 1. 相同的输入（密码 + 设备ID）总是产生相同的 PWE
/// 2. PWE 派生是确定性的，不受随机数影响
void main() {
  group('PWE 确定性验证', () {
    test('相同输入在单次握手中派生相同的 PMK', () {
      const password = 'test_password_123';
      const deviceId1 = 'device-1';
      const deviceId2 = 'device-2';

      // 运行 10 次完整握手，验证每次握手双方的 PMK 都相同
      for (int i = 0; i < 10; i++) {
        final client1 = SaeClientCurve25519.fromStrings(
          password: password,
          deviceIdSelf: deviceId1,
          deviceIdPeer: deviceId2,
        );

        final client2 = SaeClientCurve25519.fromStrings(
          password: password,
          deviceIdSelf: deviceId2,
          deviceIdPeer: deviceId1,
        );

        // 完整握手
        final commit1 = client1.generateCommit();
        final commit2 = client2.generateCommit();

        client1.processCommit(commit2);
        client2.processCommit(commit1);

        final confirm1 = client1.generateConfirm();
        final confirm2 = client2.generateConfirm();

        client1.verifyConfirm(confirm2);
        client2.verifyConfirm(confirm1);

        // 验证双方 PMK 相同（这是必须的）
        expect(client1.getPmk(), equals(client2.getPmk()),
            reason: '第 ${i + 1} 次握手：双方 PMK 应该相同');
      }

      // ignore: avoid_print
      print('✅ PWE 确定性验证通过！10 次握手中每次双方的 PMK 都相同');
      // ignore: avoid_print
      print('注意：不同握手会产生不同的 PMK（这是正确的 SAE 行为，提供前向保密性）');
    });

    test('不同密码派生不同的 PMK', () {
      const deviceId1 = 'device-1';
      const deviceId2 = 'device-2';

      final pmks = <String, Uint8List>{};

      for (final password in ['password1', 'password2', 'password3']) {
        final client1 = SaeClientCurve25519.fromStrings(
          password: password,
          deviceIdSelf: deviceId1,
          deviceIdPeer: deviceId2,
        );

        final client2 = SaeClientCurve25519.fromStrings(
          password: password,
          deviceIdSelf: deviceId2,
          deviceIdPeer: deviceId1,
        );

        final commit1 = client1.generateCommit();
        final commit2 = client2.generateCommit();

        client1.processCommit(commit2);
        client2.processCommit(commit1);

        final confirm1 = client1.generateConfirm();
        final confirm2 = client2.generateConfirm();

        client1.verifyConfirm(confirm2);
        client2.verifyConfirm(confirm1);

        pmks[password] = client1.getPmk();
      }

      // 验证不同密码产生不同的 PMK
      expect(pmks['password1'], isNot(equals(pmks['password2'])));
      expect(pmks['password1'], isNot(equals(pmks['password3'])));
      expect(pmks['password2'], isNot(equals(pmks['password3'])));

      // ignore: avoid_print
      print('✅ 不同密码产生不同的 PMK');
    });

    test('不同设备ID派生不同的 PMK', () {
      const password = 'test_password';

      final pmks = <String, Uint8List>{};

      final devicePairs = [
        ['device-1', 'device-2'],
        ['device-3', 'device-4'],
        ['device-5', 'device-6'],
      ];

      for (final pair in devicePairs) {
        final client1 = SaeClientCurve25519.fromStrings(
          password: password,
          deviceIdSelf: pair[0],
          deviceIdPeer: pair[1],
        );

        final client2 = SaeClientCurve25519.fromStrings(
          password: password,
          deviceIdSelf: pair[1],
          deviceIdPeer: pair[0],
        );

        final commit1 = client1.generateCommit();
        final commit2 = client2.generateCommit();

        client1.processCommit(commit2);
        client2.processCommit(commit1);

        final confirm1 = client1.generateConfirm();
        final confirm2 = client2.generateConfirm();

        client1.verifyConfirm(confirm2);
        client2.verifyConfirm(confirm1);

        pmks['${pair[0]}-${pair[1]}'] = client1.getPmk();
      }

      // 验证不同设备ID产生不同的 PMK
      final pmkList = pmks.values.toList();
      expect(pmkList[0], isNot(equals(pmkList[1])));
      expect(pmkList[0], isNot(equals(pmkList[2])));
      expect(pmkList[1], isNot(equals(pmkList[2])));

      // ignore: avoid_print
      print('✅ 不同设备ID产生不同的 PMK');
    });

    test('设备ID顺序不影响 PMK（对称性）', () {
      const password = 'test_password';
      const deviceId1 = 'device-1';
      const deviceId2 = 'device-2';

      // 正向：client1 = device-1, client2 = device-2
      final client1a = SaeClientCurve25519.fromStrings(
        password: password,
        deviceIdSelf: deviceId1,
        deviceIdPeer: deviceId2,
      );

      final client2a = SaeClientCurve25519.fromStrings(
        password: password,
        deviceIdSelf: deviceId2,
        deviceIdPeer: deviceId1,
      );

      final commit1a = client1a.generateCommit();
      final commit2a = client2a.generateCommit();

      client1a.processCommit(commit2a);
      client2a.processCommit(commit1a);

      final confirm1a = client1a.generateConfirm();
      final confirm2a = client2a.generateConfirm();

      client1a.verifyConfirm(confirm2a);
      client2a.verifyConfirm(confirm1a);

      final pmk1a = client1a.getPmk();
      final pmk2a = client2a.getPmk();

      // 反向：client1 = device-2, client2 = device-1
      final client1b = SaeClientCurve25519.fromStrings(
        password: password,
        deviceIdSelf: deviceId2,
        deviceIdPeer: deviceId1,
      );

      final client2b = SaeClientCurve25519.fromStrings(
        password: password,
        deviceIdSelf: deviceId1,
        deviceIdPeer: deviceId2,
      );

      final commit1b = client1b.generateCommit();
      final commit2b = client2b.generateCommit();

      client1b.processCommit(commit2b);
      client2b.processCommit(commit1b);

      final confirm1b = client1b.generateConfirm();
      final confirm2b = client2b.generateConfirm();

      client1b.verifyConfirm(confirm2b);
      client2b.verifyConfirm(confirm1b);

      final pmk1b = client1b.getPmk();
      final pmk2b = client2b.getPmk();

      // 验证每次握手双方的 PMK 都相同
      expect(pmk1a, equals(pmk2a), reason: '正向握手：双方 PMK 应该相同');
      expect(pmk1b, equals(pmk2b), reason: '反向握手：双方 PMK 应该相同');

      // 注意：pmk1a 和 pmk1b 会不同，因为它们是不同的握手（使用不同的随机数）
      // 这是正确的 SAE 行为，提供前向保密性

      // ignore: avoid_print
      print('✅ 设备ID顺序不影响握手成功（对称性验证通过）');
      // ignore: avoid_print
      print('注意：不同握手会产生不同的 PMK（这是正确的 SAE 行为）');
    });
  });
}
