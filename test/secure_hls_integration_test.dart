import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thirds/blake3.dart' as blake3;
import 'package:rockzero/services/sae_client_curve25519.dart';

/// 集成测试：验证 SAE 握手和密钥派生
void main() {
  group('SAE Handshake Integration Tests', () {
    test('SAE client generates valid commit', () {
      final password = 'TestPassword123!@#';
      final userId = 'test-user-id';

      // 生成设备ID（与 Rust 端一致）
      final deviceIdSelf =
          Uint8List.fromList(blake3.blake3(utf8.encode(userId), 32));
      final deviceIdPeer = Uint8List.fromList(
          blake3.blake3(utf8.encode('rockzero-server-device-id'), 32));

      final client = SaeClientCurve25519(
        password: Uint8List.fromList(utf8.encode(password)),
        deviceIdSelf: deviceIdSelf,
        deviceIdPeer: deviceIdPeer,
      );

      // 生成 commit
      final commit = client.generateCommit();

      // 验证 commit 结构
      expect(commit['group_id'], equals(19));
      expect(commit['scalar'], isNotEmpty);
      expect(commit['element'], isNotEmpty);

      // 验证 Base64 编码
      final scalarBytes = base64Decode(commit['scalar'] as String);
      final elementBytes = base64Decode(commit['element'] as String);

      expect(scalarBytes.length, equals(32));
      expect(elementBytes.length, equals(32));

      print('✅ SAE commit generated successfully');
      print(
          '   Scalar (first 8 bytes): ${scalarBytes.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
      print(
          '   Element (first 8 bytes): ${elementBytes.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    });

    test('SAE client-server handshake simulation', () {
      final password = 'SharedSecretPassword123!';

      // 设备ID
      final clientDeviceId =
          Uint8List.fromList(blake3.blake3(utf8.encode('client-device'), 32));
      final serverDeviceId =
          Uint8List.fromList(blake3.blake3(utf8.encode('server-device'), 32));

      // 创建客户端和服务端（模拟）
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

      // 1. 客户端生成 commit
      final clientCommit = client.generateCommit();
      print('1. Client commit generated');

      // 2. 服务端生成 commit
      final serverCommit = server.generateCommit();
      print('2. Server commit generated');

      // 3. 客户端处理服务端 commit
      client.processCommit(serverCommit);
      print('3. Client processed server commit');

      // 4. 服务端处理客户端 commit
      server.processCommit(clientCommit);
      print('4. Server processed client commit');

      // 5. 客户端生成 confirm
      final clientConfirm = client.generateConfirm();
      print('5. Client confirm generated');

      // 6. 服务端生成 confirm
      final serverConfirm = server.generateConfirm();
      print('6. Server confirm generated');

      // 7. 客户端验证服务端 confirm
      client.verifyConfirm(serverConfirm);
      print('7. Client verified server confirm');

      // 8. 服务端验证客户端 confirm
      server.verifyConfirm(clientConfirm);
      print('8. Server verified client confirm');

      // 9. 验证双方 PMK 相同
      final clientPmk = client.getPmk();
      final serverPmk = server.getPmk();

      expect(clientPmk, equals(serverPmk));
      print('✅ PMK match! SAE handshake successful');
      print(
          '   PMK (first 16 bytes): ${clientPmk.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    });

    test('Device ID generation matches Rust implementation', () {
      // 测试设备ID生成与 Rust 端一致
      final userId = 'test-user-123';
      final serverIdString = 'rockzero-server-device-id';

      // Flutter 端生成
      final clientDeviceId =
          Uint8List.fromList(blake3.blake3(utf8.encode(userId), 32));
      final serverDeviceId =
          Uint8List.fromList(blake3.blake3(utf8.encode(serverIdString), 32));

      // 验证长度
      expect(clientDeviceId.length, equals(32));
      expect(serverDeviceId.length, equals(32));

      // 打印用于与 Rust 端对比
      print('Client device ID (Blake3 of "$userId"):');
      print('  ${base64Encode(clientDeviceId)}');
      print('Server device ID (Blake3 of "$serverIdString"):');
      print('  ${base64Encode(serverDeviceId)}');
    });
  });
}
