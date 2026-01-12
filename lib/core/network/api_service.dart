import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import 'api_client.dart';

// API Service Provider
final apiServiceProvider = Provider<ApiService>((ref) {
  final dio = ref.watch(dioProvider);
  return ApiService(dio);
});

class ApiService {
  final Dio _dio;

  ApiService(this._dio);

  // ============ Generic HTTP Methods ============

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  // ============ Auth API ============

  Future<AuthResponse> register({
    required String username,
    required String email,
    required String password,
    String? inviteCode,
  }) async {
    final response = await _dio.post(
      '/api/v1/auth/register',
      data: {
        'username': username,
        'email': email,
        'password': password,
        if (inviteCode != null) 'invite_code': inviteCode,
      },
    );
    return AuthResponse.fromJson(response.data);
  }

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(
      '/api/v1/auth/login',
      data: {'email': email, 'password': password},
    );
    return AuthResponse.fromJson(response.data);
  }

  Future<TokenResponse> refreshToken(String refreshToken) async {
    final response = await _dio.post(
      '/api/v1/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    return TokenResponse.fromJson(response.data);
  }

  Future<InviteCodeResponse> generateInviteCode() async {
    final response = await _dio.post('/api/v1/auth/invite');
    return InviteCodeResponse.fromJson(response.data);
  }

  // ============ Files API ============

  Future<List<FileResponse>> uploadFiles(
    List<File> files, {
    void Function(int, int)? onProgress,
  }) async {
    final formData = FormData();
    for (final file in files) {
      formData.files.add(
        MapEntry(
          'file',
          await MultipartFile.fromFile(
            file.path,
            filename: file.path.split('/').last,
          ),
        ),
      );
    }

    final response = await _dio.post(
      '/api/v1/files',
      data: formData,
      onSendProgress: onProgress,
    );

    return (response.data as List)
        .map((e) => FileResponse.fromJson(e))
        .toList();
  }

  Future<FileListResponse> listFiles() async {
    final response = await _dio.get('/api/v1/files');
    return FileListResponse.fromJson(response.data);
  }

  Future<void> deleteFile(String id) async {
    await _dio.delete('/api/v1/files/$id');
  }

  String getFileDownloadUrl(String id) {
    return '${_dio.options.baseUrl}/api/v1/files/$id/download';
  }

  // ============ Media API ============

  Future<List<MediaResponse>> listMedia() async {
    final response = await _dio.get('/api/v1/media');
    return (response.data as List)
        .map((e) => MediaResponse.fromJson(e))
        .toList();
  }

  Future<MediaResponse> createMedia({
    required String fileId,
    required String title,
    required String mediaType,
    String? thumbnailId,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await _dio.post(
      '/api/v1/media',
      data: {
        'file_id': fileId,
        'title': title,
        'media_type': mediaType,
        if (thumbnailId != null) 'thumbnail_id': thumbnailId,
        if (metadata != null) 'metadata': metadata,
      },
    );
    return MediaResponse.fromJson(response.data);
  }

  Future<MediaCodecInfo> getCodecInfo() async {
    final response = await _dio.get('/api/v1/media/codecs');
    return MediaCodecInfo.fromJson(response.data);
  }

  Future<void> transcodeMedia({
    required String fileId,
    required String outputFormat,
    String? videoCodec,
    String? audioCodec,
    String? bitrate,
    String? resolution,
  }) async {
    await _dio.post(
      '/api/v1/media/transcode',
      data: {
        'file_id': fileId,
        'output_format': outputFormat,
        if (videoCodec != null) 'video_codec': videoCodec,
        if (audioCodec != null) 'audio_codec': audioCodec,
        if (bitrate != null) 'bitrate': bitrate,
        if (resolution != null) 'resolution': resolution,
      },
    );
  }

  // ============ Widgets API ============

  Future<List<WidgetResponse>> listWidgets() async {
    final response = await _dio.get('/api/v1/widgets');
    return (response.data as List)
        .map((e) => WidgetResponse.fromJson(e))
        .toList();
  }

  Future<WidgetResponse> createWidget({
    required String widgetType,
    required String title,
    required Map<String, dynamic> config,
    required int positionX,
    required int positionY,
    required int width,
    required int height,
  }) async {
    final response = await _dio.post(
      '/api/v1/widgets',
      data: {
        'widget_type': widgetType,
        'title': title,
        'config': config,
        'position_x': positionX,
        'position_y': positionY,
        'width': width,
        'height': height,
      },
    );
    return WidgetResponse.fromJson(response.data);
  }

  Future<WidgetResponse> updateWidget(
    String id, {
    String? title,
    Map<String, dynamic>? config,
    int? positionX,
    int? positionY,
    int? width,
    int? height,
    bool? isVisible,
  }) async {
    final response = await _dio.put(
      '/api/v1/widgets/$id',
      data: {
        if (title != null) 'title': title,
        if (config != null) 'config': config,
        if (positionX != null) 'position_x': positionX,
        if (positionY != null) 'position_y': positionY,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (isVisible != null) 'is_visible': isVisible,
      },
    );
    return WidgetResponse.fromJson(response.data);
  }

  Future<void> deleteWidget(String id) async {
    await _dio.delete('/api/v1/widgets/$id');
  }

  // ============ System API ============

  Future<SystemInfo> getSystemInfo() async {
    final response = await _dio.get('/api/v1/system/info');
    return SystemInfo.fromJson(response.data);
  }

  Future<CpuInfo> getCpuInfo() async {
    final response = await _dio.get('/api/v1/system/cpu');
    return CpuInfo.fromJson(response.data);
  }

  Future<MemoryInfo> getMemoryInfo() async {
    final response = await _dio.get('/api/v1/system/memory');
    return MemoryInfo.fromJson(response.data);
  }

  Future<List<DiskInfo>> getDiskInfo() async {
    final response = await _dio.get('/api/v1/system/disks');
    return (response.data as List).map((e) => DiskInfo.fromJson(e)).toList();
  }

  Future<List<UsbDevice>> getUsbDevices() async {
    final response = await _dio.get('/api/v1/system/usb');
    return (response.data as List).map((e) => UsbDevice.fromJson(e)).toList();
  }

  Future<HardwareInfo> getHardwareInfo() async {
    final response = await _dio.get('/api/v1/system/hardware');
    return HardwareInfo.fromJson(response.data);
  }

  // ============ Disk Manager API ============

  Future<List<DiskDetail>> listDisks() async {
    final response = await _dio.get('/api/v1/disk/list');
    return (response.data as List).map((e) => DiskDetail.fromJson(e)).toList();
  }

  Future<Map<String, dynamic>> getPartitions() async {
    final response = await _dio.get('/api/v1/disk/partitions');
    return response.data;
  }

  Future<void> mountDisk({
    required String device,
    required String mountPoint,
    String? fileSystem,
  }) async {
    await _dio.post(
      '/api/v1/disk/mount',
      data: {
        'device': device,
        'mount_point': mountPoint,
        if (fileSystem != null) 'file_system': fileSystem,
      },
    );
  }

  Future<void> unmountDisk(String device) async {
    await _dio.post('/api/v1/disk/unmount', data: {'device': device});
  }

  Future<void> formatDisk({
    required String device,
    required String fileSystem,
    String? label,
  }) async {
    await _dio.post(
      '/api/v1/disk/format',
      data: {
        'device': device,
        'file_system': fileSystem,
        if (label != null) 'label': label,
      },
    );
  }

  Future<Map<String, dynamic>> checkDiskHealth(String device) async {
    final response = await _dio.get('/api/v1/disk/health/$device');
    return response.data;
  }

  Future<void> ejectDisk(String device) async {
    await _dio.post('/api/v1/disk/eject/$device');
  }

  // ============ App Store API ============

  Future<List<AppStoreItem>> listStoreApps() async {
    final response = await _dio.get('/api/v1/appstore/apps');
    return (response.data as List)
        .map((e) => AppStoreItem.fromJson(e))
        .toList();
  }

  Future<List<DockerApp>> listInstalledApps() async {
    final response = await _dio.get('/api/v1/appstore/installed');
    return (response.data as List).map((e) => DockerApp.fromJson(e)).toList();
  }

  Future<DockerApp> installApp({
    required String name,
    required String dockerImage,
    String? dockerTag,
    required List<PortMapping> ports,
    required List<VolumeMapping> volumes,
    required List<EnvVar> environment,
  }) async {
    final response = await _dio.post(
      '/api/v1/appstore/install',
      data: {
        'name': name,
        'docker_image': dockerImage,
        if (dockerTag != null) 'docker_tag': dockerTag,
        'ports': ports.map((e) => e.toJson()).toList(),
        'volumes': volumes.map((e) => e.toJson()).toList(),
        'environment': environment.map((e) => e.toJson()).toList(),
      },
    );
    return DockerApp.fromJson(response.data);
  }

  Future<void> uninstallApp(String id) async {
    await _dio.delete('/api/v1/appstore/uninstall/$id');
  }

  Future<void> startApp(String id) async {
    await _dio.post('/api/v1/appstore/start/$id');
  }

  Future<void> stopApp(String id) async {
    await _dio.post('/api/v1/appstore/stop/$id');
  }

  Future<void> restartApp(String id) async {
    await _dio.post('/api/v1/appstore/restart/$id');
  }

  // ============ File Manager API ============

  Future<DirectoryListing> listDirectory({
    String? path,
    String? sortBy,
    String? order,
  }) async {
    final response = await _dio.get(
      '/api/v1/filemanager/list',
      queryParameters: {
        if (path != null) 'path': path,
        if (sortBy != null) 'sort_by': sortBy,
        if (order != null) 'order': order,
      },
    );
    return DirectoryListing.fromJson(response.data);
  }

  Future<void> createDirectory({
    required String path,
    required String name,
  }) async {
    await _dio.post(
      '/api/v1/filemanager/mkdir',
      data: {'path': path, 'name': name},
    );
  }

  Future<void> uploadToDirectory(
    String path,
    List<File> files, {
    void Function(int, int)? onProgress,
  }) async {
    final formData = FormData();
    for (final file in files) {
      formData.files.add(
        MapEntry(
          'file',
          await MultipartFile.fromFile(
            file.path,
            filename: file.path.split('/').last,
          ),
        ),
      );
    }

    await _dio.post(
      '/api/v1/filemanager/upload',
      data: formData,
      queryParameters: {'path': path},
      onSendProgress: onProgress,
    );
  }

  Future<void> renameFile({
    required String oldPath,
    required String newName,
  }) async {
    await _dio.post(
      '/api/v1/filemanager/rename',
      data: {'old_path': oldPath, 'new_name': newName},
    );
  }

  Future<void> moveFiles({
    required String source,
    required String destination,
  }) async {
    await _dio.post(
      '/api/v1/filemanager/move',
      data: {'source': source, 'destination': destination},
    );
  }

  Future<void> copyFiles({
    required String source,
    required String destination,
  }) async {
    await _dio.post(
      '/api/v1/filemanager/copy',
      data: {'source': source, 'destination': destination},
    );
  }

  Future<void> deleteFiles(List<String> paths) async {
    await _dio.post('/api/v1/filemanager/delete', data: {'paths': paths});
  }

  Future<StorageInfo> getStorageInfo() async {
    final response = await _dio.get('/api/v1/filemanager/storage');
    return StorageInfo.fromJson(response.data);
  }

  String getFileManagerDownloadUrl(String path) {
    return '${_dio.options.baseUrl}/api/v1/filemanager/download?path=$path';
  }

  // ============ WebDAV API ============

  String getWebDavUrl() {
    return '${_dio.options.baseUrl}/webdav';
  }

  Future<List<WebDavEntry>> webdavList(String path) async {
    final response = await _dio.request(
      '/webdav/$path',
      options: Options(method: 'PROPFIND', headers: {'Depth': '1'}),
    );
    // 解析 XML 响应
    return _parseWebDavResponse(response.data);
  }

  Future<void> webdavCreateFolder(String path) async {
    await _dio.request('/webdav/$path', options: Options(method: 'MKCOL'));
  }

  Future<void> webdavDelete(String path) async {
    await _dio.delete('/webdav/$path');
  }

  Future<void> webdavMove(String source, String destination) async {
    await _dio.request(
      '/webdav/$source',
      options: Options(
        method: 'MOVE',
        headers: {'Destination': '${_dio.options.baseUrl}/webdav/$destination'},
      ),
    );
  }

  Future<void> webdavCopy(String source, String destination) async {
    await _dio.request(
      '/webdav/$source',
      options: Options(
        method: 'COPY',
        headers: {'Destination': '${_dio.options.baseUrl}/webdav/$destination'},
      ),
    );
  }

  List<WebDavEntry> _parseWebDavResponse(dynamic data) {
    // 简化的 WebDAV 响应解析
    return [];
  }

  // ============ Streaming API ============

  Future<Map<String, dynamic>> getSupportedFormats() async {
    final response = await _dio.get('/api/v1/streaming/formats');
    return response.data;
  }

  Future<List<MediaLibraryEntry>> listMediaLibrary({String? path}) async {
    final response = await _dio.get(
      '/api/v1/streaming/library',
      queryParameters: path != null ? {'path': path} : null,
    );
    return (response.data as List)
        .map((e) => MediaLibraryEntry.fromJson(e))
        .toList();
  }

  Future<MediaStreamInfo> getMediaStreamInfo(String path) async {
    final response = await _dio.get('/api/v1/streaming/info/$path');
    return MediaStreamInfo.fromJson(response.data);
  }

  String getStreamUrl(String path) {
    return '${_dio.options.baseUrl}/api/v1/streaming/play/$path';
  }

  String getHlsPlaylistUrl(String path) {
    return '${_dio.options.baseUrl}/api/v1/streaming/hls/$path';
  }

  String getThumbnailUrl(String path, {double? timestamp}) {
    final url = '${_dio.options.baseUrl}/api/v1/streaming/thumbnail/$path';
    if (timestamp != null) {
      return '$url?quality=$timestamp';
    }
    return url;
  }

  // ============ Storage API (底层硬件访问) ============

  Future<List<StorageDevice>> listStorageDevices() async {
    final response = await _dio.get('/api/v1/storage/devices');
    return (response.data as List)
        .map((e) => StorageDevice.fromJson(e))
        .toList();
  }

  Future<StorageDevice> getStorageDevice(String id) async {
    final response = await _dio.get('/api/v1/storage/devices/$id');
    return StorageDevice.fromJson(response.data);
  }

  Future<void> mountStorage({
    required String device,
    required String mountPoint,
    String? fileSystem,
    List<String>? options,
    bool? readOnly,
  }) async {
    await _dio.post(
      '/api/v1/storage/mount',
      data: {
        'device': device,
        'mount_point': mountPoint,
        if (fileSystem != null) 'file_system': fileSystem,
        if (options != null) 'options': options,
        if (readOnly != null) 'read_only': readOnly,
      },
    );
  }

  Future<void> unmountStorage(String device) async {
    await _dio.post('/api/v1/storage/unmount/$device');
  }

  Future<void> formatStorage({
    required String device,
    required String fileSystem,
    String? label,
    bool? quick,
  }) async {
    await _dio.post(
      '/api/v1/storage/format',
      data: {
        'device': device,
        'file_system': fileSystem,
        if (label != null) 'label': label,
        if (quick != null) 'quick': quick,
      },
    );
  }

  Future<void> ejectStorage(String device) async {
    await _dio.post('/api/v1/storage/eject/$device');
  }

  Future<List<int>> readStorageFile(String path) async {
    final response = await _dio.get<List<int>>(
      '/api/v1/storage/read/$path',
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? [];
  }

  Future<void> writeStorageFile({
    required String path,
    required String content,
    bool? createDirs,
    bool? append,
  }) async {
    await _dio.post(
      '/api/v1/storage/write',
      data: {
        'path': path,
        'content': content,
        if (createDirs != null) 'create_dirs': createDirs,
        if (append != null) 'append': append,
      },
    );
  }

  Future<void> deleteStoragePath(String path) async {
    await _dio.delete('/api/v1/storage/delete/$path');
  }

  // ============ Docker API ============

  Future<DockerStatus> getDockerStatus() async {
    final response = await _dio.get('/api/v1/docker/status');
    return DockerStatus.fromJson(response.data);
  }

  Future<void> installDocker() async {
    await _dio.post('/api/v1/docker/install');
  }

  Future<void> uninstallDocker() async {
    await _dio.post('/api/v1/docker/uninstall');
  }

  Future<List<DockerContainer>> listContainers() async {
    final response = await _dio.get('/api/v1/docker/containers');
    return (response.data as List)
        .map((e) => DockerContainer.fromJson(e))
        .toList();
  }

  Future<DockerContainer> getContainer(String id) async {
    final response = await _dio.get('/api/v1/docker/containers/$id');
    return DockerContainer.fromJson(response.data);
  }

  Future<DockerContainer> createContainer({
    required String name,
    required String image,
    String? tag,
    List<PortBinding>? ports,
    List<VolumeBinding>? volumes,
    Map<String, String>? environment,
    String? restartPolicy,
    String? network,
    bool? privileged,
    List<String>? capAdd,
    List<String>? devices,
    List<String>? command,
    Map<String, String>? labels,
    String? memoryLimit,
    double? cpuLimit,
  }) async {
    final response = await _dio.post(
      '/api/v1/docker/containers',
      data: {
        'name': name,
        'image': image,
        if (tag != null) 'tag': tag,
        if (ports != null) 'ports': ports.map((e) => e.toJson()).toList(),
        if (volumes != null) 'volumes': volumes.map((e) => e.toJson()).toList(),
        if (environment != null) 'environment': environment,
        if (restartPolicy != null) 'restart_policy': restartPolicy,
        if (network != null) 'network': network,
        if (privileged != null) 'privileged': privileged,
        if (capAdd != null) 'cap_add': capAdd,
        if (devices != null) 'devices': devices,
        if (command != null) 'command': command,
        if (labels != null) 'labels': labels,
        if (memoryLimit != null) 'memory_limit': memoryLimit,
        if (cpuLimit != null) 'cpu_limit': cpuLimit,
      },
    );
    return DockerContainer.fromJson(response.data);
  }

  Future<DockerContainer> updateContainer(
    String id, {
    List<PortBinding>? ports,
    List<VolumeBinding>? volumes,
    Map<String, String>? environment,
    String? restartPolicy,
    String? memoryLimit,
    double? cpuLimit,
  }) async {
    final response = await _dio.put(
      '/api/v1/docker/containers/$id',
      data: {
        if (ports != null) 'ports': ports.map((e) => e.toJson()).toList(),
        if (volumes != null) 'volumes': volumes.map((e) => e.toJson()).toList(),
        if (environment != null) 'environment': environment,
        if (restartPolicy != null) 'restart_policy': restartPolicy,
        if (memoryLimit != null) 'memory_limit': memoryLimit,
        if (cpuLimit != null) 'cpu_limit': cpuLimit,
      },
    );
    return DockerContainer.fromJson(response.data);
  }

  Future<void> startContainer(String id) async {
    await _dio.post('/api/v1/docker/containers/$id/start');
  }

  Future<void> stopContainer(String id) async {
    await _dio.post('/api/v1/docker/containers/$id/stop');
  }

  Future<void> restartContainer(String id) async {
    await _dio.post('/api/v1/docker/containers/$id/restart');
  }

  Future<void> removeContainer(String id) async {
    await _dio.delete('/api/v1/docker/containers/$id');
  }

  Future<ContainerLogs> getContainerLogs(
    String id, {
    int? tail,
    bool? timestamps,
  }) async {
    final response = await _dio.get(
      '/api/v1/docker/containers/$id/logs',
      queryParameters: {
        if (tail != null) 'tail': tail,
        if (timestamps != null) 'timestamps': timestamps,
      },
    );
    return ContainerLogs.fromJson(response.data);
  }

  Future<Map<String, dynamic>> getContainerStats(String id) async {
    final response = await _dio.get('/api/v1/docker/containers/$id/stats');
    return response.data;
  }

  Future<ExecResult> execInContainer(
    String id, {
    required List<String> command,
    String? workdir,
    String? user,
  }) async {
    final response = await _dio.post(
      '/api/v1/docker/containers/$id/exec',
      data: {
        'command': command,
        if (workdir != null) 'workdir': workdir,
        if (user != null) 'user': user,
      },
    );
    return ExecResult.fromJson(response.data);
  }

  Future<List<DockerImageInfo>> listDockerImages() async {
    final response = await _dio.get('/api/v1/docker/images');
    return (response.data as List)
        .map((e) => DockerImageInfo.fromJson(e))
        .toList();
  }

  Future<void> pullDockerImage(String image, {String? tag}) async {
    await _dio.post(
      '/api/v1/docker/images/pull',
      data: {'image': image, if (tag != null) 'tag': tag},
    );
  }

  Future<void> removeDockerImage(String id) async {
    await _dio.delete('/api/v1/docker/images/$id');
  }

  // Docker Compose
  Future<List<ComposeApp>> listComposeApps() async {
    final response = await _dio.get('/api/v1/docker/compose');
    return (response.data as List).map((e) => ComposeApp.fromJson(e)).toList();
  }

  Future<void> deployComposeApp({
    required String name,
    required String composeContent,
    Map<String, String>? envVars,
  }) async {
    await _dio.post(
      '/api/v1/docker/compose',
      data: {
        'name': name,
        'compose_content': composeContent,
        if (envVars != null) 'env_vars': envVars,
      },
    );
  }

  Future<void> startComposeApp(String name) async {
    await _dio.post('/api/v1/docker/compose/$name/start');
  }

  Future<void> stopComposeApp(String name) async {
    await _dio.post('/api/v1/docker/compose/$name/stop');
  }

  Future<void> removeComposeApp(String name) async {
    await _dio.delete('/api/v1/docker/compose/$name');
  }
}

// WebDAV Entry Model
class WebDavEntry {
  final String href;
  final String displayName;
  final bool isCollection;
  final int contentLength;
  final String contentType;
  final String lastModified;

  WebDavEntry({
    required this.href,
    required this.displayName,
    required this.isCollection,
    required this.contentLength,
    required this.contentType,
    required this.lastModified,
  });

  factory WebDavEntry.fromJson(Map<String, dynamic> json) {
    return WebDavEntry(
      href: json['href'] ?? '',
      displayName: json['display_name'] ?? '',
      isCollection: json['is_collection'] ?? false,
      contentLength: json['content_length'] ?? 0,
      contentType: json['content_type'] ?? '',
      lastModified: json['last_modified'] ?? '',
    );
  }
}

// Media Library Entry Model
class MediaLibraryEntry {
  final String id;
  final String title;
  final String path;
  final double? duration;
  final String? thumbnail;

  MediaLibraryEntry({
    required this.id,
    required this.title,
    required this.path,
    this.duration,
    this.thumbnail,
  });

  factory MediaLibraryEntry.fromJson(Map<String, dynamic> json) {
    return MediaLibraryEntry(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      path: json['path'] ?? '',
      duration: json['duration']?.toDouble(),
      thumbnail: json['thumbnail'],
    );
  }
}

// Media Stream Info Model
class MediaStreamInfo {
  final String filename;
  final String contentType;
  final int size;
  final double? duration;
  final int? width;
  final int? height;
  final String? videoCodec;
  final String? audioCodec;
  final int? bitrate;
  final bool supportsRange;

  MediaStreamInfo({
    required this.filename,
    required this.contentType,
    required this.size,
    this.duration,
    this.width,
    this.height,
    this.videoCodec,
    this.audioCodec,
    this.bitrate,
    required this.supportsRange,
  });

  factory MediaStreamInfo.fromJson(Map<String, dynamic> json) {
    return MediaStreamInfo(
      filename: json['filename'] ?? '',
      contentType: json['content_type'] ?? '',
      size: json['size'] ?? 0,
      duration: json['duration']?.toDouble(),
      width: json['width'],
      height: json['height'],
      videoCodec: json['video_codec'],
      audioCodec: json['audio_codec'],
      bitrate: json['bitrate'],
      supportsRange: json['supports_range'] ?? false,
    );
  }
}
