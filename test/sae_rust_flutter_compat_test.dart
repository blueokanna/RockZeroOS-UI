import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockzero/services/sae_client_curve25519.dart';
import 'package:thirds/blake3.dart' as blake3;

/// 测试 Flutter SAE 客户端与 Rust 服务器的兼容性
///
/// 这个测试模拟了 Rust 服务器端的设备ID生成逻辑，
/// 确保 Flutter 客户端与 Rust 服务器能够成功完成 SAE 握手
void main() {
  group('Rust-Flutter SAE 兼容性测试', () {
    test('设备ID生成与Rust一致（使用Blake3）', () {
      // Rust 端使用 blake3::hash(b"rockzero-server-device-id")
      const serverIdString = 'rockzero-server-device-id';
      final serverIdBytes = utf8.encode(serverIdString);
      final serverDeviceId =
          Uint8List.fromList(blake3.blake3(serverIdBytes, 32));

      // Rust 端使用 blake3::hash(user_id.as_bytes())
      const userId = 'test_user_123';
      final clientDeviceId =
          Uint8List.fromList(blake3.blake3(utf8.encode(userId), 32));

      print('Server Device ID (Blake3): ${base64Encode(serverDeviceId)}');
      print('Client Device ID (Blake3): ${base64Encode(clientDeviceId)}');

      // 验证长度
      expect(serverDeviceId.length, 32);
      expect(clientDeviceId.length, 32);

      // 验证两个ID不同
      expect(serverDeviceId, isNot(equals(clientDeviceId)));
    });

    test('模拟 Rust 服务器和 Flutter 客户端握手', () {
      // 共享密码（与 Rust 服务器相同）
      const password = 'secure_password_hash_123';

      // 生成设备ID（与 Rust 服务器使用相同的方式）
      const serverIdString = 'rockzero-server-device-id';
      final serverDeviceId = Uint8List.fromList(
        blake3.blake3(utf8.encode(serverIdString), 32),
      );

      const userId = 'test_user_123';
      final clientDeviceId = Uint8List.fromList(
        blake3.blake3(utf8.encode(userId), 32),
      );

      // 创建客户端（Flutter 端）
      // deviceIdSelf = client, deviceIdPeer = server
      final flutterClient = SaeClientCurve25519(
        password: Uint8List.fromList(utf8.encode(password)),
        deviceIdSelf: clientDeviceId,
        deviceIdPeer: serverDeviceId,
      );

      // 创建服务器模拟（Rust 端）
      // 注意：Rust SaeServer 使用 (mac_self=server, mac_peer=client)
      final rustServerSimulator = SaeClientCurve25519(
        password: Uint8List.fromList(utf8.encode(password)),
        deviceIdSelf: serverDeviceId,
        deviceIdPeer: clientDeviceId,
      );

      // Flutter 客户端生成 commit
      final clientCommit = flutterClient.generateCommit();
      print('Flutter Client Commit:');
      print('  scalar: ${clientCommit['scalar']}');
      print('  element: ${clientCommit['element']}');

      // Rust 服务器模拟生成 commit
      final serverCommit = rustServerSimulator.generateCommit();
      print('Rust Server Commit:');
      print('  scalar: ${serverCommit['scalar']}');
      print('  element: ${serverCommit['element']}');

      // 双方处理对方的 commit
      flutterClient.processCommit(serverCommit);
      rustServerSimulator.processCommit(clientCommit);

      // 验证 PMK 一致
      final clientPmk = flutterClient.getPmk();
      final serverPmk = rustServerSimulator.getPmk();

      print('Flutter Client PMK: ${base64Encode(clientPmk)}');
      print('Rust Server PMK: ${base64Encode(serverPmk)}');
      print('PMK Match: ${base64Encode(clientPmk) == base64Encode(serverPmk)}');

      expect(clientPmk, equals(serverPmk),
          reason: 'PMK must match between client and server');

      // 验证 confirm 流程
      final clientConfirm = flutterClient.generateConfirm();
      final serverConfirm = rustServerSimulator.generateConfirm();

      print('Flutter Client Confirm: ${clientConfirm['confirm']}');
      print('Rust Server Confirm: ${serverConfirm['confirm']}');

      // 双方验证对方的 confirm
      flutterClient.verifyConfirm(serverConfirm);
      rustServerSimulator.verifyConfirm(clientConfirm);

      expect(flutterClient.isAuthenticated(), true);
      expect(rustServerSimulator.isAuthenticated(), true);

      print('✅ Rust-Flutter SAE 握手成功！');
    });

    test('多次握手稳定性测试', () {
      const password = 'test_password';
      const serverIdString = 'rockzero-server-device-id';
      final serverDeviceId = Uint8List.fromList(
        blake3.blake3(utf8.encode(serverIdString), 32),
      );

      const userId = 'user_stability_test';
      final clientDeviceId = Uint8List.fromList(
        blake3.blake3(utf8.encode(userId), 32),
      );

      int successCount = 0;
      const iterations = 10;

      for (int i = 0; i < iterations; i++) {
        try {
          final client = SaeClientCurve25519(
            password: Uint8List.fromList(utf8.encode(password)),
            deviceIdSelf: clientDeviceId,
            deviceIdPeer: serverDeviceId,
          );

          final server = SaeClientCurve25519(
            password: Uint8List.fromList(utf8.encode(password)),
            deviceIdSelf: serverDeviceId,
            deviceIdPeer: clientDeviceId,
          );

          final clientCommit = client.generateCommit();
          final serverCommit = server.generateCommit();

          client.processCommit(serverCommit);
          server.processCommit(clientCommit);

          // 验证 PMK 一致
          expect(client.getPmk(), equals(server.getPmk()));

          // 验证 confirm
          final clientConfirm = client.generateConfirm();
          final serverConfirm = server.generateConfirm();

          client.verifyConfirm(serverConfirm);
          server.verifyConfirm(clientConfirm);

          successCount++;
        } catch (e) {
          print('迭代 $i 失败: $e');
        }
      }

      print('✅ 稳定性测试: $successCount/$iterations 成功');
      expect(successCount, iterations);
    });

    test('PMKID 计算一致性', () {
      const password = 'pmkid_test_password';
      const serverIdString = 'rockzero-server-device-id';
      final serverDeviceId = Uint8List.fromList(
        blake3.blake3(utf8.encode(serverIdString), 32),
      );

      const userId = 'pmkid_test_user';
      final clientDeviceId = Uint8List.fromList(
        blake3.blake3(utf8.encode(userId), 32),
      );

      final client = SaeClientCurve25519(
        password: Uint8List.fromList(utf8.encode(password)),
        deviceIdSelf: clientDeviceId,
        deviceIdPeer: serverDeviceId,
      );

      final server = SaeClientCurve25519(
        password: Uint8List.fromList(utf8.encode(password)),
        deviceIdSelf: serverDeviceId,
        deviceIdPeer: clientDeviceId,
      );

      final clientCommit = client.generateCommit();
      final serverCommit = server.generateCommit();

      client.processCommit(serverCommit);
      server.processCommit(clientCommit);

      final clientPmkid = client.getPmkid();
      final serverPmkid = server.getPmkid();

      print('Client PMKID: ${base64Encode(clientPmkid)}');
      print('Server PMKID: ${base64Encode(serverPmkid)}');

      expect(clientPmkid, equals(serverPmkid), reason: 'PMKID must match');
      expect(clientPmkid.length, 16, reason: 'PMKID must be 16 bytes');

      print('✅ PMKID 一致性验证通过！');
    });
  });
}
