import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockzero/services/sae_client_curve25519.dart';
import 'package:hashlib/hashlib.dart' as hashlib;
import 'dart:typed_data';

void main() {
  test('测试 fromStrings 构造函数', () {
    final password = 'test123';
    final deviceId1Str = 'client-1';
    final deviceId2Str = 'client-2';

    // 手动哈希设备ID
    final hashDeviceId = (String id) {
      final hash = hashlib.sha3_256.convert(utf8.encode(id));
      return Uint8List.fromList(hash.bytes);
    };

    final deviceId1 = hashDeviceId(deviceId1Str);
    final deviceId2 = hashDeviceId(deviceId2Str);

    print('=== 设备ID哈希 ===');
    print('Device 1 hash: ${base64Encode(deviceId1)}');
    print('Device 2 hash: ${base64Encode(deviceId2)}');

    // 使用 fromStrings
    final client1 = SaeClientCurve25519.fromStrings(
      password: password,
      deviceIdSelf: deviceId1Str,
      deviceIdPeer: deviceId2Str,
    );

    final client2 = SaeClientCurve25519.fromStrings(
      password: password,
      deviceIdSelf: deviceId2Str,
      deviceIdPeer: deviceId1Str,
    );

    // 生成 commits
    final commit1 = client1.generateCommit();
    final commit2 = client2.generateCommit();

    print('\n=== Commits ===');
    print('Client 1 Scalar: ${commit1['scalar']}');
    print('Client 2 Scalar: ${commit2['scalar']}');

    // 交换 commits
    client1.processCommit(commit2);
    client2.processCommit(commit1);

    // 检查 PMK
    final pmk1 = client1.getPmk();
    final pmk2 = client2.getPmk();

    print('\n=== PMK ===');
    print('Client 1 PMK: ${base64Encode(pmk1)}');
    print('Client 2 PMK: ${base64Encode(pmk2)}');
    print('PMK 相同: ${base64Encode(pmk1) == base64Encode(pmk2)}');

    if (base64Encode(pmk1) == base64Encode(pmk2)) {
      print('\n✅ PMK 匹配！');

      // 尝试 confirm
      final confirm1 = client1.generateConfirm();
      final confirm2 = client2.generateConfirm();

      print('\n=== Confirms ===');
      print('Client 1 Confirm: ${confirm1['confirm']}');
      print('Client 2 Confirm: ${confirm2['confirm']}');

      try {
        client1.verifyConfirm(confirm2);
        print('\n✅ Client 1 验证 Client 2 成功');
      } catch (e) {
        print('\n❌ Client 1 验证 Client 2 失败: $e');
      }

      try {
        client2.verifyConfirm(confirm1);
        print('✅ Client 2 验证 Client 1 成功');
      } catch (e) {
        print('❌ Client 2 验证 Client 1 失败: $e');
      }
    } else {
      print('\n❌ PMK 不匹配！');
    }
  });
}
