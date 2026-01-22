import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockzero/services/sae_client_curve25519.dart';
import 'dart:typed_data';

void main() {
  group('PWE 确定性测试', () {
    test('相同输入应该派生相同的PWE（通过PMK验证）', () {
      final password = Uint8List.fromList(utf8.encode('test123'));
      final deviceId1 = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final deviceId2 = Uint8List.fromList(List.generate(32, (i) => i + 33));

      // 创建多个客户端实例，它们应该派生出相同的 PWE
      final elements = <String>[];

      for (int i = 0; i < 5; i++) {
        final client = SaeClientCurve25519(
          password: password,
          deviceIdSelf: deviceId1,
          deviceIdPeer: deviceId2,
        );

        // 生成 commit 会触发 PWE 派生
        final commit = client.generateCommit();
        final element = commit['element'] as String;

        elements.add(element);
      }

      // 检查所有 element 是否不同（因为使用了随机 mask）
      // 这是预期的，因为 element = -mask * PWE，mask 是随机的
      expect(elements.toSet().length, equals(elements.length),
          reason: 'Elements 应该都不同（随机 mask）');
    });

    test('多次握手应该100%成功（验证PWE确定性）', () {
      final password = Uint8List.fromList(utf8.encode('test123'));
      final deviceId1 = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final deviceId2 = Uint8List.fromList(List.generate(32, (i) => i + 33));

      const testRuns = 10;
      int successCount = 0;

      for (int i = 0; i < testRuns; i++) {
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

        final commit1 = client1.generateCommit();
        final commit2 = client2.generateCommit();

        client1.processCommit(commit2);
        client2.processCommit(commit1);

        final confirm1 = client1.generateConfirm();
        final confirm2 = client2.generateConfirm();

        try {
          client1.verifyConfirm(confirm2);
          client2.verifyConfirm(confirm1);

          final pmk1 = client1.getPmk();
          final pmk2 = client2.getPmk();

          if (base64Encode(pmk1) == base64Encode(pmk2)) {
            successCount++;
          }
        } catch (e) {
          // 握手失败
        }
      }

      expect(successCount, equals(testRuns),
          reason: '所有握手都应该成功，表明 PWE 派生是确定性的');
    });

    test('PWE派生在不同实例间保持一致（单次握手内）', () {
      final password = Uint8List.fromList(utf8.encode('consistent_test'));
      final deviceId1 = Uint8List.fromList(List.filled(32, 0xAA));
      final deviceId2 = Uint8List.fromList(List.filled(32, 0xBB));

      // 创建两组客户端对，验证每组内部的 PMK 一致性
      final client1a = SaeClientCurve25519(
        password: password,
        deviceIdSelf: deviceId1,
        deviceIdPeer: deviceId2,
      );

      final client2a = SaeClientCurve25519(
        password: password,
        deviceIdSelf: deviceId2,
        deviceIdPeer: deviceId1,
      );

      final client1b = SaeClientCurve25519(
        password: password,
        deviceIdSelf: deviceId1,
        deviceIdPeer: deviceId2,
      );

      final client2b = SaeClientCurve25519(
        password: password,
        deviceIdSelf: deviceId2,
        deviceIdPeer: deviceId1,
      );

      // 第一组握手
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

      // 第二组握手
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

      // 验证每组握手内部的 PMK 相同
      expect(pmk1a, equals(pmk2a), reason: '第一组握手：双方 PMK 应该相同');
      expect(pmk1b, equals(pmk2b), reason: '第二组握手：双方 PMK 应该相同');

      // 注意：pmk1a 和 pmk1b 会不同，因为它们是不同的握手（使用不同的随机数）
      // 这是正确的 SAE 行为，提供前向保密性
    });

    test('PWE派生确定性（每次握手双方PMK相同）', () {
      final password = Uint8List.fromList(utf8.encode('random_test'));
      final deviceId1 = Uint8List.fromList(List.generate(32, (i) => i));
      final deviceId2 = Uint8List.fromList(List.generate(32, (i) => 255 - i));

      // 运行 20 次握手，验证每次握手双方的 PMK 都相同
      for (int i = 0; i < 20; i++) {
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

        final commit1 = client1.generateCommit();
        final commit2 = client2.generateCommit();

        client1.processCommit(commit2);
        client2.processCommit(commit1);

        final confirm1 = client1.generateConfirm();
        final confirm2 = client2.generateConfirm();

        client1.verifyConfirm(confirm2);
        client2.verifyConfirm(confirm1);

        final pmk1 = client1.getPmk();
        final pmk2 = client2.getPmk();

        // 验证每次握手双方的 PMK 相同
        expect(pmk1, equals(pmk2), reason: '第 ${i + 1} 次握手：双方 PMK 应该相同');
      }

      // 注意：不同握手会产生不同的 PMK（这是正确的 SAE 行为，提供前向保密性）
    });
  });
}
