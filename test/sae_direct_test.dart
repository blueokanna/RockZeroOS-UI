import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockzero/services/sae_client_curve25519.dart';

void main() {
  test('直接测试 SaeClientCurve25519 - 详细调试', () {
    // 创建客户端
    final client1 = SaeClientCurve25519.fromStrings(
      password: 'test123',
      deviceIdSelf: 'client-1',
      deviceIdPeer: 'client-2',
    );

    final client2 = SaeClientCurve25519.fromStrings(
      password: 'test123',
      deviceIdSelf: 'client-2',
      deviceIdPeer: 'client-1',
    );

    // 生成 commits
    final commit1 = client1.generateCommit();
    final commit2 = client2.generateCommit();

    print('=== Commits ===');
    print('Commit 1: scalar=${commit1['scalar']}, element=${commit1['element']}');
    print('Commit 2: scalar=${commit2['scalar']}, element=${commit2['element']}');

    // 交换 commits
    client1.processCommit(commit2);
    client2.processCommit(commit1);

    // 获取 PMK
    final pmk1 = client1.getPmk();
    final pmk2 = client2.getPmk();

    print('\n=== PMK ===');
    print('PMK 1: ${base64Encode(pmk1)}');
    print('PMK 2: ${base64Encode(pmk2)}');
    print('PMK 相同: ${base64Encode(pmk1) == base64Encode(pmk2)}');

    // 验证 PMK 相同
    expect(pmk1, equals(pmk2), reason: 'PMK 应该相同');

    // 生成 confirms
    final confirm1 = client1.generateConfirm();
    final confirm2 = client2.generateConfirm();

    print('\n=== Confirms ===');
    print('Confirm 1: ${confirm1['confirm']}');
    print('Confirm 2: ${confirm2['confirm']}');

    // 验证 confirms
    client1.verifyConfirm(confirm2);
    client2.verifyConfirm(confirm1);

    print('\n✅ 握手成功！');
    expect(client1.isAuthenticated(), isTrue);
    expect(client2.isAuthenticated(), isTrue);
  });

  test('重复多次测试 SaeClientCurve25519', () {
    for (int i = 0; i < 10; i++) {
      final client1 = SaeClientCurve25519.fromStrings(
        password: 'test123',
        deviceIdSelf: 'client-1',
        deviceIdPeer: 'client-2',
      );

      final client2 = SaeClientCurve25519.fromStrings(
        password: 'test123',
        deviceIdSelf: 'client-2',
        deviceIdPeer: 'client-1',
      );

      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      client1.processCommit(commit2);
      client2.processCommit(commit1);

      final pmk1 = client1.getPmk();
      final pmk2 = client2.getPmk();

      expect(pmk1, equals(pmk2), reason: 'PMK 应该相同 (迭代 ${i + 1})');

      final confirm1 = client1.generateConfirm();
      final confirm2 = client2.generateConfirm();

      client1.verifyConfirm(confirm2);
      client2.verifyConfirm(confirm1);

      expect(client1.isAuthenticated(), isTrue);
      expect(client2.isAuthenticated(), isTrue);
    }

    print('✅ 所有 10 次迭代都成功！');
  });
}
