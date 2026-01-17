import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 文件系统事件类型
enum FileSystemEventType {
  fileCreated, // 文件创建
  fileDeleted, // 文件删除
  fileModified, // 文件修改
  fileRenamed, // 文件重命名
  fileCopied, // 文件复制
  fileMoved, // 文件移动
  diskFormatted, // 磁盘格式化
  diskMounted, // 磁盘挂载
  diskUnmounted, // 磁盘卸载
  directoryCreated, // 目录创建
  directoryDeleted, // 目录删除
  uploadCompleted, // 上传完成
  downloadCompleted, // 下载完成
}

/// 文件系统事件
class FileSystemEvent {
  final FileSystemEventType type;
  final String? path;
  final String? oldPath;
  final String? newPath;
  final String? diskName;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  FileSystemEvent({
    required this.type,
    this.path,
    this.oldPath,
    this.newPath,
    this.diskName,
    DateTime? timestamp,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'FileSystemEvent(type: $type, path: $path, oldPath: $oldPath, newPath: $newPath, diskName: $diskName)';
  }
}

/// 文件系统监视器服务
/// 提供全局文件系统事件监听和广播功能
class FileSystemMonitorService {
  static final FileSystemMonitorService _instance =
      FileSystemMonitorService._internal();
  factory FileSystemMonitorService() => _instance;
  FileSystemMonitorService._internal();

  // 事件流控制器
  final _eventController = StreamController<FileSystemEvent>.broadcast();

  // 事件流
  Stream<FileSystemEvent> get eventStream => _eventController.stream;

  // 监听特定类型的事件
  Stream<FileSystemEvent> listenToEventType(FileSystemEventType type) {
    return eventStream.where((event) => event.type == type);
  }

  // 监听特定路径的事件
  Stream<FileSystemEvent> listenToPath(String path) {
    return eventStream.where((event) =>
        event.path == path ||
        event.oldPath == path ||
        event.newPath == path ||
        (event.path != null && event.path!.startsWith(path)));
  }

  // 监听磁盘相关事件
  Stream<FileSystemEvent> listenToDiskEvents() {
    return eventStream.where((event) =>
        event.type == FileSystemEventType.diskFormatted ||
        event.type == FileSystemEventType.diskMounted ||
        event.type == FileSystemEventType.diskUnmounted);
  }

  // 发送事件
  void emit(FileSystemEvent event) {
    debugPrint('[FileSystemMonitor] Event: $event');
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  // 便捷方法：文件创建
  void emitFileCreated(String path, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.fileCreated,
      path: path,
      metadata: metadata,
    ));
  }

  // 便捷方法：文件删除
  void emitFileDeleted(String path, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.fileDeleted,
      path: path,
      metadata: metadata,
    ));
  }

  // 便捷方法：文件修改
  void emitFileModified(String path, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.fileModified,
      path: path,
      metadata: metadata,
    ));
  }

  // 便捷方法：文件重命名
  void emitFileRenamed(String oldPath, String newPath,
      {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.fileRenamed,
      oldPath: oldPath,
      newPath: newPath,
      metadata: metadata,
    ));
  }

  // 便捷方法：文件复制
  void emitFileCopied(String sourcePath, String destPath,
      {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.fileCopied,
      oldPath: sourcePath,
      newPath: destPath,
      metadata: metadata,
    ));
  }

  // 便捷方法：文件移动
  void emitFileMoved(String oldPath, String newPath,
      {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.fileMoved,
      oldPath: oldPath,
      newPath: newPath,
      metadata: metadata,
    ));
  }

  // 便捷方法：磁盘格式化
  void emitDiskFormatted(String diskName, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.diskFormatted,
      diskName: diskName,
      metadata: metadata,
    ));
  }

  // 便捷方法：磁盘挂载
  void emitDiskMounted(String diskName, String mountPoint,
      {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.diskMounted,
      diskName: diskName,
      path: mountPoint,
      metadata: metadata,
    ));
  }

  // 便捷方法：磁盘卸载
  void emitDiskUnmounted(String diskName, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.diskUnmounted,
      diskName: diskName,
      metadata: metadata,
    ));
  }

  // 便捷方法：目录创建
  void emitDirectoryCreated(String path, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.directoryCreated,
      path: path,
      metadata: metadata,
    ));
  }

  // 便捷方法：目录删除
  void emitDirectoryDeleted(String path, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.directoryDeleted,
      path: path,
      metadata: metadata,
    ));
  }

  // 便捷方法：上传完成
  void emitUploadCompleted(String path, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.uploadCompleted,
      path: path,
      metadata: metadata,
    ));
  }

  // 便捷方法：下载完成
  void emitDownloadCompleted(String path, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.downloadCompleted,
      path: path,
      metadata: metadata,
    ));
  }

  // 清理资源
  void dispose() {
    _eventController.close();
  }
}

/// Riverpod Provider
final fileSystemMonitorProvider = Provider<FileSystemMonitorService>((ref) {
  final service = FileSystemMonitorService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// 文件系统事件流 Provider
final fileSystemEventStreamProvider = StreamProvider<FileSystemEvent>((ref) {
  final monitor = ref.watch(fileSystemMonitorProvider);
  return monitor.eventStream;
});
