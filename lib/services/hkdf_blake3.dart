import 'dart:convert';
import 'dart:typed_data';

import 'package:thirds/blake3.dart' as blake3;

class HkdfBlake3 {
  final Uint8List _prk;

  HkdfBlake3({
    required Uint8List ikm,
    Uint8List? salt,
  }) : _prk = _extract(salt ?? Uint8List(32), ikm);

  factory HkdfBlake3.withSessionSalt(String sessionId, Uint8List pmk) {
    final saltInput = 'hls-session-salt:$sessionId';
    final saltHash =
        Uint8List.fromList(blake3.blake3(utf8.encode(saltInput), 32));
    return HkdfBlake3(ikm: pmk, salt: saltHash);
  }

  Uint8List expand(Uint8List info, int length) {
    final output = <int>[];
    var t = Uint8List(0);
    var counter = 1;

    while (output.length < length) {
      final hmacInput = Uint8List.fromList([...t, ...info, counter]);
      t = _blake3KeyedHash(_prk, hmacInput);
      output.addAll(t);
      counter++;
    }

    return Uint8List.fromList(output.sublist(0, length));
  }

  static Uint8List _extract(Uint8List salt, Uint8List ikm) {
    return _blake3KeyedHash(salt, ikm);
  }

  static Uint8List _blake3KeyedHash(Uint8List key, Uint8List message) {
    Uint8List normalizedKey;
    if (key.length == 32) {
      normalizedKey = key;
    } else if (key.length < 32) {
      normalizedKey = Uint8List(32);
      normalizedKey.setRange(0, key.length, key);
    } else {
      normalizedKey = Uint8List.fromList(blake3.blake3(key, 32));
    }

    final input = Uint8List.fromList([...normalizedKey, ...message]);
    return Uint8List.fromList(blake3.blake3(input, 32));
  }
}
