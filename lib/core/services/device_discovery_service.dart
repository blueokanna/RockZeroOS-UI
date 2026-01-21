import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:network_info_plus/network_info_plus.dart';

// Discovered device model
class DiscoveredDevice {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String version;
  final bool isSecure;
  final DateTime discoveredAt;

  DiscoveredDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.version,
    required this.isSecure,
    required this.discoveredAt,
  });

  String get baseUrl => isSecure ? 'https://$ip:$port' : 'http://$ip:$port';

  factory DiscoveredDevice.fromJson(Map<String, dynamic> json, String ip) {
    return DiscoveredDevice(
      id: json['id'] ?? ip,
      name: json['name'] ?? 'RockZero Device',
      ip: ip,
      port: json['port'] ?? 8080,
      version: json['version'] ?? 'unknown',
      isSecure: json['tls'] ?? false,
      discoveredAt: DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredDevice &&
          runtimeType == other.runtimeType &&
          ip == other.ip &&
          port == other.port;

  @override
  int get hashCode => ip.hashCode ^ port.hashCode;
}

// Device discovery state
class DeviceDiscoveryState {
  final List<DiscoveredDevice> devices;
  final bool isScanning;
  final String? error;
  final String? localIp;

  const DeviceDiscoveryState({
    this.devices = const [],
    this.isScanning = false,
    this.error,
    this.localIp,
  });

  DeviceDiscoveryState copyWith({
    List<DiscoveredDevice>? devices,
    bool? isScanning,
    String? error,
    String? localIp,
  }) {
    return DeviceDiscoveryState(
      devices: devices ?? this.devices,
      isScanning: isScanning ?? this.isScanning,
      error: error,
      localIp: localIp ?? this.localIp,
    );
  }
}

// Device discovery service provider
final deviceDiscoveryServiceProvider = Provider<DeviceDiscoveryService>((ref) {
  return DeviceDiscoveryService(ref);
});

// Device discovery state provider (Riverpod 3.x Notifier API)
final deviceDiscoveryStateProvider =
    NotifierProvider<DeviceDiscoveryNotifier, DeviceDiscoveryState>(
        DeviceDiscoveryNotifier.new);

// Connected device provider
final connectedDeviceProvider =
    NotifierProvider<ConnectedDeviceNotifier, DiscoveredDevice?>(
        ConnectedDeviceNotifier.new);

class ConnectedDeviceNotifier extends Notifier<DiscoveredDevice?> {
  @override
  DiscoveredDevice? build() => null;

  void setDevice(DiscoveredDevice? device) {
    state = device;
  }
}

class DeviceDiscoveryNotifier extends Notifier<DeviceDiscoveryState> {
  @override
  DeviceDiscoveryState build() => const DeviceDiscoveryState();

  void setScanning(bool scanning) {
    state = state.copyWith(isScanning: scanning);
  }

  void setLocalIp(String? ip) {
    state = state.copyWith(localIp: ip);
  }

  void addDevice(DiscoveredDevice device) {
    final devices = List<DiscoveredDevice>.from(state.devices);
    final existingIndex = devices.indexWhere((d) => d.ip == device.ip);
    if (existingIndex >= 0) {
      devices[existingIndex] = device;
    } else {
      devices.add(device);
    }
    state = state.copyWith(devices: devices);
  }

  void clearDevices() {
    state = state.copyWith(devices: []);
  }

  void setError(String? error) {
    state = state.copyWith(error: error);
  }
}

class DeviceDiscoveryService {
  final Ref _ref;
  final NetworkInfo _networkInfo = NetworkInfo();
  Timer? _scanTimer;
  Timer? _ipMonitorTimer;
  RawDatagramSocket? _udpSocket;
  String? _lastKnownIp;

  static const int _discoveryPort = 8444;
  static const int _defaultServicePort = 8080;
  static const Duration _scanInterval = Duration(seconds: 5);
  static const Duration _scanTimeout = Duration(seconds: 3);
  static const Duration _ipCheckInterval = Duration(seconds: 10);

  DeviceDiscoveryService(this._ref);

  DeviceDiscoveryNotifier get _notifier =>
      _ref.read(deviceDiscoveryStateProvider.notifier);

  /// Get the configured service port from settings
  int get _servicePort {
    try {
      final box = Hive.box('settings');
      return box.get('defaultPort', defaultValue: _defaultServicePort) as int;
    } catch (_) {
      return _defaultServicePort;
    }
  }

  /// Set the default service port
  void setDefaultPort(int port) {
    try {
      final box = Hive.box('settings');
      box.put('defaultPort', port);
    } catch (_) {}
  }

  Future<void> startDiscovery() async {
    await _getLocalIp();
    _lastKnownIp = _ref.read(deviceDiscoveryStateProvider).localIp;
    await _startUdpDiscovery();
    _startPeriodicScan();
    _startIpMonitoring();
  }

  /// Periodically monitor IP changes and trigger rescan if IP changes
  void _startIpMonitoring() {
    _ipMonitorTimer?.cancel();
    _ipMonitorTimer = Timer.periodic(_ipCheckInterval, (_) async {
      await _checkIpChange();
    });
  }

  Future<void> _checkIpChange() async {
    try {
      String? currentIp;
      try {
        currentIp = await _networkInfo.getWifiIP();
      } catch (_) {
        // Fallback to interface enumeration
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLinkLocal: false,
        );
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            if (!addr.isLoopback) {
              currentIp = addr.address;
              break;
            }
          }
          if (currentIp != null) break;
        }
      }

      if (currentIp != null && currentIp != _lastKnownIp) {
        _lastKnownIp = currentIp;
        _notifier.setLocalIp(currentIp);
        // IP changed, clear old devices and rescan
        _notifier.clearDevices();
        await scanNetwork();
      }
    } catch (_) {}
  }

  void stopDiscovery() {
    _scanTimer?.cancel();
    _ipMonitorTimer?.cancel();
    _udpSocket?.close();
  }

  Future<void> _getLocalIp() async {
    try {
      final wifiIP = await _networkInfo.getWifiIP();
      _notifier.setLocalIp(wifiIP);
    } catch (e) {
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLinkLocal: false,
        );
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            if (!addr.isLoopback) {
              _notifier.setLocalIp(addr.address);
              return;
            }
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _startUdpDiscovery() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );

      _udpSocket!.broadcastEnabled = true;

      _udpSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) {
            _handleDiscoveryResponse(datagram);
          }
        }
      });
    } catch (e) {
      _notifier.setError('Failed to start UDP discovery: $e');
    }
  }

  void _handleDiscoveryResponse(Datagram datagram) {
    try {
      final data = utf8.decode(datagram.data);
      final json = jsonDecode(data) as Map<String, dynamic>;

      if (json['service'] == 'rockzero') {
        final device = DiscoveredDevice.fromJson(
          json,
          datagram.address.address,
        );
        _notifier.addDevice(device);
      }
    } catch (_) {}
  }

  void _startPeriodicScan() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(_scanInterval, (_) => scanNetwork());
    scanNetwork();
  }

  Future<void> scanNetwork() async {
    _notifier.setScanning(true);
    _notifier.setError(null);

    try {
      await _sendBroadcast();
      await _scanSubnet();
    } catch (e) {
      _notifier.setError('Scan failed: $e');
    } finally {
      _notifier.setScanning(false);
    }
  }

  Future<void> _sendBroadcast() async {
    if (_udpSocket == null) return;

    final message = jsonEncode({
      'action': 'discover',
      'client': 'rockzero-flutter',
    });

    try {
      _udpSocket!.send(
        utf8.encode(message),
        InternetAddress('255.255.255.255'),
        _discoveryPort,
      );
    } catch (_) {}
  }

  Future<void> _scanSubnet() async {
    final localIp = _ref.read(deviceDiscoveryStateProvider).localIp;
    if (localIp == null) return;

    final parts = localIp.split('.');
    if (parts.length != 4) return;

    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
    final futures = <Future>[];

    for (var i = 1; i <= 254; i++) {
      final ip = '$subnet.$i';
      futures.add(_checkDevice(ip));
    }

    await Future.wait(futures).timeout(_scanTimeout, onTimeout: () => []);
  }

  Future<void> _checkDevice(String ip) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 500)
        ..badCertificateCallback = (cert, host, port) => true;

      // 先尝试 HTTP（默认配置）
      try {
        final request = await client.getUrl(
          Uri.parse('http://$ip:$_servicePort/health'),
        );
        final response = await request.close().timeout(
              const Duration(milliseconds: 800),
            );

        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;

          if (json['status'] == 'healthy') {
            _notifier.addDevice(
              DiscoveredDevice(
                id: ip,
                name: 'RockZero @ $ip',
                ip: ip,
                port: _servicePort,
                version: json['version'] ?? 'unknown',
                isSecure: false,
                discoveredAt: DateTime.now(),
              ),
            );
          }
        }
      } catch (_) {
        // HTTP 失败，尝试 HTTPS
        try {
          final request = await client.getUrl(
            Uri.parse('https://$ip:$_servicePort/health'),
          );
          final response = await request.close().timeout(
                const Duration(milliseconds: 800),
              );

          if (response.statusCode == 200) {
            final body = await response.transform(utf8.decoder).join();
            final json = jsonDecode(body) as Map<String, dynamic>;

            if (json['status'] == 'healthy') {
              _notifier.addDevice(
                DiscoveredDevice(
                  id: ip,
                  name: 'RockZero @ $ip',
                  ip: ip,
                  port: _servicePort,
                  version: json['version'] ?? 'unknown',
                  isSecure: true,
                  discoveredAt: DateTime.now(),
                ),
              );
            }
          }
        } catch (_) {}
      }

      client.close();
    } catch (_) {}
  }

  Future<bool> testConnection(DiscoveredDevice device) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(
        Uri.parse('${device.baseUrl}/health'),
      );
      final response = await request.close();
      client.close();

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 自动探测设备，尝试 HTTP 和 HTTPS
  /// 返回成功连接的设备，如果都失败则返回 null
  Future<DiscoveredDevice?> autoDetectDevice(String ip, {int? port}) async {
    final targetPort = port ?? _servicePort;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..badCertificateCallback = (cert, host, port) => true;

    // 先尝试 HTTP
    try {
      final request = await client.getUrl(
        Uri.parse('http://$ip:$targetPort/health'),
      );
      final response = await request.close().timeout(
            const Duration(seconds: 3),
          );

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        if (json['status'] == 'healthy') {
          client.close();
          return DiscoveredDevice(
            id: ip,
            name: 'RockZero @ $ip',
            ip: ip,
            port: targetPort,
            version: json['version'] ?? 'unknown',
            isSecure: false,
            discoveredAt: DateTime.now(),
          );
        }
      }
    } catch (_) {}

    // HTTP 失败，尝试 HTTPS
    try {
      final request = await client.getUrl(
        Uri.parse('https://$ip:$targetPort/health'),
      );
      final response = await request.close().timeout(
            const Duration(seconds: 3),
          );

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        if (json['status'] == 'healthy') {
          client.close();
          return DiscoveredDevice(
            id: ip,
            name: 'RockZero @ $ip',
            ip: ip,
            port: targetPort,
            version: json['version'] ?? 'unknown',
            isSecure: true,
            discoveredAt: DateTime.now(),
          );
        }
      }
    } catch (_) {}

    client.close();
    return null;
  }
}
