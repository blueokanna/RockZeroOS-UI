import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

class ParallelStreamService {
  RawDatagramSocket? _udpSocket;
  Socket? _tcpSocket;
  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>.broadcast();
  final Map<int, Uint8List> _udpBuffer = {};
  final Map<int, bool> _receivedPackets = {};
  int _expectedSequence = 0;
  Timer? _timeoutTimer;
  bool _isActive = false;

  Stream<Uint8List> get dataStream => _dataController.stream;
  bool get isActive => _isActive;

  Future<void> initialize({
    required String host,
    required int tcpPort,
    required int udpPort,
    required Map<String, String> headers,
  }) async {
    try {
      _isActive = true;

      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSocket!.listen(_handleUdpData);

      _tcpSocket = await Socket.connect(host, tcpPort);
      _tcpSocket!.listen(
        _handleTcpData,
        onError: (error) {
          debugPrint('[ParallelStream] TCP error: $error');
        },
        onDone: () {
          debugPrint('[ParallelStream] TCP connection closed');
        },
      );

      final request = _buildHttpRequest(host, tcpPort, headers);
      _tcpSocket!.add(request);

      await _requestUdpStream(host, udpPort, headers);

      _startTimeoutChecker();

      debugPrint('[ParallelStream] Initialized - TCP: $tcpPort, UDP: $udpPort');
    } catch (e) {
      debugPrint('[ParallelStream] Initialization error: $e');
      await dispose();
      rethrow;
    }
  }

  Uint8List _buildHttpRequest(
      String host, int port, Map<String, String> headers) {
    final request = StringBuffer();
    request.writeln('GET /stream HTTP/1.1');
    request.writeln('Host: $host:$port');
    headers.forEach((key, value) {
      request.writeln('$key: $value');
    });
    request.writeln('Connection: keep-alive');
    request.writeln('Accept-Ranges: bytes');
    request.writeln();
    return Uint8List.fromList(request.toString().codeUnits);
  }

  Future<void> _requestUdpStream(
      String host, int udpPort, Map<String, String> headers) async {
    final handshake = Uint8List.fromList([
      0x52,
      0x5A,
      0x55,
      0x44,
      0x50,
      ...Uint8List(4)
        ..buffer.asByteData().setUint32(0, _udpSocket!.port, Endian.big),
    ]);

    final address = await InternetAddress.lookup(host);
    _udpSocket!.send(handshake, address.first, udpPort);

    debugPrint(
        '[ParallelStream] UDP handshake sent to $host:$udpPort from port ${_udpSocket!.port}');
  }

  void _handleUdpData(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final datagram = _udpSocket!.receive();
      if (datagram == null) return;

      final data = datagram.data;
      if (data.length < 8) {
        return;
      }

      final sequence = data.buffer.asByteData().getUint32(0, Endian.big);
      final length = data.buffer.asByteData().getUint32(4, Endian.big);
      final payload = Uint8List.sublistView(data, 8);

      if (payload.length != length) {
        debugPrint(
            '[ParallelStream] UDP packet size mismatch: expected $length, got ${payload.length}');
        return;
      }

      _udpBuffer[sequence] = payload;
      _receivedPackets[sequence] = true;

      _deliverSequentialPackets();
    }
  }

  void _handleTcpData(Uint8List data) {
    if (_udpBuffer.isEmpty) {
      _dataController.add(data);
    }
  }

  void _deliverSequentialPackets() {
    while (_udpBuffer.containsKey(_expectedSequence)) {
      final packet = _udpBuffer.remove(_expectedSequence);
      if (packet != null) {
        _dataController.add(packet);
      }
      _expectedSequence++;
    }
  }

  void _startTimeoutChecker() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isActive) {
        timer.cancel();
        return;
      }

      final missingPackets = <int>[];
      for (int i = _expectedSequence; i < _expectedSequence + 100; i++) {
        if (!_receivedPackets.containsKey(i) && !_udpBuffer.containsKey(i)) {
          missingPackets.add(i);
        }
      }

      if (missingPackets.isNotEmpty) {
        _requestRetransmission(missingPackets);
      }
    });
  }

  void _requestRetransmission(List<int> sequences) {
    if (_tcpSocket == null) return;

    final request = Uint8List(4 + sequences.length * 4);
    request.buffer.asByteData().setUint32(0, sequences.length, Endian.big);
    for (int i = 0; i < sequences.length; i++) {
      request.buffer
          .asByteData()
          .setUint32(4 + i * 4, sequences[i], Endian.big);
    }

    _tcpSocket!.add(request);
    debugPrint(
        '[ParallelStream] Requested retransmission of ${sequences.length} packets');
  }

  Future<void> dispose() async {
    _isActive = false;
    _timeoutTimer?.cancel();
    _udpSocket?.close();
    await _tcpSocket?.close();
    await _dataController.close();
    _udpBuffer.clear();
    _receivedPackets.clear();
    debugPrint('[ParallelStream] Disposed');
  }
}

class ParallelStreamFactory {
  static bool isSupported() {
    return !kIsWeb;
  }

  static ParallelStreamService create() {
    return ParallelStreamService();
  }

  static int getOptimalBufferSize() {
    return 20 * 1024 * 1024;
  }

  static int getOptimalChunkSize() {
    return 1400;
  }
}
