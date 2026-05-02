import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_service.dart';

class DiskPlatformCapabilities {
  final String platform;
  final String architecture;
  final String environmentProfile;
  final String environmentLabel;
  final String? deviceModel;
  final bool supportsDiskListing;
  final bool supportsDiskDetails;
  final bool supportsDiskScan;
  final bool supportsMount;
  final bool supportsUnmount;
  final bool supportsFormat;
  final bool supportsInitialize;
  final bool supportsRename;
  final bool supportsHealth;
  final bool supportsEject;
  final bool supportsFileOperations;
  final bool readWriteOnlyMode;
  final bool scopedStorageRequired;
  final bool scopedStorageConfigured;
  final String? selectedRoot;
  final String? configPath;
  final String? restrictionMessage;

  const DiskPlatformCapabilities({
    required this.platform,
    required this.architecture,
    required this.environmentProfile,
    required this.environmentLabel,
    this.deviceModel,
    required this.supportsDiskListing,
    required this.supportsDiskDetails,
    required this.supportsDiskScan,
    required this.supportsMount,
    required this.supportsUnmount,
    required this.supportsFormat,
    required this.supportsInitialize,
    required this.supportsRename,
    required this.supportsHealth,
    required this.supportsEject,
    required this.supportsFileOperations,
    required this.readWriteOnlyMode,
    required this.scopedStorageRequired,
    required this.scopedStorageConfigured,
    this.selectedRoot,
    this.configPath,
    this.restrictionMessage,
  });

  factory DiskPlatformCapabilities.fromJson(Map<String, dynamic> json) {
    bool readBool(String key, {bool defaultValue = false}) {
      final value = json[key];
      return value is bool ? value : defaultValue;
    }

    return DiskPlatformCapabilities(
      platform: ((json['platform'] as String?) ?? 'unknown').toLowerCase(),
      architecture:
        ((json['architecture'] as String?) ?? 'unknown').toLowerCase(),
      environmentProfile:
        (json['environment_profile'] as String?) ?? 'generic',
      environmentLabel:
        (json['environment_label'] as String?) ?? 'Unknown backend',
      deviceModel: json['device_model'] as String?,
      supportsDiskListing:
          readBool('supports_disk_listing', defaultValue: true),
      supportsDiskDetails:
          readBool('supports_disk_details', defaultValue: true),
      supportsDiskScan: readBool('supports_disk_scan'),
      supportsMount: readBool('supports_mount'),
      supportsUnmount: readBool('supports_unmount'),
      supportsFormat: readBool('supports_format'),
      supportsInitialize: readBool('supports_initialize'),
      supportsRename: readBool('supports_rename'),
      supportsHealth: readBool('supports_health'),
      supportsEject: readBool('supports_eject'),
      supportsFileOperations:
          readBool('supports_file_operations', defaultValue: true),
      readWriteOnlyMode: readBool('read_write_only_mode'),
      scopedStorageRequired: readBool('scoped_storage_required'),
      scopedStorageConfigured: readBool('scoped_storage_configured'),
      selectedRoot: json['selected_root'] as String?,
      configPath: json['config_path'] as String?,
      restrictionMessage: json['restriction_message'] as String?,
    );
  }

  factory DiskPlatformCapabilities.safeFallback() {
    return const DiskPlatformCapabilities(
      platform: 'unknown',
      architecture: 'unknown',
      environmentProfile: 'generic',
      environmentLabel: 'Unknown backend',
      supportsDiskListing: true,
      supportsDiskDetails: true,
      supportsDiskScan: false,
      supportsMount: false,
      supportsUnmount: false,
      supportsFormat: false,
      supportsInitialize: false,
      supportsRename: false,
      supportsHealth: false,
      supportsEject: false,
      supportsFileOperations: true,
      readWriteOnlyMode: true,
      scopedStorageRequired: false,
      scopedStorageConfigured: false,
      restrictionMessage:
          'Disk status is available, but storage management controls are disabled until backend capabilities are confirmed.',
    );
  }

  bool get allowsManagement =>
      supportsDiskScan ||
      supportsMount ||
      supportsUnmount ||
      supportsFormat ||
      supportsInitialize ||
      supportsRename ||
      supportsHealth ||
      supportsEject;

  String get statusLabel => readWriteOnlyMode
      ? 'Read-only storage mode active'
      : 'Full storage management available';
}

final diskPlatformCapabilitiesProvider =
    FutureProvider<DiskPlatformCapabilities>((ref) async {
  final api = ref.read(apiServiceProvider);
  try {
    final data = await api.getDiskCapabilities();
    return DiskPlatformCapabilities.fromJson(data);
  } catch (e, stack) {
    debugPrint('[DiskCapabilities] Failed to load backend capabilities: $e');
    debugPrint('$stack');
    return DiskPlatformCapabilities.safeFallback();
  }
});
