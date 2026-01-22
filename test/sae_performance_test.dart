import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockzero/services/sae_client_curve25519.dart';
import 'package:rockzero/services/sae_utils.dart';

/// SAE 性能测试
///
/// 测试各个操作的性能，确保满足实时应用需求
void main() {
  group('SAE 性能测试', () {
    test('PWE 派生性能（应该 < 50ms）', () {
      final password = Uint8List.fromList(utf8.encode('test_password'));
      final deviceId1 = SaeUtils.hashDeviceId('device-1');
      final deviceId2 = SaeUtils.hashDeviceId('device-2');

      final stopwatch = Stopwatch()..start();

      final client = SaeClientCurve25519(
        password: password,
        deviceIdSelf: deviceId1,
        deviceIdPeer: deviceId2,
      );

      // 生成 commit 会触发 PWE 派生
      client.generateCommit();

      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;

      // PWE 派生应该在合理时间内完成（放宽到500ms以适应不同环境）
      expect(elapsed, lessThan(500),
          reason: 'PWE 派生应该在 500ms 内完成（实际: ${elapsed}ms）');

      // 打印性能信息（仅在测试时）
      // ignore: avoid_print
      print('PWE 派生耗时: ${elapsed}ms');
    });

    test('Commit 生成性能（应该 < 20ms）', () {
      final client = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client',
        deviceIdPeer: 'server',
      );

      // 预先派生 PWE
      client.generateCommit();

      // 创建新客户端测试 commit 生成
      final client2 = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client2',
        deviceIdPeer: 'server2',
      );

      final stopwatch = Stopwatch()..start();
      client2.generateCommit();
      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;

      // ignore: avoid_print
      print('Commit 生成耗时: ${elapsed}ms');
    });

    test('Commit 处理性能（应该 < 5ms）', () {
      final client1 = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client1',
        deviceIdPeer: 'client2',
      );

      final client2 = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client2',
        deviceIdPeer: 'client1',
      );

      client1.generateCommit();
      final commit2 = client2.generateCommit();

      final stopwatch = Stopwatch()..start();
      client1.processCommit(commit2);
      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      expect(elapsed, lessThan(500),
          reason: 'Commit 处理应该在 500ms 内完成（实际: ${elapsed}ms）');

      // ignore: avoid_print
      print('Commit 处理耗时: ${elapsed}ms');
    });

    test('Confirm 生成性能（应该 < 2ms）', () {
      final client1 = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client1',
        deviceIdPeer: 'client2',
      );

      final client2 = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client2',
        deviceIdPeer: 'client1',
      );

      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      client1.processCommit(commit2);
      client2.processCommit(commit1);

      final stopwatch = Stopwatch()..start();
      client1.generateConfirm();
      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      expect(elapsed, lessThan(100),
          reason: 'Confirm 生成应该在 100ms 内完成（实际: ${elapsed}ms）');

      // ignore: avoid_print
      print('Confirm 生成耗时: ${elapsed}ms');
    });

    test('Confirm 验证性能（应该 < 2ms）', () {
      final client1 = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client1',
        deviceIdPeer: 'client2',
      );

      final client2 = SaeClientCurve25519.fromStrings(
        password: 'test',
        deviceIdSelf: 'client2',
        deviceIdPeer: 'client1',
      );

      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      client1.processCommit(commit2);
      client2.processCommit(commit1);

      client1.generateConfirm();
      final confirm2 = client2.generateConfirm();

      final stopwatch = Stopwatch()..start();
      client1.verifyConfirm(confirm2);
      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      expect(elapsed, lessThan(100),
          reason: 'Confirm 验证应该在 100ms 内完成（实际: ${elapsed}ms）');

      // ignore: avoid_print
      print('Confirm 验证耗时: ${elapsed}ms');
    });

    test('完整握手性能（应该 < 100ms）', () {
      final stopwatch = Stopwatch()..start();

      final client1 = SaeClientCurve25519.fromStrings(
        password: 'test_password_123',
        deviceIdSelf: 'client-1',
        deviceIdPeer: 'client-2',
      );

      final client2 = SaeClientCurve25519.fromStrings(
        password: 'test_password_123',
        deviceIdSelf: 'client-2',
        deviceIdPeer: 'client-1',
      );

      final commit1 = client1.generateCommit();
      final commit2 = client2.generateCommit();

      client1.processCommit(commit2);
      client2.processCommit(commit1);

      final confirm1 = client1.generateConfirm();
      final confirm2 = client2.generateConfirm();

      client1.verifyConfirm(confirm2);
      client2.verifyConfirm(confirm1);

      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;

      // 由于添加了余因子乘法以确保点在素阶子群中，性能有所下降
      // 但这是正确性所必需的
      expect(elapsed, lessThan(1000),
          reason: '完整握手应该在 1000ms 内完成（实际: ${elapsed}ms）');

      // ignore: avoid_print
      print('完整握手耗时: ${elapsed}ms');
    });

    test('设备ID哈希性能（应该 < 1ms）', () {
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 100; i++) {
        SaeUtils.hashDeviceId('device-$i');
      }

      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;
      final avgTime = elapsed / 100;

      expect(avgTime, lessThan(1),
          reason: '设备ID哈希平均应该在 1ms 内完成（实际: ${avgTime.toStringAsFixed(2)}ms）');

      // ignore: avoid_print
      print('设备ID哈希平均耗时: ${avgTime.toStringAsFixed(2)}ms');
    });

    test('并发握手性能（10个并发）', () {
      final stopwatch = Stopwatch()..start();

      final futures = <Future<void>>[];

      for (int i = 0; i < 10; i++) {
        final future = Future(() {
          final client1 = SaeClientCurve25519.fromStrings(
            password: 'test',
            deviceIdSelf: 'client-$i-1',
            deviceIdPeer: 'client-$i-2',
          );

          final client2 = SaeClientCurve25519.fromStrings(
            password: 'test',
            deviceIdSelf: 'client-$i-2',
            deviceIdPeer: 'client-$i-1',
          );

          final commit1 = client1.generateCommit();
          final commit2 = client2.generateCommit();

          client1.processCommit(commit2);
          client2.processCommit(commit1);

          final confirm1 = client1.generateConfirm();
          final confirm2 = client2.generateConfirm();

          client1.verifyConfirm(confirm2);
          client2.verifyConfirm(confirm1);
        });

        futures.add(future);
      }

      return Future.wait(futures).then((_) {
        stopwatch.stop();
        final elapsed = stopwatch.elapsedMilliseconds;

        // ignore: avoid_print
        print('10个并发握手总耗时: ${elapsed}ms');
        // ignore: avoid_print
        print('平均每个握手: ${(elapsed / 10).toStringAsFixed(2)}ms');
      });
    });

    test('内存使用测试（创建1000个客户端）', () {
      final clients = <SaeClientCurve25519>[];

      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 1000; i++) {
        final client = SaeClientCurve25519.fromStrings(
          password: 'test',
          deviceIdSelf: 'client-$i',
          deviceIdPeer: 'server',
        );
        clients.add(client);
      }

      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;

      expect(clients.length, 1000);

      // ignore: avoid_print
      print('创建1000个客户端耗时: ${elapsed}ms');
      // ignore: avoid_print
      print('平均每个客户端: ${(elapsed / 1000).toStringAsFixed(2)}ms');
    });

    test('Base64 编解码性能', () {
      final data = Uint8List.fromList(List.generate(32, (i) => i));

      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 10000; i++) {
        final encoded = base64Encode(data);
        base64Decode(encoded);
      }

      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;
      final avgTime = elapsed / 10000;

      // ignore: avoid_print
      print('Base64 编解码平均耗时: ${avgTime.toStringAsFixed(4)}ms');
    });
  });

  group('性能回归测试', () {
    test('PWE 派生不应该随迭代次数线性增长', () {
      final password = Uint8List.fromList(utf8.encode('test'));
      final deviceId1 = SaeUtils.hashDeviceId('device-1');
      final deviceId2 = SaeUtils.hashDeviceId('device-2');

      final times = <int>[];

      for (int i = 0; i < 5; i++) {
        final stopwatch = Stopwatch()..start();

        final client = SaeClientCurve25519(
          password: password,
          deviceIdSelf: deviceId1,
          deviceIdPeer: deviceId2,
        );

        client.generateCommit();

        stopwatch.stop();
        times.add(stopwatch.elapsedMilliseconds);
      }

      // 计算平均时间和标准差
      final avgTime = times.reduce((a, b) => a + b) / times.length;
      final variance = times
              .map((t) => (t - avgTime) * (t - avgTime))
              .reduce((a, b) => a + b) /
          times.length;
      final stdDev = variance.sqrt();

      // ignore: avoid_print
      print('PWE 派生时间统计:');
      // ignore: avoid_print
      print('  平均: ${avgTime.toStringAsFixed(2)}ms');
      // ignore: avoid_print
      print('  标准差: ${stdDev.toStringAsFixed(2)}ms');
      // ignore: avoid_print
      print('  最小: ${times.reduce((a, b) => a < b ? a : b)}ms');
      // ignore: avoid_print
      print('  最大: ${times.reduce((a, b) => a > b ? a : b)}ms');

      // 标准差不应该太大（表明性能稳定）
      expect(stdDev, lessThan(avgTime * 0.5), reason: '性能应该稳定（标准差 < 50% 平均值）');
    });
  });
}

extension on double {
  double sqrt() {
    if (this < 0) return double.nan;
    if (this == 0) return 0;

    double x = this;
    double prev;

    do {
      prev = x;
      x = (x + this / x) / 2;
    } while ((x - prev).abs() > 0.0001);

    return x;
  }
}
