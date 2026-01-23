import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:edwards25519/edwards25519.dart' as ed25519;
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:thirds/blake3.dart' as blake3;

/// 详细的 SAE 共享密钥计算测试
void main() {
  group('SAE 共享密钥计算详细测试', () {
    test('验证共享密钥计算对称性', () {
      // 1. 设置共同参数
      const password = 'test_password';
      final passwordBytes = Uint8List.fromList(utf8.encode(password));

      final clientId =
          Uint8List.fromList(blake3.blake3(utf8.encode('client'), 32));
      final serverId =
          Uint8List.fromList(blake3.blake3(utf8.encode('server'), 32));

      // 2. 派生 PWE（双方应该相同）
      final pweClient =
          _derivePasswordElement(passwordBytes, clientId, serverId);
      final pweServer =
          _derivePasswordElement(passwordBytes, serverId, clientId);

      print('Client PWE: ${base64Encode(pweClient.Bytes())}');
      print('Server PWE: ${base64Encode(pweServer.Bytes())}');
      expect(pweClient.equal(pweServer), 1, reason: 'PWE should be symmetric');

      // 3. 客户端生成 commit
      final clientRand = _generateRandomScalar();
      final clientMask = _generateRandomScalar();
      final clientScalar = ed25519.Scalar()..add(clientRand, clientMask);
      final maskNegClient = ed25519.Scalar()..negate(clientMask);
      final clientElement = ed25519.Point.zero()
        ..scalarMult(maskNegClient, pweClient);

      print('\nClient:');
      print('  rand: ${base64Encode(clientRand.Bytes())}');
      print('  mask: ${base64Encode(clientMask.Bytes())}');
      print('  scalar: ${base64Encode(clientScalar.Bytes())}');
      print('  element: ${base64Encode(clientElement.Bytes())}');

      // 4. 服务器生成 commit
      final serverRand = _generateRandomScalar();
      final serverMask = _generateRandomScalar();
      final serverScalar = ed25519.Scalar()..add(serverRand, serverMask);
      final maskNegServer = ed25519.Scalar()..negate(serverMask);
      final serverElement = ed25519.Point.zero()
        ..scalarMult(maskNegServer, pweServer);

      print('\nServer:');
      print('  rand: ${base64Encode(serverRand.Bytes())}');
      print('  mask: ${base64Encode(serverMask.Bytes())}');
      print('  scalar: ${base64Encode(serverScalar.Bytes())}');
      print('  element: ${base64Encode(serverElement.Bytes())}');

      // 5. 客户端计算共享密钥: K = rand_client * (element_server + scalar_server * PWE)
      final serverScalarPwe = ed25519.Point.zero()
        ..scalarMult(serverScalar, pweClient);
      final tempClient = ed25519.Point.zero()
        ..add(serverElement, serverScalarPwe);
      final sharedSecretClient = ed25519.Point.zero()
        ..scalarMult(clientRand, tempClient);

      print('\nClient shared secret calculation:');
      print('  scalar_server * PWE: ${base64Encode(serverScalarPwe.Bytes())}');
      print(
          '  element_server + scalar_server * PWE: ${base64Encode(tempClient.Bytes())}');
      print(
          '  K = rand_client * temp: ${base64Encode(sharedSecretClient.Bytes())}');

      // 6. 服务器计算共享密钥: K = rand_server * (element_client + scalar_client * PWE)
      final clientScalarPwe = ed25519.Point.zero()
        ..scalarMult(clientScalar, pweServer);
      final tempServer = ed25519.Point.zero()
        ..add(clientElement, clientScalarPwe);
      final sharedSecretServer = ed25519.Point.zero()
        ..scalarMult(serverRand, tempServer);

      print('\nServer shared secret calculation:');
      print('  scalar_client * PWE: ${base64Encode(clientScalarPwe.Bytes())}');
      print(
          '  element_client + scalar_client * PWE: ${base64Encode(tempServer.Bytes())}');
      print(
          '  K = rand_server * temp: ${base64Encode(sharedSecretServer.Bytes())}');

      // 7. 验证中间计算
      // element_client + scalar_client * PWE = -mask_client * PWE + (rand_client + mask_client) * PWE
      //                                      = -mask_client * PWE + rand_client * PWE + mask_client * PWE
      //                                      = rand_client * PWE
      final expectedClientContribution = ed25519.Point.zero()
        ..scalarMult(clientRand, pweClient);
      print('\nVerification:');
      print(
          '  Expected (rand_client * PWE): ${base64Encode(expectedClientContribution.Bytes())}');
      print(
          '  Actual (element_client + scalar_client * PWE): ${base64Encode(tempServer.Bytes())}');

      final matchClient = expectedClientContribution.equal(tempServer) == 1;
      print('  Match: $matchClient');

      final expectedServerContribution = ed25519.Point.zero()
        ..scalarMult(serverRand, pweServer);
      print(
          '  Expected (rand_server * PWE): ${base64Encode(expectedServerContribution.Bytes())}');
      print(
          '  Actual (element_server + scalar_server * PWE): ${base64Encode(tempClient.Bytes())}');

      final matchServer = expectedServerContribution.equal(tempClient) == 1;
      print('  Match: $matchServer');

      // 8. 验证共享密钥
      // K_client = rand_client * rand_server * PWE
      // K_server = rand_server * rand_client * PWE
      print('\nFinal shared secrets:');
      print('  Client: ${base64Encode(sharedSecretClient.Bytes())}');
      print('  Server: ${base64Encode(sharedSecretServer.Bytes())}');

      expect(matchClient, true, reason: 'Client contribution should match');
      expect(matchServer, true, reason: 'Server contribution should match');
      expect(sharedSecretClient.equal(sharedSecretServer), 1,
          reason: 'Shared secrets should match');
    });

    test('验证 scalar 乘法可交换性', () {
      // 生成随机 scalar
      final a = _generateRandomScalar();
      final b = _generateRandomScalar();

      // 生成一个点
      final pwe = ed25519.Point.zero();
      pwe.setBytes(Uint8List.fromList([
        0x12,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x80,
      ]));

      // a * (b * P)
      final bP = ed25519.Point.zero()..scalarMult(b, pwe);
      final abP = ed25519.Point.zero()..scalarMult(a, bP);

      // b * (a * P)
      final aP = ed25519.Point.zero()..scalarMult(a, pwe);
      final baP = ed25519.Point.zero()..scalarMult(b, aP);

      // (a * b) * P
      final ab = ed25519.Scalar()..multiply(a, b);
      final abP2 = ed25519.Point.zero()..scalarMult(ab, pwe);

      print('a * (b * P): ${base64Encode(abP.Bytes())}');
      print('b * (a * P): ${base64Encode(baP.Bytes())}');
      print('(a * b) * P: ${base64Encode(abP2.Bytes())}');

      expect(abP.equal(baP), 1,
          reason: 'Scalar multiplication should be commutative');
      expect(abP.equal(abP2), 1, reason: 'Associativity should hold');
    });
  });
}

/// 生成随机标量
ed25519.Scalar _generateRandomScalar() {
  final random = DateTime.now().microsecondsSinceEpoch;
  final bytes = Uint8List(64);
  for (int i = 0; i < 64; i++) {
    bytes[i] = ((random + i) * 17 + i * 23) % 256;
  }
  final scalar = ed25519.Scalar();
  scalar.setUniformBytes(bytes);
  return scalar;
}

/// 派生密码元素
ed25519.Point _derivePasswordElement(
    Uint8List password, Uint8List id1, Uint8List id2) {
  // 确保顺序一致
  final List<int> sortedId1;
  final List<int> sortedId2;
  if (_compareBytes(id1, id2) < 0) {
    sortedId1 = id1;
    sortedId2 = id2;
  } else {
    sortedId1 = id2;
    sortedId2 = id1;
  }

  for (int counter = 1; counter <= 40; counter++) {
    final counterBytes = Uint8List(4)
      ..buffer.asByteData().setInt32(0, counter, Endian.little);
    final hash = blake3
        .blake3([...sortedId1, ...sortedId2, ...password, ...counterBytes], 32);

    for (int offset = 0; offset < 8; offset++) {
      Uint8List seed;
      if (offset == 0) {
        seed = Uint8List.fromList(hash);
      } else {
        final offsetBytes = Uint8List(4)
          ..buffer.asByteData().setInt32(0, offset, Endian.little);
        seed = Uint8List.fromList(blake3.blake3([...hash, ...offsetBytes], 32));
      }

      try {
        final point = ed25519.Point.zero();
        point.setBytes(seed);

        // 验证点有效
        if (point.equal(ed25519.Point.identity) != 1 &&
            ed25519.checkOnCurve([point])) {
          final cofactorResult = ed25519.Point.zero();
          cofactorResult.multByCofactor(point);
          if (cofactorResult.equal(ed25519.Point.identity) != 1) {
            return point;
          }
        }
      } catch (_) {
        continue;
      }
    }
  }

  throw StateError('Failed to derive PWE');
}

int _compareBytes(List<int> a, List<int> b) {
  final minLen = a.length < b.length ? a.length : b.length;
  for (int i = 0; i < minLen; i++) {
    if (a[i] < b[i]) return -1;
    if (a[i] > b[i]) return 1;
  }
  return a.length.compareTo(b.length);
}
