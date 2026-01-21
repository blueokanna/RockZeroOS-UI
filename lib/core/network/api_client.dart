import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';

import '../services/device_discovery_service.dart';

final _logger = Logger(printer: PrettyPrinter(methodCount: 0));

// Secure storage provider
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
});

// API client provider
final apiClientProvider = Provider<ApiClient>((ref) {
  final device = ref.watch(connectedDeviceProvider);
  final storage = ref.watch(secureStorageProvider);
  return ApiClient(device: device, storage: storage, ref: ref);
});

// Dio instance provider
final dioProvider = Provider<Dio>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return apiClient.dio;
});

// Base URL provider for accessing the server URL
final baseUrlProvider = Provider<String>((ref) {
  final device = ref.watch(connectedDeviceProvider);
  return device?.baseUrl ?? '';
});

class ApiClient {
  final DiscoveredDevice? device;
  final FlutterSecureStorage storage;
  final Ref ref;
  late final Dio dio;

  ApiClient({required this.device, required this.storage, required this.ref}) {
    dio = _createDio();
  }

  Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: device?.baseUrl ?? '',
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 5), // 增加接收超时到5分钟
        sendTimeout: const Duration(minutes: 30), // 增加发送超时到30分钟（用于大文件上传）
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        // Ensure proper UTF-8 encoding for query parameters
        listFormat: ListFormat.multiCompatible,
      ),
    );

    // Allow self-signed certificates (non-web platforms only)
    if (!kIsWeb && device?.isSecure == true) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient()
          ..badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    }

    // Add interceptors
    dio.interceptors.addAll([
      _AuthInterceptor(storage, ref),
      if (kDebugMode) _LoggingInterceptor(),
      _ErrorInterceptor(),
    ]);

    return dio;
  }

  void updateBaseUrl(String baseUrl) {
    dio.options.baseUrl = baseUrl;
  }
}

class _AuthInterceptor extends Interceptor {
  final FlutterSecureStorage storage;
  final Ref ref;

  static const _publicPaths = [
    '/health',
    '/api/v1/auth/login',
    '/api/v1/auth/register',
    '/api/v1/fido/auth/start',
    '/api/v1/fido/auth/finish',
  ];

  _AuthInterceptor(this.storage, this.ref);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    debugPrint('🌐 [Auth] 请求: ${options.method} ${options.path}');

    // Skip auth for public endpoints
    if (_publicPaths.any((path) => options.path.contains(path))) {
      debugPrint('   ℹ️  [Auth] 公开端点，跳过认证');
      return handler.next(options);
    }

    // Add access token
    final accessToken = await storage.read(key: 'access_token');
    if (accessToken != null) {
      debugPrint(
          '   🔑 [Auth] 添加 Access Token: ${accessToken.substring(0, 20)}...');
      options.headers['Authorization'] = 'Bearer $accessToken';
    } else {
      debugPrint('   ⚠️  [Auth] 警告: 没有 Access Token');
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // Try to refresh token
      final refreshed = await _refreshToken();
      if (refreshed) {
        // Retry the request
        try {
          final accessToken = await storage.read(key: 'access_token');
          err.requestOptions.headers['Authorization'] = 'Bearer $accessToken';

          final response = await Dio().fetch(err.requestOptions);
          return handler.resolve(response);
        } catch (_) {}
      }
    }
    handler.next(err);
  }

  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await storage.read(key: 'refresh_token');
      if (refreshToken == null) return false;

      final device = ref.read(connectedDeviceProvider);
      if (device == null) return false;

      final dio = Dio()..options.baseUrl = device.baseUrl;

      if (!kIsWeb && device.isSecure) {
        (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
          return HttpClient()
            ..badCertificateCallback = (cert, host, port) => true;
        };
      }

      final response = await dio.post(
        '/api/v1/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        await storage.write(key: 'access_token', value: data['access_token']);
        await storage.write(key: 'refresh_token', value: data['refresh_token']);
        return true;
      }
    } catch (_) {}
    return false;
  }
}

class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logger.d('🌐 ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _logger.d('✅ ${response.statusCode} ${response.requestOptions.uri}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logger.e(
      '❌ ${err.response?.statusCode} ${err.requestOptions.uri}\n   ${err.message}',
    );
    handler.next(err);
  }
}

class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final error = ApiException.fromDioException(err);
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: error,
      ),
    );
  }
}

// API Exception
class ApiException implements Exception {
  final String message;
  final String? errorCode;
  final int? statusCode;
  final dynamic details;

  ApiException({
    required this.message,
    this.errorCode,
    this.statusCode,
    this.details,
  });

  factory ApiException.fromDioException(DioException err) {
    String message = 'An error occurred';
    String? errorCode;
    int? statusCode = err.response?.statusCode;

    if (err.response?.data is Map) {
      final data = err.response!.data as Map;
      message = data['message'] ?? message;
      errorCode = data['error'];
    } else {
      switch (err.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          message = 'Connection timeout';
          break;
        case DioExceptionType.connectionError:
          message = 'Connection failed';
          break;
        case DioExceptionType.cancel:
          message = 'Request cancelled';
          break;
        default:
          message = err.message ?? message;
      }
    }

    return ApiException(
      message: message,
      errorCode: errorCode,
      statusCode: statusCode,
    );
  }

  @override
  String toString() => message;
}
