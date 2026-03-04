import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_service.dart';
import '../../../../core/services/device_discovery_service.dart';

class LanTransferPage extends ConsumerStatefulWidget {
  const LanTransferPage({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LanTransferPage()),
    );
  }

  @override
  ConsumerState<LanTransferPage> createState() => _LanTransferPageState();
}

class _LanTransferPageState extends ConsumerState<LanTransferPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  List<Map<String, dynamic>> _sharedItems = [];
  bool _isLoadingShared = false;
  List<Map<String, dynamic>> _sessions = [];

  List<_PeerDevice> _peers = [];
  bool _isScanning = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSharedItems();
    _loadSessions();
    _scanPeers();

    // 每 3 秒刷新传输进度
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadSessions();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  ApiService get _api => ref.read(apiServiceProvider);

  Future<void> _loadSharedItems() async {
    setState(() => _isLoadingShared = true);
    try {
      final resp = await _api.get('/api/v1/lan-transfer/shared');
      final data = resp.data as Map<String, dynamic>? ?? {};
      setState(() {
        _sharedItems = List<Map<String, dynamic>>.from(data['items'] ?? []);
        _isLoadingShared = false;
      });
    } catch (e) {
      setState(() => _isLoadingShared = false);
    }
  }

  Future<void> _loadSessions() async {
    try {
      final resp = await _api.get('/api/v1/lan-transfer/sessions');
      final data = resp.data as Map<String, dynamic>? ?? {};
      if (mounted) {
        setState(() {
          _sessions = List<Map<String, dynamic>>.from(data['sessions'] ?? []);
        });
      }
    } catch (_) {}
  }

  Future<void> _scanPeers() async {
    setState(() => _isScanning = true);
    try {
      // 使用现有的设备发现服务
      var discoveryState = ref.read(deviceDiscoveryStateProvider);
      var devices = discoveryState.devices;

      // 如果设备列表为空，触发一次扫描
      if (devices.isEmpty) {
        final service = ref.read(deviceDiscoveryServiceProvider);
        await service.startDiscovery();
        await Future.delayed(const Duration(seconds: 4));
        discoveryState = ref.read(deviceDiscoveryStateProvider);
        devices = discoveryState.devices;
      }

      final peers = <_PeerDevice>[];
      for (final device in devices) {
        // 查询对端的 LAN transfer 能力
        try {
          final peerDio = Dio(BaseOptions(
            baseUrl: device.baseUrl,
            connectTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(seconds: 5),
          ));
          final peerApi = ApiService(peerDio);
          final infoResp = await peerApi
              .get('/api/v1/lan-transfer/device-info')
              .timeout(const Duration(seconds: 3));
          final info = infoResp.data as Map<String, dynamic>? ?? {};

          final capabilities =
              (info['capabilities'] as List?)?.cast<String>() ?? [];
          if (capabilities.contains('lan_transfer')) {
            peers.add(_PeerDevice(
              device: device,
              deviceName: info['device_name'] as String? ?? device.name,
              sharedCount: info['shared_items_count'] as int? ?? 0,
              activeTransfers: info['active_transfers'] as int? ?? 0,
            ));
          }
        } catch (_) {
          // 不支持 LAN transfer 的设备，跳过
        }
      }

      setState(() {
        _peers = peers;
        _isScanning = false;
      });
    } catch (e) {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _scanGames() async {
    try {
      await _api.post('/api/v1/lan-transfer/scan-games');
      await _loadSharedItems();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Steam 游戏库扫描完成')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e')),
        );
      }
    }
  }

  Future<void> _removeShared(String id) async {
    try {
      await _api.delete('/api/v1/lan-transfer/share/$id');
      await _loadSharedItems();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移除失败: $e')),
        );
      }
    }
  }

  Future<void> _cancelSession(String id) async {
    try {
      await _api.post('/api/v1/lan-transfer/sessions/$id/cancel');
      await _loadSessions();
    } catch (_) {}
  }

  Future<void> _cleanupSessions() async {
    try {
      await _api.post('/api/v1/lan-transfer/sessions/cleanup');
      await _loadSessions();
    } catch (_) {}
  }

  Future<void> _browseAndReceive(_PeerDevice peer) async {
    // 获取对端共享列表
    try {
      final peerDio = Dio(BaseOptions(
        baseUrl: peer.device.baseUrl,
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 10),
      ));
      final peerApi = ApiService(peerDio);
      final resp = await peerApi.get('/api/v1/lan-transfer/shared');
      final data = resp.data as Map<String, dynamic>? ?? {};
      final items = List<Map<String, dynamic>>.from(data['items'] ?? []);

      if (!mounted) return;

      _showPeerItemsDialog(peer, items);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法连接到 ${peer.deviceName}: $e')),
        );
      }
    }
  }

  void _showPeerItemsDialog(
      _PeerDevice peer, List<Map<String, dynamic>> items) {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.devices_rounded, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${peer.deviceName} 的共享',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.5,
          child: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_off_rounded,
                          size: 48, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 8),
                      Text('该设备暂无共享内容',
                          style:
                              TextStyle(color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    final name = item['name'] as String? ?? '';
                    final size = item['size_bytes'] as int? ?? 0;
                    final type_ = item['item_type'] as String? ?? 'file';
                    final fileCount = item['file_count'] as int? ?? 1;

                    return ListTile(
                      leading: Icon(
                        type_ == 'game'
                            ? Icons.sports_esports_rounded
                            : type_ == 'directory'
                                ? Icons.folder_rounded
                                : Icons.insert_drive_file_rounded,
                        color: colorScheme.primary,
                      ),
                      title: Text(name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${_formatSize(size)} · $fileCount 个文件',
                        style: TextStyle(
                            fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.download_rounded),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _startReceive(peer, item);
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _startReceive(
      _PeerDevice peer, Map<String, dynamic> item) async {
    try {
      await _api.post('/api/v1/lan-transfer/receive', data: {
        'item_id': item['id'],
        'peer_url': peer.device.baseUrl,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('开始从 ${peer.deviceName} 下载 ${item['name']}')),
        );
        // 切换到传输 tab
        _tabController.animateTo(2);
        await _loadSessions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动传输失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('局域网传输'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _loadSharedItems();
              _loadSessions();
              _scanPeers();
            },
            tooltip: '刷新',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.devices_rounded), text: '设备'),
            Tab(icon: Icon(Icons.share_rounded), text: '共享'),
            Tab(icon: Icon(Icons.sync_rounded), text: '传输'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDevicesTab(colorScheme),
          _buildSharedTab(colorScheme),
          _buildTransfersTab(colorScheme),
        ],
      ),
    );
  }

  /// 设备发现 Tab
  Widget _buildDevicesTab(ColorScheme colorScheme) {
    return RefreshIndicator(
      onRefresh: _scanPeers,
      child: _isScanning && _peers.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _peers.isEmpty
              ? ListView(
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 64, color: colorScheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text('未发现支持传输的设备',
                              style: TextStyle(
                                  color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Text('请确保其他 RockZero 设备在同一局域网内',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _scanPeers,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('重新扫描'),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _peers.length,
                  itemBuilder: (ctx, i) =>
                      _buildPeerCard(_peers[i], colorScheme),
                ),
    );
  }

  Widget _buildPeerCard(_PeerDevice peer, ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _browseAndReceive(peer),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.computer_rounded,
                    color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peer.deviceName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      peer.device.ip,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.folder_shared_rounded,
                            size: 14, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          '${peer.sharedCount} 个共享',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.primary,
                          ),
                        ),
                        if (peer.activeTransfers > 0) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.sync_rounded,
                              size: 14, color: Colors.orange),
                          const SizedBox(width: 4),
                          Text(
                            '${peer.activeTransfers} 传输中',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  /// 本机共享 Tab
  Widget _buildSharedTab(ColorScheme colorScheme) {
    return Column(
      children: [
        // 操作按钮栏
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _scanGames,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('扫描 Steam 库'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _showAddShareDialog,
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加共享'),
              ),
            ],
          ),
        ),
        // 共享列表
        Expanded(
          child: _isLoadingShared
              ? const Center(child: CircularProgressIndicator())
              : _sharedItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.share_rounded,
                              size: 48, color: colorScheme.onSurfaceVariant),
                          const SizedBox(height: 8),
                          Text('暂无共享内容',
                              style: TextStyle(
                                  color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Text('扫描 Steam 库或手动添加文件',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _sharedItems.length,
                      itemBuilder: (ctx, i) =>
                          _buildSharedItemCard(_sharedItems[i], colorScheme),
                    ),
        ),
      ],
    );
  }

  Widget _buildSharedItemCard(
      Map<String, dynamic> item, ColorScheme colorScheme) {
    final name = item['name'] as String? ?? '';
    final size = item['size_bytes'] as int? ?? 0;
    final type_ = item['item_type'] as String? ?? 'file';
    final fileCount = item['file_count'] as int? ?? 1;
    final id = item['id'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: type_ == 'game'
                ? Colors.indigo.withAlpha(30)
                : colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            type_ == 'game'
                ? Icons.sports_esports_rounded
                : type_ == 'directory'
                    ? Icons.folder_rounded
                    : Icons.insert_drive_file_rounded,
            color: type_ == 'game'
                ? Colors.indigo
                : colorScheme.onPrimaryContainer,
            size: 20,
          ),
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_formatSize(size)} · $fileCount 文件',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        trailing: IconButton(
          icon: Icon(Icons.close_rounded, color: colorScheme.error, size: 20),
          onPressed: () => _removeShared(id),
          tooltip: '取消共享',
        ),
      ),
    );
  }

  void _showAddShareDialog() {
    final pathCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.add_circle_rounded, color: colorScheme.primary),
            const SizedBox(width: 8),
            const Text('添加共享'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pathCtrl,
              decoration: const InputDecoration(
                labelText: '文件/目录路径',
                hintText: '/path/to/game/folder',
                prefixIcon: Icon(Icons.folder_open_rounded),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '显示名称（可选）',
                hintText: '我的游戏',
                prefixIcon: Icon(Icons.label_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (pathCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _api.post('/api/v1/lan-transfer/share', data: {
                  'path': pathCtrl.text.trim(),
                  if (nameCtrl.text.trim().isNotEmpty)
                    'name': nameCtrl.text.trim(),
                });
                await _loadSharedItems();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('添加共享失败: $e')),
                  );
                }
              }
            },
            child: const Text('共享'),
          ),
        ],
      ),
    );
  }

  /// 传输会话 Tab
  Widget _buildTransfersTab(ColorScheme colorScheme) {
    return Column(
      children: [
        // 清理按钮
        if (_sessions.any((s) =>
            s['status'] == 'completed' ||
            s['status'] == 'failed' ||
            s['status'] == 'cancelled'))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _cleanupSessions,
                icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                label: const Text('清理已完成'),
              ),
            ),
          ),
        Expanded(
          child: _sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_horiz_rounded,
                          size: 48, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 8),
                      Text('暂无传输任务',
                          style:
                              TextStyle(color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _sessions.length,
                  itemBuilder: (ctx, i) =>
                      _buildSessionCard(_sessions[i], colorScheme),
                ),
        ),
      ],
    );
  }

  Widget _buildSessionCard(
      Map<String, dynamic> session, ColorScheme colorScheme) {
    final name = session['item_name'] as String? ?? '';
    final totalBytes = session['total_bytes'] as int? ?? 0;
    final transferred = session['transferred_bytes'] as int? ?? 0;
    final status = session['status'] as String? ?? 'pending';
    final speedBps = session['speed_bps'] as int? ?? 0;
    final sessionId = session['id'] as String? ?? '';
    final direction = session['direction'] as String? ?? 'download';
    final peer = session['peer_address'] as String? ?? '';

    final progress = totalBytes > 0 ? transferred / totalBytes : 0.0;
    final isActive = status == 'transferring' || status == 'pending';

    Color statusColor;
    IconData statusIcon;
    String statusText;
    switch (status) {
      case 'transferring':
        statusColor = Colors.blue;
        statusIcon = Icons.sync_rounded;
        statusText = '传输中';
        break;
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_rounded;
        statusText = '完成';
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.error_rounded;
        statusText = '失败';
        break;
      case 'cancelled':
        statusColor = Colors.orange;
        statusIcon = Icons.cancel_rounded;
        statusText = '已取消';
        break;
      case 'paused':
        statusColor = Colors.amber;
        statusIcon = Icons.pause_circle_rounded;
        statusText = '暂停';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.hourglass_empty_rounded;
        statusText = '等待中';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  direction == 'download'
                      ? Icons.download_rounded
                      : Icons.upload_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (peer.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                peer,
                style: TextStyle(
                    fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 12),
            // 进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: statusColor,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${_formatSize(transferred)} / ${_formatSize(totalBytes)}',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                if (isActive && speedBps > 0)
                  Text(
                    '${_formatSize(speedBps)}/s',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                Text(
                  ' · ${(progress * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            if (isActive) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _cancelSession(sessionId),
                  icon: Icon(Icons.stop_rounded,
                      size: 16, color: colorScheme.error),
                  label: Text('取消', style: TextStyle(color: colorScheme.error)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _PeerDevice {
  final DiscoveredDevice device;
  final String deviceName;
  final int sharedCount;
  final int activeTransfers;

  _PeerDevice({
    required this.device,
    required this.deviceName,
    required this.sharedCount,
    required this.activeTransfers,
  });
}
