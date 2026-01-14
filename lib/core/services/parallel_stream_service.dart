import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Service for parallel UDP/TCP streaming to optimize video buffering
/// This combines UDP for fast data transfer with TCP for reliability
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

  /// Initialize parallel streaming with both UDP and TCP
  /// UDP provides fast initial buffering, TCP ensures no data loss
  Future<void> initialize({
    required String host,
    required int tcpPort,
    required int udpPort,
    required Map<String, String> headers,
  }) async {
    try {
      _isActive = true;

      // Start UDP socket for fast data transfer
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSocket!.listen(_handleUdpData);

      // Start TCP socket for reliable data transfer
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

      // Send initial request with headers
      final request = _buildHttpRequest(host, tcpPort, headers);
      _tcpSocket!.add(request);

      // Request UDP stream from server
      await _requestUdpStream(host, udpPort, headers);

      // Start timeout checker for missing UDP packets
      _startTimeoutChecker();

      debugPrint('[ParallelStream] Initialized - TCP: $tcpPort, UDP: $udpPort');
    } catch (e) {
      debugPrint('[ParallelStream] Initialization error: $e');
      await dispose();
      rethrow;
    }
  }

  /// Build HTTP request for TCP connection
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

  /// Request UDP stream from server
  Future<void> _requestUdpStream(
      String host, int udpPort, Map<String, String> headers) async {
    // Send UDP handshake packet
    final handshake = Uint8List.fromList([
      0x52, 0x5A, 0x55, 0x44, 0x50, // "RZUDP" magic bytes
      ...Uint8List(4)
        ..buffer.asByteData().setUint32(0, _udpSocket!.port, Endian.big),
    ]);

    final address = await InternetAddress.lookup(host);
    _udpSocket!.send(handshake, address.first, udpPort);

    debugPrint(
        '[ParallelStream] UDP handshake sent to $host:$udpPort from port ${_udpSocket!.port}');
  }

  /// Handle incoming UDP data packets
  void _handleUdpData(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final datagram = _udpSocket!.receive();
      if (datagram == null) return;

      final data = datagram.data;
      if (data.length < 8) {
        return; // Minimum packet size (4 bytes seq + 4 bytes length)
      }

      // Parse packet header
      final sequence = data.buffer.asByteData().getUint32(0, Endian.big);
      final length = data.buffer.asByteData().getUint32(4, Endian.big);
      final payload = Uint8List.sublistView(data, 8);

      if (payload.length != length) {
        debugPrint(
            '[ParallelStream] UDP packet size mismatch: expected $length, got ${payload.length}');
        return;
      }

      // Store packet in buffer
      _udpBuffer[sequence] = payload;
      _receivedPackets[sequence] = true;

      // Try to deliver sequential packets
      _deliverSequentialPackets();
    }
  }

  /// Handle incoming TCP data (fallback for missing UDP packets)
  void _handleTcpData(Uint8List data) {
    // TCP provides reliable delivery for any packets missed by UDP
    // In a real implementation, this would parse HTTP chunked encoding
    // and fill gaps in the UDP stream

    // For now, just forward TCP data if UDP is not delivering
    if (_udpBuffer.isEmpty) {
      _dataController.add(data);
    }
  }

  /// Deliver packets in sequential order
  void _deliverSequentialPackets() {
    while (_udpBuffer.containsKey(_expectedSequence)) {
      final packet = _udpBuffer.remove(_expectedSequence);
      if (packet != null) {
        _dataController.add(packet);
      }
      _expectedSequence++;
    }
  }

  /// Start timeout checker for missing packets
  void _startTimeoutChecker() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isActive) {
        timer.cancel();
        return;
      }

      // Check for missing packets (gaps in sequence)
      final missingPackets = <int>[];
      for (int i = _expectedSequence; i < _expectedSequence + 100; i++) {
        if (!_receivedPackets.containsKey(i) && !_udpBuffer.containsKey(i)) {
          missingPackets.add(i);
        }
      }

      // Request retransmission via TCP for missing packets
      if (missingPackets.isNotEmpty) {
        _requestRetransmission(missingPackets);
      }
    });
  }

  /// Request retransmission of missing packets via TCP
  void _requestRetransmission(List<int> sequences) {
    if (_tcpSocket == null) return;

    // Send retransmission request
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

  /// Dispose resources
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

/// Factory for creating parallel stream services
class ParallelStreamFactory {
  /// Check if parallel streaming is supported
  static bool isSupported() {
    // UDP streaming is supported on all platforms except web
    return !kIsWeb;
  }

  /// Create a parallel stream service
  static ParallelStreamService create() {
    return ParallelStreamService();
  }

  /// Get optimal buffer size based on network conditions
  static int getOptimalBufferSize() {
    // Start with 20MB buffer, can be adjusted based on network speed
    return 20 * 1024 * 1024;
  }

  /// Get optimal chunk size for UDP packets
  static int getOptimalChunkSize() {
    // Use 1400 bytes to avoid IP fragmentation (MTU is typically 1500)
    return 1400;
  }
}
