// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'dart:math';

import 'package:edwards25519/edwards25519.dart' as ed25519;
import 'package:flutter/foundation.dart';
import 'package:thirds/blake3.dart' as blake3;

class SaeClientCurve25519 {
  static const int GROUP_ID = 19;
  static const int SAE_MAX_PWE_LOOP = 40;
  static const int SAE_PWE_OFFSET_ITERATIONS = 8;

  final Uint8List password;
  final Uint8List _deviceIdSelf32;
  final Uint8List _deviceIdPeer32;

  final Uint8List deviceIdSelf;
  final Uint8List deviceIdPeer;

  ed25519.Point? _pwe;

  ed25519.Scalar? _rand;
  ed25519.Scalar? _mask;
  ed25519.Scalar? _scalar;
  ed25519.Point? _element;

  ed25519.Scalar? _peerScalar;
  ed25519.Point? _peerElement;

  Uint8List? _kck;
  Uint8List? _pmk;
  Uint8List? _pmkid;

  bool _committed = false;
  bool _confirmed = false;

  final int _sendConfirm = 1;

  static Uint8List _normalizeDeviceId(Uint8List input) {
    if (input.length == 32) {
      return Uint8List.fromList(input);
    }
    final hash = blake3.blake3(input, 32);
    return Uint8List.fromList(hash);
  }

  SaeClientCurve25519({
    required this.password,
    required this.deviceIdSelf,
    required this.deviceIdPeer,
  })  : _deviceIdSelf32 = _normalizeDeviceId(deviceIdSelf),
        _deviceIdPeer32 = _normalizeDeviceId(deviceIdPeer);

  factory SaeClientCurve25519.fromStrings({
    required String password,
    required String deviceIdSelf,
    required String deviceIdPeer,
  }) {
    return SaeClientCurve25519(
      password: Uint8List.fromList(utf8.encode(password)),
      deviceIdSelf: Uint8List.fromList(utf8.encode(deviceIdSelf)),
      deviceIdPeer: Uint8List.fromList(utf8.encode(deviceIdPeer)),
    );
  }

  Map<String, dynamic> generateCommit() {
    if (_committed) {
      throw StateError('Already committed');
    }

    _pwe ??= _derivePasswordElement();

    _rand = _generateRandomScalar();
    _mask = _generateRandomScalar();

    _scalar = ed25519.Scalar()..add(_rand!, _mask!);

    final maskNeg = ed25519.Scalar()..negate(_mask!);
    _element = ed25519.Point.zero()..scalarMult(maskNeg, _pwe!);

    _committed = true;

    return {
      'group_id': GROUP_ID,
      'scalar': base64Encode(_scalarToBytes(_scalar!)),
      'element': base64Encode(_pointToBytes(_element!)),
    };
  }

  void processCommit(Map<String, dynamic> peerCommit) {
    if (!_committed) {
      throw StateError('Must generate own commit first');
    }

    final groupId = peerCommit['group_id'] as int;
    if (groupId != GROUP_ID) {
      throw ArgumentError(
          'Unsupported group ID: $groupId (expected $GROUP_ID)');
    }

    final peerScalarBytes = base64Decode(peerCommit['scalar'] as String);
    _peerScalar = _bytesToScalar(peerScalarBytes);

    final peerElementBytes = base64Decode(peerCommit['element'] as String);
    _peerElement = _bytesToPoint(peerElementBytes);

    if (_peerScalar!.equal(_scalar!) == 1) {
      throw StateError('Peer scalar equals own scalar');
    }

    if (_peerElement!.equal(_element!) == 1) {
      throw StateError('Peer element equals own element');
    }

    final sharedSecret = _computeSharedSecret();
    _deriveKeys(sharedSecret);
    _pmkid = _computePmkid();
  }

  Map<String, dynamic> generateConfirm() {
    if (!_committed || _kck == null) {
      throw StateError('Must process peer commit first');
    }

    final confirm = _computeConfirm(_sendConfirm);

    return {
      'send_confirm': _sendConfirm,
      'confirm': base64Encode(confirm),
    };
  }

  void verifyConfirm(Map<String, dynamic> peerConfirm) {
    if (_kck == null) {
      throw StateError('Must process peer commit first');
    }

    final sendConfirm = peerConfirm['send_confirm'] as int;
    final peerConfirmBytes = base64Decode(peerConfirm['confirm'] as String);

    final expectedConfirm = _computePeerConfirm(sendConfirm);

    if (!_constantTimeCompare(peerConfirmBytes, expectedConfirm)) {
      throw StateError('Confirm verification failed');
    }

    _confirmed = true;
  }

  Uint8List getPmk() {
    if (_pmk == null) {
      throw StateError('PMK not derived yet');
    }
    return Uint8List.fromList(_pmk!);
  }

  Uint8List getKck() {
    if (_kck == null) {
      throw StateError('KCK not derived yet');
    }
    return Uint8List.fromList(_kck!);
  }

  Uint8List getPmkid() {
    if (_pmkid == null) {
      throw StateError('PMKID not derived yet');
    }
    return Uint8List.fromList(_pmkid!);
  }

  bool isAuthenticated() => _confirmed;

  bool isCommitted() => _committed;

  ed25519.Point _derivePasswordElement() {
    final List<int> id1;
    final List<int> id2;
    if (_compareBytes(_deviceIdSelf32, _deviceIdPeer32) < 0) {
      id1 = _deviceIdSelf32;
      id2 = _deviceIdPeer32;
    } else {
      id1 = _deviceIdPeer32;
      id2 = _deviceIdSelf32;
    }

    for (int counter = 1; counter <= SAE_MAX_PWE_LOOP; counter++) {
      final initialHash = _blake3Hash([
        ...id1,
        ...id2,
        ...password,
        ...Uint8List(4)
          ..buffer.asByteData().setInt32(0, counter, Endian.little),
      ]);

      for (int offset = 0; offset < SAE_PWE_OFFSET_ITERATIONS; offset++) {
        Uint8List seed;
        if (offset == 0) {
          seed = initialHash;
        } else {
          seed = _blake3Hash([
            ...initialHash,
            ...Uint8List(4)
              ..buffer.asByteData().setInt32(0, offset, Endian.little),
          ]);
        }

        final point = _trySeedToPoint(seed);
        if (point != null && _isValidPwe(point)) {
          return point;
        }
      }
    }

    throw StateError('Failed to derive PWE after maximum iterations');
  }

  Uint8List _blake3Hash(List<int> input) {
    final result = blake3.blake3(input, 32);
    return Uint8List.fromList(result);
  }

  ed25519.Point? _trySeedToPoint(Uint8List seed) {
    if (seed.length < 32) return null;

    try {
      final yBytes = Uint8List.fromList(seed.sublist(0, 32));
      final point = ed25519.Point.zero();
      point.setBytes(yBytes);
      return point;
    } catch (_) {
      return null;
    }
  }

  bool _isValidPwe(ed25519.Point point) {
    if (point.equal(ed25519.Point.identity) == 1) {
      return false;
    }

    if (!ed25519.checkOnCurve([point])) {
      return false;
    }

    final lMinus1Scalar = ed25519.Scalar();
    lMinus1Scalar.setCanonicalBytes(ed25519.Scalar.scalarMinusOneBytes);

    final lMinus1TimesP = ed25519.Point.zero();
    lMinus1TimesP.scalarMult(lMinus1Scalar, point);

    final lTimesP = ed25519.Point.zero();
    lTimesP.add(lMinus1TimesP, point);

    return lTimesP.equal(ed25519.Point.identity) == 1;
  }

  ed25519.Scalar _generateRandomScalar() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    final scalar = ed25519.Scalar();
    scalar.setUniformBytes(Uint8List.fromList([...bytes, ...bytes]));
    return scalar;
  }

  Uint8List _computeSharedSecret() {
    final peerScalarPwe = ed25519.Point.zero();
    peerScalarPwe.scalarMult(_peerScalar!, _pwe!);

    final temp = ed25519.Point.zero();
    temp.add(_peerElement!, peerScalarPwe);

    final sharedSecret = ed25519.Point.zero();
    sharedSecret.scalarMult(_rand!, temp);

    return Uint8List.fromList(sharedSecret.Bytes());
  }

  void _deriveKeys(Uint8List sharedSecret) {
    final zeroKey = Uint8List(32);
    final keyseed = _blake3KeyedHash(zeroKey, sharedSecret);

    final value = ed25519.Scalar()..add(_scalar!, _peerScalar!);
    final valueBytes = _scalarToBytes(value);

    final info =
        Uint8List.fromList([...utf8.encode('SAE KCK and PMK'), ...valueBytes]);

    final kckPmk = _hkdfBlake3Expand(keyseed, info, 64);

    _kck = Uint8List.fromList(kckPmk.sublist(0, 32));
    _pmk = Uint8List.fromList(kckPmk.sublist(32, 64));
  }

  Uint8List _computeConfirm(int sendConfirm) {
    final data = Uint8List.fromList([
      sendConfirm & 0xFF,
      (sendConfirm >> 8) & 0xFF,
      ..._scalarToBytes(_scalar!),
      ..._scalarToBytes(_peerScalar!),
      ..._pointToBytes(_element!),
      ..._pointToBytes(_peerElement!),
    ]);

    return _blake3KeyedHash(_kck!, data);
  }

  Uint8List _computePeerConfirm(int sendConfirm) {
    final data = Uint8List.fromList([
      sendConfirm & 0xFF,
      (sendConfirm >> 8) & 0xFF,
      ..._scalarToBytes(_peerScalar!),
      ..._scalarToBytes(_scalar!),
      ..._pointToBytes(_peerElement!),
      ..._pointToBytes(_element!),
    ]);

    return _blake3KeyedHash(_kck!, data);
  }

  Uint8List _computePmkid() {
    final data = Uint8List.fromList([
      ...utf8.encode('PMK Name'),
      ..._deviceIdPeer32,
      ..._deviceIdSelf32,
    ]);

    final fullHash = _blake3KeyedHash(_pmk!, data);
    return Uint8List.fromList(fullHash.sublist(0, 16));
  }

  Uint8List _blake3KeyedHash(Uint8List key, Uint8List message) {
    Uint8List normalizedKey;
    if (key.length == 32) {
      normalizedKey = key;
    } else if (key.length < 32) {
      normalizedKey = Uint8List(32);
      normalizedKey.setRange(0, key.length, key);
    } else {
      final hash = blake3.blake3(key, 32);
      normalizedKey = Uint8List.fromList(hash);
    }

    final input = Uint8List.fromList([...normalizedKey, ...message]);
    final hash = blake3.blake3(input, 32);
    return Uint8List.fromList(hash);
  }

  Uint8List _hkdfBlake3Expand(Uint8List prk, Uint8List info, int length) {
    final output = <int>[];
    var t = Uint8List(0);
    var counter = 1;

    while (output.length < length) {
      final hmacInput = Uint8List.fromList([...t, ...info, counter]);
      t = _blake3KeyedHash(prk, hmacInput);
      output.addAll(t);
      counter++;
    }

    return Uint8List.fromList(output.sublist(0, length));
  }

  Uint8List _scalarToBytes(ed25519.Scalar scalar) {
    return scalar.Bytes();
  }

  ed25519.Scalar _bytesToScalar(Uint8List bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('Scalar must be 32 bytes, got ${bytes.length}');
    }
    final scalar = ed25519.Scalar();
    scalar.setCanonicalBytes(bytes);
    return scalar;
  }

  Uint8List _pointToBytes(ed25519.Point point) {
    return Uint8List.fromList(point.Bytes());
  }

  ed25519.Point _bytesToPoint(Uint8List bytes) {
    Uint8List elementBytes;

    if (bytes.length == 32) {
      elementBytes = bytes;
    } else if (bytes.length == 33) {
      elementBytes = Uint8List.fromList(bytes.sublist(1, 33));
    } else {
      throw ArgumentError(
          'Invalid element length: ${bytes.length} (expected 32 or 33)');
    }

    final point = ed25519.Point.zero();
    point.setBytes(elementBytes);
    return point;
  }

  bool _constantTimeCompare(Uint8List a, Uint8List b) {
    return ed25519.constantTimeCompare(a, b) == 1;
  }

  int _compareBytes(List<int> a, List<int> b) {
    final minLen = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < minLen; i++) {
      if (a[i] < b[i]) return -1;
      if (a[i] > b[i]) return 1;
    }
    return a.length.compareTo(b.length);
  }
}

class SaeCommitData {
  final int groupId;
  final Uint8List scalar;
  final Uint8List element;

  SaeCommitData({
    required this.groupId,
    required this.scalar,
    required this.element,
  });

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'scalar': base64Encode(scalar),
        'element': base64Encode(element),
      };

  factory SaeCommitData.fromJson(Map<String, dynamic> json) {
    return SaeCommitData(
      groupId: json['group_id'] as int,
      scalar: base64Decode(json['scalar'] as String),
      element: base64Decode(json['element'] as String),
    );
  }
}

class SaeConfirmData {
  final int sendConfirm;
  final Uint8List confirm;

  SaeConfirmData({
    required this.sendConfirm,
    required this.confirm,
  });

  Map<String, dynamic> toJson() => {
        'send_confirm': sendConfirm,
        'confirm': base64Encode(confirm),
      };

  factory SaeConfirmData.fromJson(Map<String, dynamic> json) {
    return SaeConfirmData(
      sendConfirm: json['send_confirm'] as int,
      confirm: base64Decode(json['confirm'] as String),
    );
  }
}
