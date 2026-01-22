import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockzero/services/sae_client_curve25519.dart';

void main() {
  test('测试随机性是否影响 PWE', () {
    final password = 'test123';

    // 运行多次，看 PMK 是否每次都不同
    for (int i = 0; i < 3; i++) {
      // ignore: avoid_print
      print('\n=== 运行 ${i + 1} ===');

      final client1 = SaeClientCurve25519.fromStrings(
        password: password,
        deviceIdSelf: 'client-1',
        deviceIdPeer: 'client-2',
      );

      final client2 = SaeClientCurve25519.fromStrings(
        password: password,
        deviceIdSelf: 'client-2',
        deviceIdPeer: 'client-1',
      );

      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      client1.processCommit(commit2);
      client2.processCommit(commit1);

      final pmk1 = client1.getPmk();
      final pmk2 = client2.getPmk();

      // ignore: avoid_print
      print('Client 1 PMK: ${base64Encode(pmk1)}');
      // ignore: avoid_print
      print('Client 2 PMK: ${base64Encode(pmk2)}');
      // ignore: avoid_print
      print('匹配: ${base64Encode(pmk1) == base64Encode(pmk2)}');
    }
  });
}
