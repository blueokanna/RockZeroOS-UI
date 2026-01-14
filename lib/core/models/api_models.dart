import 'package:json_annotation/json_annotation.dart';

part 'api_models.g.dart';

// ============ Auth Models ============

@JsonSerializable()
class User {
  final String id;
  final String username;
  final String email;
  final String role;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}

@JsonSerializable()
class TokenResponse {
  @JsonKey(name: 'access_token')
  final String accessToken;
  @JsonKey(name: 'refresh_token')
  final String refreshToken;
  @JsonKey(name: 'token_type')
  final String tokenType;
  @JsonKey(name: 'expires_in')
  final int expiresIn;

  TokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
  });

  factory TokenResponse.fromJson(Map<String, dynamic> json) =>
      _$TokenResponseFromJson(json);
  Map<String, dynamic> toJson() => _$TokenResponseToJson(this);
}

@JsonSerializable()
class AuthResponse {
  final User user;
  final TokenResponse tokens;

  AuthResponse({required this.user, required this.tokens});

  factory AuthResponse.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseFromJson(json);
  Map<String, dynamic> toJson() => _$AuthResponseToJson(this);
}

@JsonSerializable()
class InviteCodeResponse {
  final String code;
  @JsonKey(name: 'expires_in_seconds')
  final int expiresInSeconds;

  InviteCodeResponse({required this.code, required this.expiresInSeconds});

  factory InviteCodeResponse.fromJson(Map<String, dynamic> json) =>
      _$InviteCodeResponseFromJson(json);
  Map<String, dynamic> toJson() => _$InviteCodeResponseToJson(this);
}

// ============ ZKP Models (零知识证明) ============

/// ZKP 密码证明数据
@JsonSerializable()
class ZkpPasswordProof {
  final String commitment;
  final String challenge;
  final String response;
  @JsonKey(name: 'blinding_commitment')
  final String blindingCommitment;

  ZkpPasswordProof({
    required this.commitment,
    required this.challenge,
    required this.response,
    required this.blindingCommitment,
  });

  factory ZkpPasswordProof.fromJson(Map<String, dynamic> json) =>
      _$ZkpPasswordProofFromJson(json);
  Map<String, dynamic> toJson() => _$ZkpPasswordProofToJson(this);
}

/// 增强的 ZKP 证明
@JsonSerializable()
class EnhancedZkpProof {
  @JsonKey(name: 'schnorr_proof')
  final ZkpPasswordProof schnorrProof;
  @JsonKey(name: 'strength_proof')
  final String? strengthProof;
  final int timestamp;
  final String nonce;

  EnhancedZkpProof({
    required this.schnorrProof,
    this.strengthProof,
    required this.timestamp,
    required this.nonce,
  });

  factory EnhancedZkpProof.fromJson(Map<String, dynamic> json) =>
      _$EnhancedZkpProofFromJson(json);
  Map<String, dynamic> toJson() => _$EnhancedZkpProofToJson(this);
}

/// ZKP 证明响应
@JsonSerializable()
class ZkpProofResponse {
  final ZkpPasswordProof proof;

  ZkpProofResponse({required this.proof});

  factory ZkpProofResponse.fromJson(Map<String, dynamic> json) =>
      _$ZkpProofResponseFromJson(json);
  Map<String, dynamic> toJson() => _$ZkpProofResponseToJson(this);
}

/// 增强 ZKP 证明响应
@JsonSerializable()
class EnhancedZkpProofResponse {
  final EnhancedZkpProof proof;

  EnhancedZkpProofResponse({required this.proof});

  factory EnhancedZkpProofResponse.fromJson(Map<String, dynamic> json) =>
      _$EnhancedZkpProofResponseFromJson(json);
  Map<String, dynamic> toJson() => _$EnhancedZkpProofResponseToJson(this);
}

/// 密码强度响应
@JsonSerializable()
class PasswordStrengthResponse {
  final int entropy;
  @JsonKey(name: 'entropy_bits')
  final double entropyBits;
  final String strength;
  final List<String> suggestions;

  PasswordStrengthResponse({
    required this.entropy,
    required this.entropyBits,
    required this.strength,
    required this.suggestions,
  });

  factory PasswordStrengthResponse.fromJson(Map<String, dynamic> json) =>
      _$PasswordStrengthResponseFromJson(json);
  Map<String, dynamic> toJson() => _$PasswordStrengthResponseToJson(this);
}

/// 范围证明数据
@JsonSerializable()
class RangeProofData {
  final String proof;
  final String commitment;
  @JsonKey(name: 'n_bits')
  final int nBits;

  RangeProofData({
    required this.proof,
    required this.commitment,
    required this.nBits,
  });

  factory RangeProofData.fromJson(Map<String, dynamic> json) =>
      _$RangeProofDataFromJson(json);
  Map<String, dynamic> toJson() => _$RangeProofDataToJson(this);
}

/// 范围证明响应
@JsonSerializable()
class RangeProofResponse {
  final RangeProofData proof;

  RangeProofResponse({required this.proof});

  factory RangeProofResponse.fromJson(Map<String, dynamic> json) =>
      _$RangeProofResponseFromJson(json);
  Map<String, dynamic> toJson() => _$RangeProofResponseToJson(this);
}

// ============ File Models ============

@JsonSerializable()
class FileResponse {
  final String id;
  final String filename;
  @JsonKey(name: 'mime_type')
  final String mimeType;
  @JsonKey(name: 'file_size')
  final int fileSize;
  @JsonKey(name: 'is_public')
  final bool isPublic;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'download_url')
  final String downloadUrl;

  FileResponse({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.fileSize,
    required this.isPublic,
    required this.createdAt,
    required this.downloadUrl,
  });

  factory FileResponse.fromJson(Map<String, dynamic> json) =>
      _$FileResponseFromJson(json);
  Map<String, dynamic> toJson() => _$FileResponseToJson(this);
}

@JsonSerializable()
class FileListResponse {
  final List<FileResponse> files;
  final int total;

  FileListResponse({required this.files, required this.total});

  factory FileListResponse.fromJson(Map<String, dynamic> json) =>
      _$FileListResponseFromJson(json);
  Map<String, dynamic> toJson() => _$FileListResponseToJson(this);
}

// ============ Media Models ============

@JsonSerializable()
class MediaResponse {
  final String id;
  final String title;
  @JsonKey(name: 'media_type')
  final String mediaType;
  final int? duration;
  @JsonKey(name: 'file_url')
  final String fileUrl;
  @JsonKey(name: 'thumbnail_url')
  final String? thumbnailUrl;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  MediaResponse({
    required this.id,
    required this.title,
    required this.mediaType,
    this.duration,
    required this.fileUrl,
    this.thumbnailUrl,
    required this.createdAt,
  });

  factory MediaResponse.fromJson(Map<String, dynamic> json) =>
      _$MediaResponseFromJson(json);
  Map<String, dynamic> toJson() => _$MediaResponseToJson(this);
}

@JsonSerializable()
class MediaCodecInfo {
  @JsonKey(name: 'ffmpeg_available')
  final bool ffmpegAvailable;
  @JsonKey(name: 'supported_video_codecs')
  final List<String> supportedVideoCodecs;
  @JsonKey(name: 'supported_audio_codecs')
  final List<String> supportedAudioCodecs;
  @JsonKey(name: 'hardware_acceleration')
  final List<String> hardwareAcceleration;

  MediaCodecInfo({
    required this.ffmpegAvailable,
    required this.supportedVideoCodecs,
    required this.supportedAudioCodecs,
    required this.hardwareAcceleration,
  });

  factory MediaCodecInfo.fromJson(Map<String, dynamic> json) =>
      _$MediaCodecInfoFromJson(json);
  Map<String, dynamic> toJson() => _$MediaCodecInfoToJson(this);
}

// ============ Widget Models ============

@JsonSerializable()
class WidgetResponse {
  final String id;
  @JsonKey(name: 'widget_type')
  final String widgetType;
  final String title;
  final Map<String, dynamic> config;
  @JsonKey(name: 'position_x')
  final int positionX;
  @JsonKey(name: 'position_y')
  final int positionY;
  final int width;
  final int height;
  @JsonKey(name: 'is_visible')
  final bool isVisible;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  WidgetResponse({
    required this.id,
    required this.widgetType,
    required this.title,
    required this.config,
    required this.positionX,
    required this.positionY,
    required this.width,
    required this.height,
    required this.isVisible,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WidgetResponse.fromJson(Map<String, dynamic> json) =>
      _$WidgetResponseFromJson(json);
  Map<String, dynamic> toJson() => _$WidgetResponseToJson(this);
}

// ============ System Models ============

@JsonSerializable()
class SystemInfo {
  final String hostname;
  @JsonKey(name: 'os_name')
  final String osName;
  @JsonKey(name: 'os_version')
  final String osVersion;
  @JsonKey(name: 'kernel_version')
  final String kernelVersion;
  final String architecture;
  final int uptime;

  SystemInfo({
    required this.hostname,
    required this.osName,
    required this.osVersion,
    required this.kernelVersion,
    required this.architecture,
    required this.uptime,
  });

  factory SystemInfo.fromJson(Map<String, dynamic> json) =>
      _$SystemInfoFromJson(json);
  Map<String, dynamic> toJson() => _$SystemInfoToJson(this);
}

@JsonSerializable()
class CpuCoreInfo {
  @JsonKey(name: 'core_id')
  final int coreId;
  final double usage;
  final int frequency;

  CpuCoreInfo({
    required this.coreId,
    required this.usage,
    required this.frequency,
  });

  factory CpuCoreInfo.fromJson(Map<String, dynamic> json) =>
      _$CpuCoreInfoFromJson(json);
  Map<String, dynamic> toJson() => _$CpuCoreInfoToJson(this);
}

@JsonSerializable()
class CpuInfo {
  final String name;
  final String vendor;
  final String brand;
  final int frequency;
  final int cores;
  final double usage;
  final double? temperature;
  @JsonKey(name: 'per_core_usage')
  final List<CpuCoreInfo>? perCoreUsage;

  CpuInfo({
    required this.name,
    required this.vendor,
    required this.brand,
    required this.frequency,
    required this.cores,
    required this.usage,
    this.temperature,
    this.perCoreUsage,
  });

  factory CpuInfo.fromJson(Map<String, dynamic> json) =>
      _$CpuInfoFromJson(json);
  Map<String, dynamic> toJson() => _$CpuInfoToJson(this);
}

@JsonSerializable()
class MemoryInfo {
  final int total;
  final int used;
  final int available;
  @JsonKey(name: 'usage_percentage')
  final double usagePercentage;
  @JsonKey(name: 'swap_total')
  final int swapTotal;
  @JsonKey(name: 'swap_used')
  final int swapUsed;

  MemoryInfo({
    required this.total,
    required this.used,
    required this.available,
    required this.usagePercentage,
    required this.swapTotal,
    required this.swapUsed,
  });

  factory MemoryInfo.fromJson(Map<String, dynamic> json) =>
      _$MemoryInfoFromJson(json);
  Map<String, dynamic> toJson() => _$MemoryInfoToJson(this);
}

@JsonSerializable()
class DiskInfo {
  final String name;
  @JsonKey(name: 'mount_point')
  final String mountPoint;
  @JsonKey(name: 'file_system')
  final String fileSystem;
  @JsonKey(name: 'total_space')
  final int totalSpace;
  @JsonKey(name: 'available_space')
  final int availableSpace;
  @JsonKey(name: 'used_space')
  final int usedSpace;
  @JsonKey(name: 'usage_percentage')
  final double usagePercentage;
  @JsonKey(name: 'is_removable')
  final bool isRemovable;
  @JsonKey(name: 'disk_type')
  final String diskType;

  DiskInfo({
    required this.name,
    required this.mountPoint,
    required this.fileSystem,
    required this.totalSpace,
    required this.availableSpace,
    required this.usedSpace,
    required this.usagePercentage,
    required this.isRemovable,
    required this.diskType,
  });

  factory DiskInfo.fromJson(Map<String, dynamic> json) =>
      _$DiskInfoFromJson(json);
  Map<String, dynamic> toJson() => _$DiskInfoToJson(this);
}

@JsonSerializable()
class DiskDetail {
  final String name;
  @JsonKey(name: 'device_path')
  final String devicePath;
  @JsonKey(name: 'mount_point')
  final String mountPoint;
  @JsonKey(name: 'file_system')
  final String fileSystem;
  @JsonKey(name: 'total_space')
  final int totalSpace;
  @JsonKey(name: 'available_space')
  final int availableSpace;
  @JsonKey(name: 'used_space')
  final int usedSpace;
  @JsonKey(name: 'usage_percentage')
  final double usagePercentage;
  @JsonKey(name: 'is_removable')
  final bool isRemovable;
  @JsonKey(name: 'disk_type')
  final String diskType;
  @JsonKey(name: 'is_mounted')
  final bool isMounted;
  @JsonKey(name: 'read_only')
  final bool readOnly;

  DiskDetail({
    required this.name,
    required this.devicePath,
    required this.mountPoint,
    required this.fileSystem,
    required this.totalSpace,
    required this.availableSpace,
    required this.usedSpace,
    required this.usagePercentage,
    required this.isRemovable,
    required this.diskType,
    required this.isMounted,
    required this.readOnly,
  });

  factory DiskDetail.fromJson(Map<String, dynamic> json) =>
      _$DiskDetailFromJson(json);
  Map<String, dynamic> toJson() => _$DiskDetailToJson(this);
}

@JsonSerializable()
class HardwareInfo {
  final SystemInfo system;
  final CpuInfo cpu;
  final MemoryInfo memory;
  final List<DiskInfo> disks;
  @JsonKey(name: 'usb_devices')
  final List<UsbDevice> usbDevices;
  @JsonKey(name: 'network_interfaces')
  final List<NetworkInterfaceInfo>? networkInterfaces;

  HardwareInfo({
    required this.system,
    required this.cpu,
    required this.memory,
    required this.disks,
    required this.usbDevices,
    this.networkInterfaces,
  });

  factory HardwareInfo.fromJson(Map<String, dynamic> json) =>
      _$HardwareInfoFromJson(json);
  Map<String, dynamic> toJson() => _$HardwareInfoToJson(this);
}

@JsonSerializable()
class NetworkInterfaceInfo {
  final String name;
  @JsonKey(name: 'mac_address')
  final String macAddress;
  @JsonKey(name: 'ip_addresses')
  final List<String> ipAddresses;
  @JsonKey(name: 'is_up')
  final bool isUp;
  @JsonKey(name: 'speed_mbps')
  final int? speedMbps;
  @JsonKey(name: 'interface_type')
  final String interfaceType;
  @JsonKey(name: 'rx_bytes')
  final int rxBytes;
  @JsonKey(name: 'tx_bytes')
  final int txBytes;

  NetworkInterfaceInfo({
    required this.name,
    required this.macAddress,
    required this.ipAddresses,
    required this.isUp,
    this.speedMbps,
    required this.interfaceType,
    required this.rxBytes,
    required this.txBytes,
  });

  factory NetworkInterfaceInfo.fromJson(Map<String, dynamic> json) =>
      _$NetworkInterfaceInfoFromJson(json);
  Map<String, dynamic> toJson() => _$NetworkInterfaceInfoToJson(this);
}

@JsonSerializable()
class UsbDevice {
  final String name;
  @JsonKey(name: 'vendor_id')
  final String vendorId;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'mount_point')
  final String? mountPoint;
  final int? size;

  UsbDevice({
    required this.name,
    required this.vendorId,
    required this.productId,
    this.mountPoint,
    this.size,
  });

  factory UsbDevice.fromJson(Map<String, dynamic> json) =>
      _$UsbDeviceFromJson(json);
  Map<String, dynamic> toJson() => _$UsbDeviceToJson(this);
}

// ============ App Store Models ============

@JsonSerializable()
class AppStoreItem {
  final String id;
  final String name;
  @JsonKey(name: 'display_name')
  final String displayName;
  final String description;
  final String icon;
  final String category;
  @JsonKey(name: 'docker_image')
  final String dockerImage;
  @JsonKey(name: 'recommended_tag')
  final String recommendedTag;
  @JsonKey(name: 'default_ports')
  final List<PortMapping> defaultPorts;
  @JsonKey(name: 'default_volumes')
  final List<VolumeMapping> defaultVolumes;
  @JsonKey(name: 'required_env')
  final List<String> requiredEnv;

  AppStoreItem({
    required this.id,
    required this.name,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.category,
    required this.dockerImage,
    required this.recommendedTag,
    required this.defaultPorts,
    required this.defaultVolumes,
    required this.requiredEnv,
  });

  factory AppStoreItem.fromJson(Map<String, dynamic> json) =>
      _$AppStoreItemFromJson(json);
  Map<String, dynamic> toJson() => _$AppStoreItemToJson(this);
}

@JsonSerializable()
class DockerApp {
  final String id;
  final String name;
  @JsonKey(name: 'display_name')
  final String displayName;
  final String description;
  final String icon;
  final String category;
  @JsonKey(name: 'docker_image')
  final String dockerImage;
  @JsonKey(name: 'docker_tag')
  final String dockerTag;
  final List<PortMapping> ports;
  final List<VolumeMapping> volumes;
  final List<EnvVar> environment;
  final String status;
  @JsonKey(name: 'container_id')
  final String? containerId;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  DockerApp({
    required this.id,
    required this.name,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.category,
    required this.dockerImage,
    required this.dockerTag,
    required this.ports,
    required this.volumes,
    required this.environment,
    required this.status,
    this.containerId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DockerApp.fromJson(Map<String, dynamic> json) =>
      _$DockerAppFromJson(json);
  Map<String, dynamic> toJson() => _$DockerAppToJson(this);
}

@JsonSerializable()
class PortMapping {
  @JsonKey(name: 'container_port')
  final int containerPort;
  @JsonKey(name: 'host_port')
  final int hostPort;
  final String protocol;

  PortMapping({
    required this.containerPort,
    required this.hostPort,
    required this.protocol,
  });

  factory PortMapping.fromJson(Map<String, dynamic> json) =>
      _$PortMappingFromJson(json);
  Map<String, dynamic> toJson() => _$PortMappingToJson(this);
}

@JsonSerializable()
class VolumeMapping {
  @JsonKey(name: 'container_path')
  final String containerPath;
  @JsonKey(name: 'host_path')
  final String hostPath;
  final String mode;

  VolumeMapping({
    required this.containerPath,
    required this.hostPath,
    required this.mode,
  });

  factory VolumeMapping.fromJson(Map<String, dynamic> json) =>
      _$VolumeMappingFromJson(json);
  Map<String, dynamic> toJson() => _$VolumeMappingToJson(this);
}

@JsonSerializable()
class EnvVar {
  final String key;
  final String value;
  final bool required;

  EnvVar({required this.key, required this.value, required this.required});

  factory EnvVar.fromJson(Map<String, dynamic> json) => _$EnvVarFromJson(json);
  Map<String, dynamic> toJson() => _$EnvVarToJson(this);
}

// ============ File Manager Models ============

@JsonSerializable()
class FileEntry {
  final String name;
  final String path;
  @JsonKey(name: 'is_directory')
  final bool isDirectory;
  final int size;
  final int modified;
  final String permissions;
  @JsonKey(name: 'mime_type')
  final String? mimeType;

  FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
    required this.permissions,
    this.mimeType,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) =>
      _$FileEntryFromJson(json);
  Map<String, dynamic> toJson() => _$FileEntryToJson(this);
}

@JsonSerializable()
class DirectoryListing {
  @JsonKey(name: 'current_path')
  final String currentPath;
  @JsonKey(name: 'parent_path')
  final String? parentPath;
  final List<FileEntry> entries;
  @JsonKey(name: 'total_size')
  final int totalSize;
  @JsonKey(name: 'total_files')
  final int totalFiles;
  @JsonKey(name: 'total_directories')
  final int totalDirectories;

  DirectoryListing({
    required this.currentPath,
    this.parentPath,
    required this.entries,
    required this.totalSize,
    required this.totalFiles,
    required this.totalDirectories,
  });

  factory DirectoryListing.fromJson(Map<String, dynamic> json) =>
      _$DirectoryListingFromJson(json);
  Map<String, dynamic> toJson() => _$DirectoryListingToJson(this);
}

@JsonSerializable()
class StorageInfo {
  @JsonKey(name: 'total_space')
  final int totalSpace;
  @JsonKey(name: 'used_space')
  final int usedSpace;
  @JsonKey(name: 'available_space')
  final int availableSpace;
  @JsonKey(name: 'usage_percentage')
  final double usagePercentage;

  StorageInfo({
    required this.totalSpace,
    required this.usedSpace,
    required this.availableSpace,
    required this.usagePercentage,
  });

  factory StorageInfo.fromJson(Map<String, dynamic> json) =>
      _$StorageInfoFromJson(json);
  Map<String, dynamic> toJson() => _$StorageInfoToJson(this);
}

// ============ File Preview Models ============

@JsonSerializable()
class FilePreviewResponse {
  final String content;
  @JsonKey(name: 'mime_type')
  final String mimeType;
  final int size;
  final bool truncated;
  final String encoding;

  FilePreviewResponse({
    required this.content,
    required this.mimeType,
    required this.size,
    required this.truncated,
    required this.encoding,
  });

  factory FilePreviewResponse.fromJson(Map<String, dynamic> json) =>
      _$FilePreviewResponseFromJson(json);
  Map<String, dynamic> toJson() => _$FilePreviewResponseToJson(this);
}

@JsonSerializable()
class MediaFileInfo {
  final String filename;
  @JsonKey(name: 'mime_type')
  final String mimeType;
  final int size;
  final double? duration;
  final int? width;
  final int? height;
  @JsonKey(name: 'video_codec')
  final String? videoCodec;
  @JsonKey(name: 'audio_codec')
  final String? audioCodec;
  final int? bitrate;
  @JsonKey(name: 'supports_streaming')
  final bool supportsStreaming;

  MediaFileInfo({
    required this.filename,
    required this.mimeType,
    required this.size,
    this.duration,
    this.width,
    this.height,
    this.videoCodec,
    this.audioCodec,
    this.bitrate,
    required this.supportsStreaming,
  });

  factory MediaFileInfo.fromJson(Map<String, dynamic> json) =>
      _$MediaFileInfoFromJson(json);
  Map<String, dynamic> toJson() => _$MediaFileInfoToJson(this);

  bool get isVideo => mimeType.startsWith('video/');
  bool get isAudio => mimeType.startsWith('audio/');
  bool get isImage => mimeType.startsWith('image/');

  String get formattedDuration {
    if (duration == null) return '--:--';
    final totalSeconds = duration!.toInt();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get resolution {
    if (width != null && height != null) {
      return '${width}x$height';
    }
    return 'Unknown';
  }
}

// ============ Utility Extensions ============

extension FileSizeFormatter on int {
  String toReadableSize() {
    if (this >= 1024 * 1024 * 1024) {
      return '${(this / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (this >= 1024 * 1024) {
      return '${(this / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (this >= 1024) {
      return '${(this / 1024).toStringAsFixed(1)} KB';
    }
    return '$this B';
  }
}

extension DurationFormatter on int {
  String toReadableDuration() {
    final hours = this ~/ 3600;
    final minutes = (this % 3600) ~/ 60;
    final seconds = this % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}

extension UptimeFormatter on int {
  String toReadableUptime() {
    final days = this ~/ 86400;
    final hours = (this % 86400) ~/ 3600;
    final minutes = (this % 3600) ~/ 60;

    if (days > 0) {
      return '${days}d ${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

extension DockerAppStatus on DockerApp {
  bool get isRunning => status == 'running';
  bool get isStopped => status == 'stopped' || status == 'exited';
  bool get isPending => status == 'pending' || status == 'starting';
}

extension MediaTypeHelper on MediaResponse {
  bool get isVideo => mediaType == 'video';
  bool get isAudio => mediaType == 'audio';
  bool get isImage => mediaType == 'image';
}

// ============ Storage Models (底层硬件访问) ============

@JsonSerializable()
class StorageDevice {
  final String id;
  final String name;
  @JsonKey(name: 'device_path')
  final String devicePath;
  @JsonKey(name: 'mount_point')
  final String? mountPoint;
  final String? label;
  final String? uuid;
  @JsonKey(name: 'file_system')
  final String? fileSystem;
  @JsonKey(name: 'total_size')
  final int totalSize;
  @JsonKey(name: 'used_size')
  final int usedSize;
  @JsonKey(name: 'available_size')
  final int availableSize;
  @JsonKey(name: 'device_type')
  final String deviceType;
  @JsonKey(name: 'is_removable')
  final bool isRemovable;
  @JsonKey(name: 'is_mounted')
  final bool isMounted;
  @JsonKey(name: 'is_readonly')
  final bool isReadonly;
  final String? vendor;
  final String? model;
  final String? serial;
  @JsonKey(name: 'bus_type')
  final String busType;

  StorageDevice({
    required this.id,
    required this.name,
    required this.devicePath,
    this.mountPoint,
    this.label,
    this.uuid,
    this.fileSystem,
    required this.totalSize,
    required this.usedSize,
    required this.availableSize,
    required this.deviceType,
    required this.isRemovable,
    required this.isMounted,
    required this.isReadonly,
    this.vendor,
    this.model,
    this.serial,
    required this.busType,
  });

  factory StorageDevice.fromJson(Map<String, dynamic> json) =>
      _$StorageDeviceFromJson(json);
  Map<String, dynamic> toJson() => _$StorageDeviceToJson(this);

  double get usagePercentage =>
      totalSize > 0 ? (usedSize / totalSize) * 100 : 0;
}

// ============ Docker Models ============

@JsonSerializable()
class DockerStatus {
  @JsonKey(name: 'docker_available')
  final bool dockerAvailable;
  @JsonKey(name: 'docker_compose_available')
  final bool dockerComposeAvailable;
  final String? version;
  final DockerInfo? info;

  DockerStatus({
    required this.dockerAvailable,
    required this.dockerComposeAvailable,
    this.version,
    this.info,
  });

  factory DockerStatus.fromJson(Map<String, dynamic> json) =>
      _$DockerStatusFromJson(json);
  Map<String, dynamic> toJson() => _$DockerStatusToJson(this);
}

@JsonSerializable()
class DockerInfo {
  final int? containers;
  @JsonKey(name: 'containers_running')
  final int? containersRunning;
  @JsonKey(name: 'containers_paused')
  final int? containersPaused;
  @JsonKey(name: 'containers_stopped')
  final int? containersStopped;
  final int? images;
  @JsonKey(name: 'storage_driver')
  final String? storageDriver;
  @JsonKey(name: 'docker_root_dir')
  final String? dockerRootDir;
  @JsonKey(name: 'os_type')
  final String? osType;
  final String? architecture;
  final int? cpus;
  final int? memory;

  DockerInfo({
    this.containers,
    this.containersRunning,
    this.containersPaused,
    this.containersStopped,
    this.images,
    this.storageDriver,
    this.dockerRootDir,
    this.osType,
    this.architecture,
    this.cpus,
    this.memory,
  });

  factory DockerInfo.fromJson(Map<String, dynamic> json) =>
      _$DockerInfoFromJson(json);
  Map<String, dynamic> toJson() => _$DockerInfoToJson(this);
}

@JsonSerializable()
class DockerContainer {
  final String id;
  final String name;
  final String image;
  @JsonKey(name: 'image_id')
  final String imageId;
  final String status;
  final String state;
  final String created;
  final List<PortBinding> ports;
  final List<VolumeBinding> volumes;
  final List<String> networks;
  final Map<String, String> labels;
  @JsonKey(name: 'cpu_usage')
  final double? cpuUsage;
  @JsonKey(name: 'memory_usage')
  final int? memoryUsage;
  @JsonKey(name: 'memory_limit')
  final int? memoryLimit;

  DockerContainer({
    required this.id,
    required this.name,
    required this.image,
    required this.imageId,
    required this.status,
    required this.state,
    required this.created,
    required this.ports,
    required this.volumes,
    required this.networks,
    required this.labels,
    this.cpuUsage,
    this.memoryUsage,
    this.memoryLimit,
  });

  factory DockerContainer.fromJson(Map<String, dynamic> json) =>
      _$DockerContainerFromJson(json);
  Map<String, dynamic> toJson() => _$DockerContainerToJson(this);

  bool get isRunning => state == 'running';
  bool get isStopped => state == 'exited' || state == 'stopped';
}

@JsonSerializable()
class PortBinding {
  @JsonKey(name: 'container_port')
  final int containerPort;
  @JsonKey(name: 'host_port')
  final int hostPort;
  final String protocol;
  @JsonKey(name: 'host_ip')
  final String? hostIp;

  PortBinding({
    required this.containerPort,
    required this.hostPort,
    required this.protocol,
    this.hostIp,
  });

  factory PortBinding.fromJson(Map<String, dynamic> json) =>
      _$PortBindingFromJson(json);
  Map<String, dynamic> toJson() => _$PortBindingToJson(this);
}

@JsonSerializable()
class VolumeBinding {
  final String source;
  final String destination;
  final String mode;

  VolumeBinding({
    required this.source,
    required this.destination,
    required this.mode,
  });

  factory VolumeBinding.fromJson(Map<String, dynamic> json) =>
      _$VolumeBindingFromJson(json);
  Map<String, dynamic> toJson() => _$VolumeBindingToJson(this);
}

@JsonSerializable()
class DockerImageInfo {
  final String id;
  final String repository;
  final String tag;
  final int size;
  final String created;

  DockerImageInfo({
    required this.id,
    required this.repository,
    required this.tag,
    required this.size,
    required this.created,
  });

  factory DockerImageInfo.fromJson(Map<String, dynamic> json) =>
      _$DockerImageInfoFromJson(json);
  Map<String, dynamic> toJson() => _$DockerImageInfoToJson(this);

  String get fullName => tag.isNotEmpty ? '$repository:$tag' : repository;
}

@JsonSerializable()
class ContainerLogs {
  final String stdout;
  final String stderr;

  ContainerLogs({required this.stdout, required this.stderr});

  factory ContainerLogs.fromJson(Map<String, dynamic> json) =>
      _$ContainerLogsFromJson(json);
  Map<String, dynamic> toJson() => _$ContainerLogsToJson(this);
}

@JsonSerializable()
class ExecResult {
  @JsonKey(name: 'exit_code')
  final int? exitCode;
  final String stdout;
  final String stderr;

  ExecResult({this.exitCode, required this.stdout, required this.stderr});

  factory ExecResult.fromJson(Map<String, dynamic> json) =>
      _$ExecResultFromJson(json);
  Map<String, dynamic> toJson() => _$ExecResultToJson(this);

  bool get success => exitCode == 0;
}

@JsonSerializable()
class ComposeApp {
  final String name;
  final String status;
  @JsonKey(name: 'compose_file')
  final String composeFile;

  ComposeApp({
    required this.name,
    required this.status,
    required this.composeFile,
  });

  factory ComposeApp.fromJson(Map<String, dynamic> json) =>
      _$ComposeAppFromJson(json);
  Map<String, dynamic> toJson() => _$ComposeAppToJson(this);

  bool get isRunning => status == 'running';
}
