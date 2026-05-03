import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum NetworkProtocol {
  smb('SMB/CIFS', 'Windows file sharing', Icons.computer_rounded, 445),
  nfs('NFS', 'Network File System', Icons.dns_rounded, 2049),
  ftp('FTP', 'File Transfer Protocol', Icons.folder_shared_rounded, 21),
  sftp('SFTP', 'Secure FTP over SSH', Icons.security_rounded, 22),
  webdav('WebDAV', 'Web-based file access', Icons.cloud_rounded, 80);

  final String displayName;
  final String description;
  final IconData icon;
  final int defaultPort;

  const NetworkProtocol(
    this.displayName,
    this.description,
    this.icon,
    this.defaultPort,
  );
}

class NetworkShare {
  final String id;
  final String name;
  final NetworkProtocol protocol;
  final String host;
  final int port;
  final String? username;
  final String? password;
  final String? remotePath;
  final bool isConnected;
  final DateTime? lastConnected;

  NetworkShare({
    required this.id,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    this.username,
    this.password,
    this.remotePath,
    this.isConnected = false,
    this.lastConnected,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'host': host,
        'port': port,
        'username': username,
        'remotePath': remotePath,
        'lastConnected': lastConnected?.toIso8601String(),
      };

  factory NetworkShare.fromJson(Map<String, dynamic> json) {
    return NetworkShare(
      id: json['id'] as String,
      name: json['name'] as String,
      protocol: NetworkProtocol.values.firstWhere(
        (p) => p.name == json['protocol'],
        orElse: () => NetworkProtocol.smb,
      ),
      host: json['host'] as String,
      port: json['port'] as int,
      username: json['username'] as String?,
      remotePath: json['remotePath'] as String?,
      lastConnected: json['lastConnected'] != null
          ? DateTime.parse(json['lastConnected'] as String)
          : null,
    );
  }

  NetworkShare copyWith({
    String? id,
    String? name,
    NetworkProtocol? protocol,
    String? host,
    int? port,
    String? username,
    String? password,
    String? remotePath,
    bool? isConnected,
    DateTime? lastConnected,
  }) {
    return NetworkShare(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      remotePath: remotePath ?? this.remotePath,
      isConnected: isConnected ?? this.isConnected,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }
}

class NetworkSharesNotifier extends Notifier<List<NetworkShare>> {
  @override
  List<NetworkShare> build() {
    _loadShares();
    return [];
  }

  Future<void> _loadShares() async {
    final box = Hive.box('settings');
    final sharesJson = box.get('networkShares', defaultValue: <dynamic>[]);
    final shares = (sharesJson as List)
        .map((e) => NetworkShare.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    state = shares;
  }

  Future<void> _saveShares() async {
    final box = Hive.box('settings');
    await box.put('networkShares', state.map((s) => s.toJson()).toList());
  }

  Future<void> addShare(NetworkShare share) async {
    state = [...state, share];
    await _saveShares();
  }

  Future<void> updateShare(NetworkShare share) async {
    state = state.map((s) => s.id == share.id ? share : s).toList();
    await _saveShares();
  }

  Future<void> removeShare(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _saveShares();
  }

  Future<void> setConnected(String id, bool connected) async {
    state = state.map((s) {
      if (s.id == id) {
        return s.copyWith(
          isConnected: connected,
          lastConnected: connected ? DateTime.now() : s.lastConnected,
        );
      }
      return s;
    }).toList();
    await _saveShares();
  }
}

final networkSharesProvider =
    NotifierProvider<NetworkSharesNotifier, List<NetworkShare>>(
  NetworkSharesNotifier.new,
);

class NetworkSharesPage extends ConsumerStatefulWidget {
  const NetworkSharesPage({super.key});

  @override
  ConsumerState<NetworkSharesPage> createState() => _NetworkSharesPageState();
}

class _NetworkSharesPageState extends ConsumerState<NetworkSharesPage> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final shares = ref.watch(networkSharesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Shares'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: _showProtocolHelp,
            tooltip: 'Protocol help',
          ),
        ],
      ),
      body: shares.isEmpty
          ? _buildEmptyState(colorScheme, textTheme)
          : _buildSharesList(shares, colorScheme, textTheme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddShareDialog(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Share'),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.folder_shared_rounded,
                size: 48,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Network Shares',
              style:
                  textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Add network shares to access files from SMB, NFS, FTP, SFTP, or WebDAV servers',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: NetworkProtocol.values.map((protocol) {
                return _ProtocolChip(
                  protocol: protocol,
                  onTap: () => _showAddShareDialog(initialProtocol: protocol),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSharesList(
    List<NetworkShare> shares,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: shares.length,
      itemBuilder: (context, index) {
        final share = shares[index];
        return _ShareCard(
          share: share,
          onConnect: () => _connectToShare(share),
          onEdit: () => _showEditShareDialog(share),
          onDelete: () => _deleteShare(share),
        );
      },
    );
  }

  void _showProtocolHelp() {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Supported Protocols',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              ...NetworkProtocol.values.map((protocol) => _ProtocolHelpCard(
                    protocol: protocol,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddShareDialog({NetworkProtocol? initialProtocol}) {
    showDialog(
      context: context,
      builder: (context) => _AddEditShareDialog(
        initialProtocol: initialProtocol,
        onSave: (share) {
          ref.read(networkSharesProvider.notifier).addShare(share);
        },
      ),
    );
  }

  void _showEditShareDialog(NetworkShare share) {
    showDialog(
      context: context,
      builder: (context) => _AddEditShareDialog(
        share: share,
        onSave: (updatedShare) {
          ref.read(networkSharesProvider.notifier).updateShare(updatedShare);
        },
      ),
    );
  }

  Future<void> _connectToShare(NetworkShare share) async {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(width: 24),
            Text('Connecting to ${share.name}...'),
          ],
        ),
      ),
    );

    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${share.protocol.displayName} connection requires server-side support',
          ),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () {},
          ),
        ),
      );
    }
  }

  void _deleteShare(NetworkShare share) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Share'),
        content: Text('Are you sure you want to delete "${share.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(networkSharesProvider.notifier).removeShare(share.id);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ProtocolChip extends StatelessWidget {
  final NetworkProtocol protocol;
  final VoidCallback onTap;

  const _ProtocolChip({required this.protocol, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(protocol.icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                protocol.displayName,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProtocolHelpCard extends StatelessWidget {
  final NetworkProtocol protocol;

  const _ProtocolHelpCard({required this.protocol});

  String _getProtocolDetails() {
    switch (protocol) {
      case NetworkProtocol.smb:
        return 'SMB (Server Message Block) / CIFS is the standard Windows file sharing protocol. Use for accessing Windows shares, NAS devices, and Samba servers.';
      case NetworkProtocol.nfs:
        return 'NFS (Network File System) is commonly used in Unix/Linux environments. Ideal for high-performance file sharing between Linux systems.';
      case NetworkProtocol.ftp:
        return 'FTP (File Transfer Protocol) is a standard protocol for transferring files. Note: FTP transmits data in plain text.';
      case NetworkProtocol.sftp:
        return 'SFTP (SSH File Transfer Protocol) provides secure file transfer over SSH. Recommended for secure remote file access.';
      case NetworkProtocol.webdav:
        return 'WebDAV (Web Distributed Authoring and Versioning) allows file access over HTTP/HTTPS. Works well through firewalls.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                protocol.icon,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        protocol.displayName,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Port ${protocol.defaultPort}',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getProtocolDetails(),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareCard extends StatelessWidget {
  final NetworkShare share;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ShareCard({
    required this.share,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onConnect,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: share.isConnected
                          ? Colors.green.withValues(alpha: 0.15)
                          : colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      share.protocol.icon,
                      color: share.isConnected
                          ? Colors.green
                          : colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          share.name,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${share.protocol.displayName} • ${share.host}:${share.port}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onEdit();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_rounded, size: 20),
                            SizedBox(width: 12),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_rounded,
                              size: 20,
                              color: colorScheme.error,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Delete',
                              style: TextStyle(color: colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (share.remotePath != null && share.remotePath!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        share.remotePath!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (share.lastConnected != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Last connected: ${_formatDate(share.lastConnected!)}',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

class _AddEditShareDialog extends StatefulWidget {
  final NetworkShare? share;
  final NetworkProtocol? initialProtocol;
  final Function(NetworkShare) onSave;

  const _AddEditShareDialog({
    this.share,
    this.initialProtocol,
    required this.onSave,
  });

  @override
  State<_AddEditShareDialog> createState() => _AddEditShareDialogState();
}

class _AddEditShareDialogState extends State<_AddEditShareDialog> {
  late TextEditingController _nameController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _pathController;
  late NetworkProtocol _selectedProtocol;

  @override
  void initState() {
    super.initState();
    _selectedProtocol =
        widget.share?.protocol ?? widget.initialProtocol ?? NetworkProtocol.smb;
    _nameController = TextEditingController(text: widget.share?.name ?? '');
    _hostController = TextEditingController(text: widget.share?.host ?? '');
    _portController = TextEditingController(
      text: widget.share?.port.toString() ??
          _selectedProtocol.defaultPort.toString(),
    );
    _usernameController =
        TextEditingController(text: widget.share?.username ?? '');
    _passwordController =
        TextEditingController(text: widget.share?.password ?? '');
    _pathController =
        TextEditingController(text: widget.share?.remotePath ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  void _updatePort() {
    _portController.text = _selectedProtocol.defaultPort.toString();
  }

  void _save() {
    if (_nameController.text.isEmpty || _hostController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and host are required')),
      );
      return;
    }

    final share = NetworkShare(
      id: widget.share?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      protocol: _selectedProtocol,
      host: _hostController.text,
      port: int.tryParse(_portController.text) ?? _selectedProtocol.defaultPort,
      username:
          _usernameController.text.isNotEmpty ? _usernameController.text : null,
      password:
          _passwordController.text.isNotEmpty ? _passwordController.text : null,
      remotePath: _pathController.text.isNotEmpty ? _pathController.text : null,
      lastConnected: widget.share?.lastConnected,
    );

    widget.onSave(share);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditing = widget.share != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Share' : 'Add Network Share'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Protocol',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: NetworkProtocol.values.map((protocol) {
                final isSelected = protocol == _selectedProtocol;
                return ChoiceChip(
                  label: Text(protocol.displayName),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedProtocol = protocol;
                        _updatePort();
                      });
                    }
                  },
                  avatar: Icon(
                    protocol.icon,
                    size: 18,
                    color: isSelected ? colorScheme.onPrimary : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                hintText: 'My NAS',
                prefixIcon: Icon(Icons.label_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText: '192.168.1.100 or nas.local',
                prefixIcon: Icon(Icons.dns_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Port',
                hintText: _selectedProtocol.defaultPort.toString(),
                prefixIcon: const Icon(Icons.numbers_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username (optional)',
                prefixIcon: Icon(Icons.person_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password (optional)',
                prefixIcon: Icon(Icons.lock_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pathController,
              decoration: InputDecoration(
                labelText: 'Remote Path (optional)',
                hintText: _selectedProtocol == NetworkProtocol.smb
                    ? '/share'
                    : '/home/user',
                prefixIcon: const Icon(Icons.folder_rounded),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
