import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum FileSystemEventType {
  fileCreated,
  fileDeleted,
  fileModified,
  fileRenamed,
  fileCopied,
  fileMoved,
  diskFormatted,
  diskMounted,
  diskUnmounted,
  directoryCreated,
  directoryDeleted,
  uploadCompleted,
  downloadCompleted,
}

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

class FileSystemMonitorService {
  static final FileSystemMonitorService _instance =
      FileSystemMonitorService._internal();
  factory FileSystemMonitorService() => _instance;
  FileSystemMonitorService._internal();

  final _eventController = StreamController<FileSystemEvent>.broadcast();

  Stream<FileSystemEvent> get eventStream => _eventController.stream;

  Stream<FileSystemEvent> listenToEventType(FileSystemEventType type) {
    return eventStream.where((event) => event.type == type);
  }

  Stream<FileSystemEvent> listenToPath(String path) {
    return eventStream.where((event) =>
        event.path == path ||
        event.oldPath == path ||
        event.newPath == path ||
        (event.path != null && event.path!.startsWith(path)));
  }

  Stream<FileSystemEvent> listenToDiskEvents() {
    return eventStream.where((event) =>
        event.type == FileSystemEventType.diskFormatted ||
        event.type == FileSystemEventType.diskMounted ||
        event.type == FileSystemEventType.diskUnmounted);
  }

  void emit(FileSystemEvent event) {
    debugPrint('[FileSystemMonitor] Event: $event');
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  void emitFileCreated(String path, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.fileCreated,
      path: path,
      metadata: metadata,
    ));
  }

  void emitFileDeleted(String path, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.fileDeleted,
      path: path,
      metadata: metadata,
    ));
  }

  void emitFileModified(String path, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.fileModified,
      path: path,
      metadata: metadata,
    ));
  }

  void emitFileRenamed(String oldPath, String newPath,
      {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.fileRenamed,
      oldPath: oldPath,
      newPath: newPath,
      metadata: metadata,
    ));
  }

  void emitFileCopied(String sourcePath, String destPath,
      {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.fileCopied,
      oldPath: sourcePath,
      newPath: destPath,
      metadata: metadata,
    ));
  }

  void emitFileMoved(String oldPath, String newPath,
      {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.fileMoved,
      oldPath: oldPath,
      newPath: newPath,
      metadata: metadata,
    ));
  }

  void emitDiskFormatted(String diskName, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.diskFormatted,
      diskName: diskName,
      metadata: metadata,
    ));
  }

  void emitDiskMounted(String diskName, String mountPoint,
      {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.diskMounted,
      diskName: diskName,
      path: mountPoint,
      metadata: metadata,
    ));
  }

  void emitDiskUnmounted(String diskName, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.diskUnmounted,
      diskName: diskName,
      metadata: metadata,
    ));
  }

  void emitDirectoryCreated(String path, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.directoryCreated,
      path: path,
      metadata: metadata,
    ));
  }

  void emitDirectoryDeleted(String path, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.directoryDeleted,
      path: path,
      metadata: metadata,
    ));
  }

  void emitUploadCompleted(String path, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.uploadCompleted,
      path: path,
      metadata: metadata,
    ));
  }

  void emitDownloadCompleted(String path, {Map<String, dynamic>? metadata}) {
    emit(FileSystemEvent(
      type: FileSystemEventType.downloadCompleted,
      path: path,
      metadata: metadata,
    ));
  }

  void dispose() {
    _eventController.close();
  }
}

final fileSystemMonitorProvider = Provider<FileSystemMonitorService>((ref) {
  final service = FileSystemMonitorService();
  ref.onDispose(() => service.dispose());
  return service;
});

final fileSystemEventStreamProvider = StreamProvider<FileSystemEvent>((ref) {
  final monitor = ref.watch(fileSystemMonitorProvider);
  return monitor.eventStream;
});
