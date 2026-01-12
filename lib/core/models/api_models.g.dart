// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
      'id': instance.id,
      'username': instance.username,
      'email': instance.email,
      'role': instance.role,
      'created_at': instance.createdAt.toIso8601String(),
    };

TokenResponse _$TokenResponseFromJson(Map<String, dynamic> json) =>
    TokenResponse(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      tokenType: json['token_type'] as String,
      expiresIn: (json['expires_in'] as num).toInt(),
    );

Map<String, dynamic> _$TokenResponseToJson(TokenResponse instance) =>
    <String, dynamic>{
      'access_token': instance.accessToken,
      'refresh_token': instance.refreshToken,
      'token_type': instance.tokenType,
      'expires_in': instance.expiresIn,
    };

AuthResponse _$AuthResponseFromJson(Map<String, dynamic> json) => AuthResponse(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      tokens: TokenResponse.fromJson(json['tokens'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$AuthResponseToJson(AuthResponse instance) =>
    <String, dynamic>{
      'user': instance.user,
      'tokens': instance.tokens,
    };

InviteCodeResponse _$InviteCodeResponseFromJson(Map<String, dynamic> json) =>
    InviteCodeResponse(
      code: json['code'] as String,
      expiresInSeconds: (json['expires_in_seconds'] as num).toInt(),
    );

Map<String, dynamic> _$InviteCodeResponseToJson(InviteCodeResponse instance) =>
    <String, dynamic>{
      'code': instance.code,
      'expires_in_seconds': instance.expiresInSeconds,
    };

FileResponse _$FileResponseFromJson(Map<String, dynamic> json) => FileResponse(
      id: json['id'] as String,
      filename: json['filename'] as String,
      mimeType: json['mime_type'] as String,
      fileSize: (json['file_size'] as num).toInt(),
      isPublic: json['is_public'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      downloadUrl: json['download_url'] as String,
    );

Map<String, dynamic> _$FileResponseToJson(FileResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'filename': instance.filename,
      'mime_type': instance.mimeType,
      'file_size': instance.fileSize,
      'is_public': instance.isPublic,
      'created_at': instance.createdAt.toIso8601String(),
      'download_url': instance.downloadUrl,
    };

FileListResponse _$FileListResponseFromJson(Map<String, dynamic> json) =>
    FileListResponse(
      files: (json['files'] as List<dynamic>)
          .map((e) => FileResponse.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num).toInt(),
    );

Map<String, dynamic> _$FileListResponseToJson(FileListResponse instance) =>
    <String, dynamic>{
      'files': instance.files,
      'total': instance.total,
    };

MediaResponse _$MediaResponseFromJson(Map<String, dynamic> json) =>
    MediaResponse(
      id: json['id'] as String,
      title: json['title'] as String,
      mediaType: json['media_type'] as String,
      duration: (json['duration'] as num?)?.toInt(),
      fileUrl: json['file_url'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$MediaResponseToJson(MediaResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'media_type': instance.mediaType,
      'duration': instance.duration,
      'file_url': instance.fileUrl,
      'thumbnail_url': instance.thumbnailUrl,
      'created_at': instance.createdAt.toIso8601String(),
    };

MediaCodecInfo _$MediaCodecInfoFromJson(Map<String, dynamic> json) =>
    MediaCodecInfo(
      ffmpegAvailable: json['ffmpeg_available'] as bool,
      supportedVideoCodecs: (json['supported_video_codecs'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      supportedAudioCodecs: (json['supported_audio_codecs'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      hardwareAcceleration: (json['hardware_acceleration'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$MediaCodecInfoToJson(MediaCodecInfo instance) =>
    <String, dynamic>{
      'ffmpeg_available': instance.ffmpegAvailable,
      'supported_video_codecs': instance.supportedVideoCodecs,
      'supported_audio_codecs': instance.supportedAudioCodecs,
      'hardware_acceleration': instance.hardwareAcceleration,
    };

WidgetResponse _$WidgetResponseFromJson(Map<String, dynamic> json) =>
    WidgetResponse(
      id: json['id'] as String,
      widgetType: json['widget_type'] as String,
      title: json['title'] as String,
      config: json['config'] as Map<String, dynamic>,
      positionX: (json['position_x'] as num).toInt(),
      positionY: (json['position_y'] as num).toInt(),
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      isVisible: json['is_visible'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$WidgetResponseToJson(WidgetResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'widget_type': instance.widgetType,
      'title': instance.title,
      'config': instance.config,
      'position_x': instance.positionX,
      'position_y': instance.positionY,
      'width': instance.width,
      'height': instance.height,
      'is_visible': instance.isVisible,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

SystemInfo _$SystemInfoFromJson(Map<String, dynamic> json) => SystemInfo(
      hostname: json['hostname'] as String,
      osName: json['os_name'] as String,
      osVersion: json['os_version'] as String,
      kernelVersion: json['kernel_version'] as String,
      architecture: json['architecture'] as String,
      uptime: (json['uptime'] as num).toInt(),
    );

Map<String, dynamic> _$SystemInfoToJson(SystemInfo instance) =>
    <String, dynamic>{
      'hostname': instance.hostname,
      'os_name': instance.osName,
      'os_version': instance.osVersion,
      'kernel_version': instance.kernelVersion,
      'architecture': instance.architecture,
      'uptime': instance.uptime,
    };

CpuInfo _$CpuInfoFromJson(Map<String, dynamic> json) => CpuInfo(
      name: json['name'] as String,
      vendor: json['vendor'] as String,
      brand: json['brand'] as String,
      frequency: (json['frequency'] as num).toInt(),
      cores: (json['cores'] as num).toInt(),
      usage: (json['usage'] as num).toDouble(),
      temperature: (json['temperature'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$CpuInfoToJson(CpuInfo instance) => <String, dynamic>{
      'name': instance.name,
      'vendor': instance.vendor,
      'brand': instance.brand,
      'frequency': instance.frequency,
      'cores': instance.cores,
      'usage': instance.usage,
      'temperature': instance.temperature,
    };

MemoryInfo _$MemoryInfoFromJson(Map<String, dynamic> json) => MemoryInfo(
      total: (json['total'] as num).toInt(),
      used: (json['used'] as num).toInt(),
      available: (json['available'] as num).toInt(),
      usagePercentage: (json['usage_percentage'] as num).toDouble(),
      swapTotal: (json['swap_total'] as num).toInt(),
      swapUsed: (json['swap_used'] as num).toInt(),
    );

Map<String, dynamic> _$MemoryInfoToJson(MemoryInfo instance) =>
    <String, dynamic>{
      'total': instance.total,
      'used': instance.used,
      'available': instance.available,
      'usage_percentage': instance.usagePercentage,
      'swap_total': instance.swapTotal,
      'swap_used': instance.swapUsed,
    };

DiskInfo _$DiskInfoFromJson(Map<String, dynamic> json) => DiskInfo(
      name: json['name'] as String,
      mountPoint: json['mount_point'] as String,
      fileSystem: json['file_system'] as String,
      totalSpace: (json['total_space'] as num).toInt(),
      availableSpace: (json['available_space'] as num).toInt(),
      usedSpace: (json['used_space'] as num).toInt(),
      usagePercentage: (json['usage_percentage'] as num).toDouble(),
      isRemovable: json['is_removable'] as bool,
      diskType: json['disk_type'] as String,
    );

Map<String, dynamic> _$DiskInfoToJson(DiskInfo instance) => <String, dynamic>{
      'name': instance.name,
      'mount_point': instance.mountPoint,
      'file_system': instance.fileSystem,
      'total_space': instance.totalSpace,
      'available_space': instance.availableSpace,
      'used_space': instance.usedSpace,
      'usage_percentage': instance.usagePercentage,
      'is_removable': instance.isRemovable,
      'disk_type': instance.diskType,
    };

DiskDetail _$DiskDetailFromJson(Map<String, dynamic> json) => DiskDetail(
      name: json['name'] as String,
      devicePath: json['device_path'] as String,
      mountPoint: json['mount_point'] as String,
      fileSystem: json['file_system'] as String,
      totalSpace: (json['total_space'] as num).toInt(),
      availableSpace: (json['available_space'] as num).toInt(),
      usedSpace: (json['used_space'] as num).toInt(),
      usagePercentage: (json['usage_percentage'] as num).toDouble(),
      isRemovable: json['is_removable'] as bool,
      diskType: json['disk_type'] as String,
      isMounted: json['is_mounted'] as bool,
      readOnly: json['read_only'] as bool,
    );

Map<String, dynamic> _$DiskDetailToJson(DiskDetail instance) =>
    <String, dynamic>{
      'name': instance.name,
      'device_path': instance.devicePath,
      'mount_point': instance.mountPoint,
      'file_system': instance.fileSystem,
      'total_space': instance.totalSpace,
      'available_space': instance.availableSpace,
      'used_space': instance.usedSpace,
      'usage_percentage': instance.usagePercentage,
      'is_removable': instance.isRemovable,
      'disk_type': instance.diskType,
      'is_mounted': instance.isMounted,
      'read_only': instance.readOnly,
    };

HardwareInfo _$HardwareInfoFromJson(Map<String, dynamic> json) => HardwareInfo(
      system: SystemInfo.fromJson(json['system'] as Map<String, dynamic>),
      cpu: CpuInfo.fromJson(json['cpu'] as Map<String, dynamic>),
      memory: MemoryInfo.fromJson(json['memory'] as Map<String, dynamic>),
      disks: (json['disks'] as List<dynamic>)
          .map((e) => DiskInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      usbDevices: (json['usb_devices'] as List<dynamic>)
          .map((e) => UsbDevice.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$HardwareInfoToJson(HardwareInfo instance) =>
    <String, dynamic>{
      'system': instance.system,
      'cpu': instance.cpu,
      'memory': instance.memory,
      'disks': instance.disks,
      'usb_devices': instance.usbDevices,
    };

UsbDevice _$UsbDeviceFromJson(Map<String, dynamic> json) => UsbDevice(
      name: json['name'] as String,
      vendorId: json['vendor_id'] as String,
      productId: json['product_id'] as String,
      mountPoint: json['mount_point'] as String?,
      size: (json['size'] as num?)?.toInt(),
    );

Map<String, dynamic> _$UsbDeviceToJson(UsbDevice instance) => <String, dynamic>{
      'name': instance.name,
      'vendor_id': instance.vendorId,
      'product_id': instance.productId,
      'mount_point': instance.mountPoint,
      'size': instance.size,
    };

AppStoreItem _$AppStoreItemFromJson(Map<String, dynamic> json) => AppStoreItem(
      id: json['id'] as String,
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      description: json['description'] as String,
      icon: json['icon'] as String,
      category: json['category'] as String,
      dockerImage: json['docker_image'] as String,
      recommendedTag: json['recommended_tag'] as String,
      defaultPorts: (json['default_ports'] as List<dynamic>)
          .map((e) => PortMapping.fromJson(e as Map<String, dynamic>))
          .toList(),
      defaultVolumes: (json['default_volumes'] as List<dynamic>)
          .map((e) => VolumeMapping.fromJson(e as Map<String, dynamic>))
          .toList(),
      requiredEnv: (json['required_env'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$AppStoreItemToJson(AppStoreItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'display_name': instance.displayName,
      'description': instance.description,
      'icon': instance.icon,
      'category': instance.category,
      'docker_image': instance.dockerImage,
      'recommended_tag': instance.recommendedTag,
      'default_ports': instance.defaultPorts,
      'default_volumes': instance.defaultVolumes,
      'required_env': instance.requiredEnv,
    };

DockerApp _$DockerAppFromJson(Map<String, dynamic> json) => DockerApp(
      id: json['id'] as String,
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      description: json['description'] as String,
      icon: json['icon'] as String,
      category: json['category'] as String,
      dockerImage: json['docker_image'] as String,
      dockerTag: json['docker_tag'] as String,
      ports: (json['ports'] as List<dynamic>)
          .map((e) => PortMapping.fromJson(e as Map<String, dynamic>))
          .toList(),
      volumes: (json['volumes'] as List<dynamic>)
          .map((e) => VolumeMapping.fromJson(e as Map<String, dynamic>))
          .toList(),
      environment: (json['environment'] as List<dynamic>)
          .map((e) => EnvVar.fromJson(e as Map<String, dynamic>))
          .toList(),
      status: json['status'] as String,
      containerId: json['container_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$DockerAppToJson(DockerApp instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'display_name': instance.displayName,
      'description': instance.description,
      'icon': instance.icon,
      'category': instance.category,
      'docker_image': instance.dockerImage,
      'docker_tag': instance.dockerTag,
      'ports': instance.ports,
      'volumes': instance.volumes,
      'environment': instance.environment,
      'status': instance.status,
      'container_id': instance.containerId,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

PortMapping _$PortMappingFromJson(Map<String, dynamic> json) => PortMapping(
      containerPort: (json['container_port'] as num).toInt(),
      hostPort: (json['host_port'] as num).toInt(),
      protocol: json['protocol'] as String,
    );

Map<String, dynamic> _$PortMappingToJson(PortMapping instance) =>
    <String, dynamic>{
      'container_port': instance.containerPort,
      'host_port': instance.hostPort,
      'protocol': instance.protocol,
    };

VolumeMapping _$VolumeMappingFromJson(Map<String, dynamic> json) =>
    VolumeMapping(
      containerPath: json['container_path'] as String,
      hostPath: json['host_path'] as String,
      mode: json['mode'] as String,
    );

Map<String, dynamic> _$VolumeMappingToJson(VolumeMapping instance) =>
    <String, dynamic>{
      'container_path': instance.containerPath,
      'host_path': instance.hostPath,
      'mode': instance.mode,
    };

EnvVar _$EnvVarFromJson(Map<String, dynamic> json) => EnvVar(
      key: json['key'] as String,
      value: json['value'] as String,
      required: json['required'] as bool,
    );

Map<String, dynamic> _$EnvVarToJson(EnvVar instance) => <String, dynamic>{
      'key': instance.key,
      'value': instance.value,
      'required': instance.required,
    };

FileEntry _$FileEntryFromJson(Map<String, dynamic> json) => FileEntry(
      name: json['name'] as String,
      path: json['path'] as String,
      isDirectory: json['is_directory'] as bool,
      size: (json['size'] as num).toInt(),
      modified: (json['modified'] as num).toInt(),
      permissions: json['permissions'] as String,
      mimeType: json['mime_type'] as String?,
    );

Map<String, dynamic> _$FileEntryToJson(FileEntry instance) => <String, dynamic>{
      'name': instance.name,
      'path': instance.path,
      'is_directory': instance.isDirectory,
      'size': instance.size,
      'modified': instance.modified,
      'permissions': instance.permissions,
      'mime_type': instance.mimeType,
    };

DirectoryListing _$DirectoryListingFromJson(Map<String, dynamic> json) =>
    DirectoryListing(
      currentPath: json['current_path'] as String,
      parentPath: json['parent_path'] as String?,
      entries: (json['entries'] as List<dynamic>)
          .map((e) => FileEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalSize: (json['total_size'] as num).toInt(),
      totalFiles: (json['total_files'] as num).toInt(),
      totalDirectories: (json['total_directories'] as num).toInt(),
    );

Map<String, dynamic> _$DirectoryListingToJson(DirectoryListing instance) =>
    <String, dynamic>{
      'current_path': instance.currentPath,
      'parent_path': instance.parentPath,
      'entries': instance.entries,
      'total_size': instance.totalSize,
      'total_files': instance.totalFiles,
      'total_directories': instance.totalDirectories,
    };

StorageInfo _$StorageInfoFromJson(Map<String, dynamic> json) => StorageInfo(
      totalSpace: (json['total_space'] as num).toInt(),
      usedSpace: (json['used_space'] as num).toInt(),
      availableSpace: (json['available_space'] as num).toInt(),
      usagePercentage: (json['usage_percentage'] as num).toDouble(),
    );

Map<String, dynamic> _$StorageInfoToJson(StorageInfo instance) =>
    <String, dynamic>{
      'total_space': instance.totalSpace,
      'used_space': instance.usedSpace,
      'available_space': instance.availableSpace,
      'usage_percentage': instance.usagePercentage,
    };

StorageDevice _$StorageDeviceFromJson(Map<String, dynamic> json) =>
    StorageDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      devicePath: json['device_path'] as String,
      mountPoint: json['mount_point'] as String?,
      label: json['label'] as String?,
      uuid: json['uuid'] as String?,
      fileSystem: json['file_system'] as String?,
      totalSize: (json['total_size'] as num).toInt(),
      usedSize: (json['used_size'] as num).toInt(),
      availableSize: (json['available_size'] as num).toInt(),
      deviceType: json['device_type'] as String,
      isRemovable: json['is_removable'] as bool,
      isMounted: json['is_mounted'] as bool,
      isReadonly: json['is_readonly'] as bool,
      vendor: json['vendor'] as String?,
      model: json['model'] as String?,
      serial: json['serial'] as String?,
      busType: json['bus_type'] as String,
    );

Map<String, dynamic> _$StorageDeviceToJson(StorageDevice instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'device_path': instance.devicePath,
      'mount_point': instance.mountPoint,
      'label': instance.label,
      'uuid': instance.uuid,
      'file_system': instance.fileSystem,
      'total_size': instance.totalSize,
      'used_size': instance.usedSize,
      'available_size': instance.availableSize,
      'device_type': instance.deviceType,
      'is_removable': instance.isRemovable,
      'is_mounted': instance.isMounted,
      'is_readonly': instance.isReadonly,
      'vendor': instance.vendor,
      'model': instance.model,
      'serial': instance.serial,
      'bus_type': instance.busType,
    };

DockerStatus _$DockerStatusFromJson(Map<String, dynamic> json) => DockerStatus(
      dockerAvailable: json['docker_available'] as bool,
      dockerComposeAvailable: json['docker_compose_available'] as bool,
      version: json['version'] as String?,
      info: json['info'] == null
          ? null
          : DockerInfo.fromJson(json['info'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$DockerStatusToJson(DockerStatus instance) =>
    <String, dynamic>{
      'docker_available': instance.dockerAvailable,
      'docker_compose_available': instance.dockerComposeAvailable,
      'version': instance.version,
      'info': instance.info,
    };

DockerInfo _$DockerInfoFromJson(Map<String, dynamic> json) => DockerInfo(
      containers: (json['containers'] as num?)?.toInt(),
      containersRunning: (json['containers_running'] as num?)?.toInt(),
      containersPaused: (json['containers_paused'] as num?)?.toInt(),
      containersStopped: (json['containers_stopped'] as num?)?.toInt(),
      images: (json['images'] as num?)?.toInt(),
      storageDriver: json['storage_driver'] as String?,
      dockerRootDir: json['docker_root_dir'] as String?,
      osType: json['os_type'] as String?,
      architecture: json['architecture'] as String?,
      cpus: (json['cpus'] as num?)?.toInt(),
      memory: (json['memory'] as num?)?.toInt(),
    );

Map<String, dynamic> _$DockerInfoToJson(DockerInfo instance) =>
    <String, dynamic>{
      'containers': instance.containers,
      'containers_running': instance.containersRunning,
      'containers_paused': instance.containersPaused,
      'containers_stopped': instance.containersStopped,
      'images': instance.images,
      'storage_driver': instance.storageDriver,
      'docker_root_dir': instance.dockerRootDir,
      'os_type': instance.osType,
      'architecture': instance.architecture,
      'cpus': instance.cpus,
      'memory': instance.memory,
    };

DockerContainer _$DockerContainerFromJson(Map<String, dynamic> json) =>
    DockerContainer(
      id: json['id'] as String,
      name: json['name'] as String,
      image: json['image'] as String,
      imageId: json['image_id'] as String,
      status: json['status'] as String,
      state: json['state'] as String,
      created: json['created'] as String,
      ports: (json['ports'] as List<dynamic>)
          .map((e) => PortBinding.fromJson(e as Map<String, dynamic>))
          .toList(),
      volumes: (json['volumes'] as List<dynamic>)
          .map((e) => VolumeBinding.fromJson(e as Map<String, dynamic>))
          .toList(),
      networks:
          (json['networks'] as List<dynamic>).map((e) => e as String).toList(),
      labels: Map<String, String>.from(json['labels'] as Map),
      cpuUsage: (json['cpu_usage'] as num?)?.toDouble(),
      memoryUsage: (json['memory_usage'] as num?)?.toInt(),
      memoryLimit: (json['memory_limit'] as num?)?.toInt(),
    );

Map<String, dynamic> _$DockerContainerToJson(DockerContainer instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'image': instance.image,
      'image_id': instance.imageId,
      'status': instance.status,
      'state': instance.state,
      'created': instance.created,
      'ports': instance.ports,
      'volumes': instance.volumes,
      'networks': instance.networks,
      'labels': instance.labels,
      'cpu_usage': instance.cpuUsage,
      'memory_usage': instance.memoryUsage,
      'memory_limit': instance.memoryLimit,
    };

PortBinding _$PortBindingFromJson(Map<String, dynamic> json) => PortBinding(
      containerPort: (json['container_port'] as num).toInt(),
      hostPort: (json['host_port'] as num).toInt(),
      protocol: json['protocol'] as String,
      hostIp: json['host_ip'] as String?,
    );

Map<String, dynamic> _$PortBindingToJson(PortBinding instance) =>
    <String, dynamic>{
      'container_port': instance.containerPort,
      'host_port': instance.hostPort,
      'protocol': instance.protocol,
      'host_ip': instance.hostIp,
    };

VolumeBinding _$VolumeBindingFromJson(Map<String, dynamic> json) =>
    VolumeBinding(
      source: json['source'] as String,
      destination: json['destination'] as String,
      mode: json['mode'] as String,
    );

Map<String, dynamic> _$VolumeBindingToJson(VolumeBinding instance) =>
    <String, dynamic>{
      'source': instance.source,
      'destination': instance.destination,
      'mode': instance.mode,
    };

DockerImageInfo _$DockerImageInfoFromJson(Map<String, dynamic> json) =>
    DockerImageInfo(
      id: json['id'] as String,
      repository: json['repository'] as String,
      tag: json['tag'] as String,
      size: (json['size'] as num).toInt(),
      created: json['created'] as String,
    );

Map<String, dynamic> _$DockerImageInfoToJson(DockerImageInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'repository': instance.repository,
      'tag': instance.tag,
      'size': instance.size,
      'created': instance.created,
    };

ContainerLogs _$ContainerLogsFromJson(Map<String, dynamic> json) =>
    ContainerLogs(
      stdout: json['stdout'] as String,
      stderr: json['stderr'] as String,
    );

Map<String, dynamic> _$ContainerLogsToJson(ContainerLogs instance) =>
    <String, dynamic>{
      'stdout': instance.stdout,
      'stderr': instance.stderr,
    };

ExecResult _$ExecResultFromJson(Map<String, dynamic> json) => ExecResult(
      exitCode: (json['exit_code'] as num?)?.toInt(),
      stdout: json['stdout'] as String,
      stderr: json['stderr'] as String,
    );

Map<String, dynamic> _$ExecResultToJson(ExecResult instance) =>
    <String, dynamic>{
      'exit_code': instance.exitCode,
      'stdout': instance.stdout,
      'stderr': instance.stderr,
    };

ComposeApp _$ComposeAppFromJson(Map<String, dynamic> json) => ComposeApp(
      name: json['name'] as String,
      status: json['status'] as String,
      composeFile: json['compose_file'] as String,
    );

Map<String, dynamic> _$ComposeAppToJson(ComposeApp instance) =>
    <String, dynamic>{
      'name': instance.name,
      'status': instance.status,
      'compose_file': instance.composeFile,
    };
