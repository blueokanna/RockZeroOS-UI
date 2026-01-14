import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Download task status
enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

/// Download task model
class DownloadTask {
  final String id;
  final String url;
  final String fileName;
  final String savePath;
  int totalBytes;
  int downloadedBytes;
  DownloadStatus status;
  String? error;
  DateTime createdAt;
  DateTime? completedAt;

  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savePath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = DownloadStatus.pending,
    this.error,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0;

  String get progressText {
    if (totalBytes == 0) return '0%';
    return '${(progress * 100).toStringAsFixed(1)}%';
  }

  String get sizeText {
    if (totalBytes == 0) return 'Unknown size';
    return '${_formatBytes(downloadedBytes)} / ${_formatBytes(totalBytes)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'savePath': savePath,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        'status': status.index,
        'error': error,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String,
      url: json['url'] as String,
      fileName: json['fileName'] as String,
      savePath: json['savePath'] as String,
      totalBytes: (json['totalBytes'] as int?) ?? 0,
      downloadedBytes: (json['downloadedBytes'] as int?) ?? 0,
      status: DownloadStatus.values[(json['status'] as int?) ?? 0],
      error: json['error'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
    );
  }
}

/// Upload task model
class UploadTask {
  final String id;
  final String filePath;
  final String fileName;
  final String uploadUrl;
  final int totalBytes;
  int uploadedBytes;
  DownloadStatus status;
  String? error;
  DateTime createdAt;
  DateTime? completedAt;

  UploadTask({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.uploadUrl,
    this.totalBytes = 0,
    this.uploadedBytes = 0,
    this.status = DownloadStatus.pending,
    this.error,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get progress => totalBytes > 0 ? uploadedBytes / totalBytes : 0;

  String get progressText {
    if (totalBytes == 0) return '0%';
    return '${(progress * 100).toStringAsFixed(1)}%';
  }
}

/// Download manager state
class DownloadManagerState {
  final List<DownloadTask> downloads;
  final List<UploadTask> uploads;
  final int maxConcurrentDownloads;

  const DownloadManagerState({
    this.downloads = const [],
    this.uploads = const [],
    this.maxConcurrentDownloads = 3,
  });

  DownloadManagerState copyWith({
    List<DownloadTask>? downloads,
    List<UploadTask>? uploads,
    int? maxConcurrentDownloads,
  }) {
    return DownloadManagerState(
      downloads: downloads ?? this.downloads,
      uploads: uploads ?? this.uploads,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
    );
  }

  int get activeDownloads =>
      downloads.where((d) => d.status == DownloadStatus.downloading).length;

  int get activeUploads =>
      uploads.where((u) => u.status == DownloadStatus.downloading).length;

  List<DownloadTask> get pendingDownloads =>
      downloads.where((d) => d.status == DownloadStatus.pending).toList();

  List<DownloadTask> get completedDownloads =>
      downloads.where((d) => d.status == DownloadStatus.completed).toList();
}

/// Download manager notifier with resume support
class DownloadManagerNotifier extends Notifier<DownloadManagerState> {
  final Map<String, StreamSubscription> _downloadSubscriptions = {};
  final Map<String, http.Client> _httpClients = {};
  String? _authToken;

  @override
  DownloadManagerState build() {
    _loadAuthToken();
    _loadPersistedTasks();
    return const DownloadManagerState();
  }

  Future<void> _loadAuthToken() async {
    const storage = FlutterSecureStorage();
    _authToken = await storage.read(key: 'access_token');
  }

  Future<void> _loadPersistedTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = prefs.getStringList('download_tasks') ?? [];
      final tasks = tasksJson
          .map((json) => DownloadTask.fromJson(
              Map<String, dynamic>.from(Uri.splitQueryString(json))))
          .toList();

      // Resume incomplete downloads
      for (final task in tasks) {
        if (task.status == DownloadStatus.downloading) {
          task.status = DownloadStatus.paused;
        }
      }

      state = state.copyWith(downloads: tasks);
    } catch (e) {
      debugPrint('Failed to load persisted tasks: $e');
    }
  }

  Future<void> _persistTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = state.downloads
          .map((task) => Uri(
              queryParameters: task.toJson().map(
                    (key, value) => MapEntry(key, value?.toString() ?? ''),
                  )).query)
          .toList();
      await prefs.setStringList('download_tasks', tasksJson);
    } catch (e) {
      debugPrint('Failed to persist tasks: $e');
    }
  }

  /// Get download directory
  Future<Directory> getDownloadDirectory() async {
    Directory? downloadDir;
    if (Platform.isAndroid) {
      downloadDir = Directory('/storage/emulated/0/Download/RockZeroDownload');
    } else if (Platform.isIOS) {
      final docDir = await getApplicationDocumentsDirectory();
      downloadDir = Directory('${docDir.path}/RockZeroDownload');
    } else {
      final docDir = await getDownloadsDirectory();
      if (docDir != null) {
        downloadDir = Directory('${docDir.path}/RockZeroDownload');
      }
    }

    downloadDir ??= await getApplicationDocumentsDirectory();

    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    return downloadDir;
  }

  /// Add a new download task
  Future<DownloadTask> addDownload({
    required String url,
    required String fileName,
    String? customPath,
  }) async {
    final downloadDir = await getDownloadDirectory();
    final savePath = customPath ?? '${downloadDir.path}/$fileName';

    final task = DownloadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      fileName: fileName,
      savePath: savePath,
    );

    state = state.copyWith(downloads: [...state.downloads, task]);
    await _persistTasks();

    // Start download if under limit
    if (state.activeDownloads < state.maxConcurrentDownloads) {
      _startDownload(task);
    }

    return task;
  }

  /// Start or resume a download
  Future<void> _startDownload(DownloadTask task) async {
    final index = state.downloads.indexWhere((d) => d.id == task.id);
    if (index == -1) {
      return;
    }

    final file = File(task.savePath);
    int startByte = 0;

    // Check for existing partial download
    if (await file.exists()) {
      startByte = await file.length();
      task.downloadedBytes = startByte;
    }

    task.status = DownloadStatus.downloading;
    _updateTask(task);

    try {
      final client = http.Client();
      _httpClients[task.id] = client;

      final request = http.Request('GET', Uri.parse(task.url));

      // Add auth header
      if (_authToken != null && _authToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $_authToken';
      }

      // Add range header for resume support
      if (startByte > 0) {
        request.headers['Range'] = 'bytes=$startByte-';
      }

      final response = await client.send(request);

      // Get total size
      if (task.totalBytes == 0) {
        final contentLength = response.contentLength ?? 0;
        if (response.statusCode == 206) {
          // Partial content - parse Content-Range header
          final contentRange = response.headers['content-range'];
          if (contentRange != null) {
            final match =
                RegExp(r'bytes \d+-\d+/(\d+)').firstMatch(contentRange);
            if (match != null) {
              task.totalBytes = int.parse(match.group(1)!);
            }
          }
        } else {
          task.totalBytes = contentLength + startByte;
        }
        _updateTask(task);
      }

      // Open file for writing
      final sink = file.openWrite(
          mode: startByte > 0 ? FileMode.append : FileMode.write);

      // Download with progress tracking
      _downloadSubscriptions[task.id] = response.stream.listen(
        (chunk) {
          sink.add(chunk);
          task.downloadedBytes += chunk.length;
          _updateTask(task);
        },
        onDone: () async {
          await sink.close();
          task.status = DownloadStatus.completed;
          task.completedAt = DateTime.now();
          _updateTask(task);
          _cleanup(task.id);
          _startNextPendingDownload();
        },
        onError: (error) async {
          await sink.close();
          task.status = DownloadStatus.failed;
          task.error = error.toString();
          _updateTask(task);
          _cleanup(task.id);
          _startNextPendingDownload();
        },
        cancelOnError: true,
      );
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.error = e.toString();
      _updateTask(task);
      _cleanup(task.id);
      _startNextPendingDownload();
    }
  }

  /// Pause a download
  void pauseDownload(String taskId) {
    final index = state.downloads.indexWhere((d) => d.id == taskId);
    if (index == -1) {
      return;
    }

    final task = state.downloads[index];
    if (task.status != DownloadStatus.downloading) {
      return;
    }

    _downloadSubscriptions[taskId]?.cancel();
    _httpClients[taskId]?.close();
    _cleanup(taskId);

    task.status = DownloadStatus.paused;
    _updateTask(task);
    _startNextPendingDownload();
  }

  /// Resume a paused download
  void resumeDownload(String taskId) {
    final index = state.downloads.indexWhere((d) => d.id == taskId);
    if (index == -1) {
      return;
    }

    final task = state.downloads[index];
    if (task.status != DownloadStatus.paused &&
        task.status != DownloadStatus.failed) {
      return;
    }

    if (state.activeDownloads < state.maxConcurrentDownloads) {
      _startDownload(task);
    } else {
      task.status = DownloadStatus.pending;
      _updateTask(task);
    }
  }

  /// Cancel a download
  void cancelDownload(String taskId) {
    final index = state.downloads.indexWhere((d) => d.id == taskId);
    if (index == -1) {
      return;
    }

    final task = state.downloads[index];

    _downloadSubscriptions[taskId]?.cancel();
    _httpClients[taskId]?.close();
    _cleanup(taskId);

    // Delete partial file
    final file = File(task.savePath);
    if (file.existsSync()) {
      file.deleteSync();
    }

    task.status = DownloadStatus.cancelled;
    _updateTask(task);
    _startNextPendingDownload();
  }

  /// Remove a download from the list
  void removeDownload(String taskId) {
    cancelDownload(taskId);
    state = state.copyWith(
      downloads: state.downloads.where((d) => d.id != taskId).toList(),
    );
    _persistTasks();
  }

  /// Clear completed downloads
  void clearCompleted() {
    state = state.copyWith(
      downloads: state.downloads
          .where((d) => d.status != DownloadStatus.completed)
          .toList(),
    );
    _persistTasks();
  }

  void _updateTask(DownloadTask task) {
    final downloads = List<DownloadTask>.from(state.downloads);
    final index = downloads.indexWhere((d) => d.id == task.id);
    if (index != -1) {
      downloads[index] = task;
      state = state.copyWith(downloads: downloads);
      _persistTasks();
    }
  }

  void _cleanup(String taskId) {
    _downloadSubscriptions.remove(taskId);
    _httpClients.remove(taskId);
  }

  void _startNextPendingDownload() {
    if (state.activeDownloads >= state.maxConcurrentDownloads) {
      return;
    }

    final pending = state.pendingDownloads;
    if (pending.isNotEmpty) {
      _startDownload(pending.first);
    }
  }

  /// Add upload task
  Future<UploadTask> addUpload({
    required String filePath,
    required String uploadUrl,
  }) async {
    final file = File(filePath);
    final fileName = filePath.split('/').last;
    final fileSize = await file.length();

    final task = UploadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      filePath: filePath,
      fileName: fileName,
      uploadUrl: uploadUrl,
      totalBytes: fileSize,
    );

    state = state.copyWith(uploads: [...state.uploads, task]);
    return task;
  }

  /// Update upload progress
  void updateUploadProgress(String taskId, int uploadedBytes) {
    final uploads = List<UploadTask>.from(state.uploads);
    final index = uploads.indexWhere((u) => u.id == taskId);
    if (index != -1) {
      uploads[index].uploadedBytes = uploadedBytes;
      state = state.copyWith(uploads: uploads);
    }
  }

  /// Complete upload
  void completeUpload(String taskId) {
    final uploads = List<UploadTask>.from(state.uploads);
    final index = uploads.indexWhere((u) => u.id == taskId);
    if (index != -1) {
      uploads[index].status = DownloadStatus.completed;
      uploads[index].completedAt = DateTime.now();
      state = state.copyWith(uploads: uploads);
    }
  }

  /// Fail upload
  void failUpload(String taskId, String error) {
    final uploads = List<UploadTask>.from(state.uploads);
    final index = uploads.indexWhere((u) => u.id == taskId);
    if (index != -1) {
      uploads[index].status = DownloadStatus.failed;
      uploads[index].error = error;
      state = state.copyWith(uploads: uploads);
    }
  }

  /// Remove upload
  void removeUpload(String taskId) {
    state = state.copyWith(
      uploads: state.uploads.where((u) => u.id != taskId).toList(),
    );
  }
}

/// Provider for download manager
final downloadManagerProvider =
    NotifierProvider<DownloadManagerNotifier, DownloadManagerState>(
  DownloadManagerNotifier.new,
);
