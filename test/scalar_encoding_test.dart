import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:edwards25519/edwards25519.dart' as ed25519;
import 'package:convert/convert.dart';

void main() {
  group('Scalar 编码测试', () {
    test('测试 setCanonicalBytes vs from_bytes_mod_order', () {
      // 测试规范字节（小于 l）
      final canonicalBytes = Uint8List.fromList([
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);

      final scalar1 = ed25519.Scalar();
      scalar1.setCanonicalBytes(canonicalBytes);
      print('Canonical scalar: ${hex.encode(scalar1.Bytes())}');

      // 测试非规范字节（需要 mod l）
      // l = 2^252 + 27742317777372353535851937790883648493
      // 创建一个接近 l 的值
      final largeBytes = Uint8List.fromList([
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0x7F,
      ]);

      print('Input bytes: ${hex.encode(largeBytes)}');

      // 尝试 setCanonicalBytes
      try {
        final scalar2 = ed25519.Scalar();
        scalar2.setCanonicalBytes(largeBytes);
        print('setCanonicalBytes result: ${hex.encode(scalar2.Bytes())}');
      } catch (e) {
        print('setCanonicalBytes failed: $e');
      }

      // 使用 setUniformBytes（需要64字节）
      final extendedBytes = Uint8List(64);
      extendedBytes.setRange(0, 32, largeBytes);
      final scalar3 = ed25519.Scalar();
      scalar3.setUniformBytes(extendedBytes);
      print('setUniformBytes result: ${hex.encode(scalar3.Bytes())}');

      // 测试 Rust 发来的实际 scalar 格式
      // Rust: scalar.to_bytes() 返回规范化的字节
      // Rust 中 Scalar::to_bytes() 总是返回规范字节
      print('\n--- Rust 兼容性测试 ---');

      // 模拟 Rust Scalar::from_bytes_mod_order 的结果
      // 由于 Rust 的 scalar.to_bytes() 已经是规范的
      // 所以 setCanonicalBytes 应该可以工作
    });

    test('验证 Scalar 往返编码', () {
      // 生成一个随机 scalar
      final scalar = ed25519.Scalar();
      final uniformInput = Uint8List(64);
      for (int i = 0; i < 64; i++) {
        uniformInput[i] = i * 7 % 256;
      }
      scalar.setUniformBytes(uniformInput);

      // 获取字节
      final bytes = scalar.Bytes();
      print('Original scalar bytes: ${hex.encode(bytes)}');

      // 验证 isReduced
      final isReduced = ed25519.Scalar.isReduced(bytes);
      print('Is reduced: $isReduced');
      expect(isReduced, true,
          reason: 'Scalar.Bytes() should always return reduced bytes');

      // 从字节恢复
      final scalar2 = ed25519.Scalar();
      scalar2.setCanonicalBytes(bytes);

      final bytes2 = scalar2.Bytes();
      print('Recovered scalar bytes: ${hex.encode(bytes2)}');

      expect(bytes, equals(bytes2),
          reason: 'Round-trip should preserve scalar');
    });

    test('测试 scalar 加法结果的编码', () {
      // 创建两个 scalar
      final s1 = ed25519.Scalar();
      s1.setCanonicalBytes(Uint8List.fromList([
        10,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]));

      final s2 = ed25519.Scalar();
      s2.setCanonicalBytes(Uint8List.fromList([
        20,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]));

      final sum = ed25519.Scalar();
      sum.add(s1, s2);

      final sumBytes = sum.Bytes();
      print('Sum scalar bytes: ${hex.encode(sumBytes)}');

      // 验证结果是规范的
      expect(ed25519.Scalar.isReduced(sumBytes), true);

      // 从字节恢复
      final sumRecovered = ed25519.Scalar();
      sumRecovered.setCanonicalBytes(sumBytes);

      expect(sum.equal(sumRecovered), 1);
    });
  });
}
