// ignore_for_file: avoid_print
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 测试 Dashboard API 调用
///
/// 使用方法:
/// dart run test_dashboard_api.dart
void main() async {
  print('🧪 Dashboard API 测试工具\n');

  final storage = const FlutterSecureStorage();
  final dio = Dio(BaseOptions(
    baseUrl: 'http://localhost:8080',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  // 1. 测试健康检查
  print('1️⃣ 测试健康检查...');
  try {
    final response = await dio.get('/health');
    print('   ✅ 健康检查成功: ${response.statusCode}');
  } catch (e) {
    print('   ❌ 健康检查失败: $e');
    print('   ⚠️  请确保后端服务正在运行 (cargo run)');
    exit(1);
  }

  // 2. 测试登录
  print('\n2️⃣ 测试登录...');
  String? accessToken;
  try {
    final response = await dio.post('/api/v1/auth/login', data: {
      'username': 'test@example.com',
      'password': 'Test1234',
    });

    if (response.statusCode == 200) {
      final data = response.data;
      accessToken = data['tokens']?['access_token'];

      if (accessToken != null) {
        print('   ✅ 登录成功');
        print('   🔑 Access Token: ${accessToken.substring(0, 20)}...');

        // 保存到 secure storage
        await storage.write(key: 'access_token', value: accessToken);
        print('   💾 Token 已保存到 Secure Storage');
      } else {
        print('   ❌ 登录响应中没有 access_token');
        print('   响应数据: $data');
        exit(1);
      }
    }
  } catch (e) {
    print('   ❌ 登录失败: $e');
    if (e is DioException) {
      print('   响应数据: ${e.response?.data}');
    }
    print('   ⚠️  请确保用户已注册 (test@example.com / Test1234)');
    exit(1);
  }

  // 3. 测试系统 API (不带 token)
  print('\n3️⃣ 测试系统 API (不带认证)...');
  try {
    final response = await dio.get('/api/v1/system/all');
    if (response.statusCode == 200) {
      print('   ✅ 系统 API 无需认证即可访问');
      final data = response.data;
      print('   📊 CPU: ${data['cpu']?['name']}');
      print(
          '   💾 内存: ${(data['memory']?['total'] ?? 0) / 1024 / 1024 / 1024} GB');
    }
  } catch (e) {
    print('   ⚠️  系统 API 需要认证: $e');
  }

  // 4. 测试系统 API (带 token)
  print('\n4️⃣ 测试系统 API (带认证)...');
  if (accessToken != null) {
    try {
      final response = await dio.get(
        '/api/v1/system/all',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );

      if (response.statusCode == 200) {
        print('   ✅ 系统 API 调用成功');
        final data = response.data;

        // 显示详细信息
        print('\n   📊 系统信息:');
        print('   ├─ 主机名: ${data['system']?['hostname']}');
        print(
            '   ├─ 操作系统: ${data['system']?['os_name']} ${data['system']?['os_version']}');
        print('   ├─ 架构: ${data['system']?['architecture']}');

        print('\n   🖥️  CPU 信息:');
        print('   ├─ 型号: ${data['cpu']?['name']}');
        print('   ├─ 核心数: ${data['cpu']?['cores']}');
        print('   ├─ 使用率: ${data['cpu']?['usage']?.toStringAsFixed(1)}%');

        print('\n   💾 内存信息:');
        final totalMem = (data['memory']?['total'] ?? 0) / 1024 / 1024 / 1024;
        final usedMem = (data['memory']?['used'] ?? 0) / 1024 / 1024 / 1024;
        print('   ├─ 总量: ${totalMem.toStringAsFixed(2)} GB');
        print('   ├─ 已用: ${usedMem.toStringAsFixed(2)} GB');
        print(
            '   ├─ 使用率: ${data['memory']?['usage_percentage']?.toStringAsFixed(1)}%');

        print('\n   💿 磁盘信息:');
        final disks = data['disks'] as List?;
        if (disks != null && disks.isNotEmpty) {
          for (var disk in disks) {
            final totalSpace = (disk['total_space'] ?? 0) / 1024 / 1024 / 1024;
            final usedSpace = (disk['used_space'] ?? 0) / 1024 / 1024 / 1024;
            print(
                '   ├─ ${disk['name']}: ${usedSpace.toStringAsFixed(1)}/${totalSpace.toStringAsFixed(1)} GB (${disk['usage_percentage']?.toStringAsFixed(1)}%)');
          }
        }

        print('\n   🌐 网络接口:');
        final interfaces = data['network_interfaces'] as List?;
        if (interfaces != null && interfaces.isNotEmpty) {
          for (var iface in interfaces) {
            final rxMB = (iface['rx_bytes'] ?? 0) / 1024 / 1024;
            final txMB = (iface['tx_bytes'] ?? 0) / 1024 / 1024;
            print(
                '   ├─ ${iface['name']}: ↓${rxMB.toStringAsFixed(1)} MB ↑${txMB.toStringAsFixed(1)} MB');
          }
        }
      }
    } catch (e) {
      print('   ❌ 系统 API 调用失败: $e');
      if (e is DioException) {
        print('   状态码: ${e.response?.statusCode}');
        print('   响应数据: ${e.response?.data}');
      }
      exit(1);
    }
  }

  // 5. 测试磁盘 API
  print('\n5️⃣ 测试磁盘 API...');
  if (accessToken != null) {
    try {
      final response = await dio.get(
        '/api/v1/system/disks',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );

      if (response.statusCode == 200) {
        print('   ✅ 磁盘 API 调用成功');
        final disks = response.data as List;
        print('   💿 找到 ${disks.length} 个磁盘');
      }
    } catch (e) {
      print('   ❌ 磁盘 API 调用失败: $e');
    }
  }

  // 6. 测试网络 API
  print('\n6️⃣ 测试网络 API...');
  if (accessToken != null) {
    try {
      final response = await dio.get(
        '/api/v1/system/network',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );

      if (response.statusCode == 200) {
        print('   ✅ 网络 API 调用成功');
        final interfaces = response.data as List;
        print('   🌐 找到 ${interfaces.length} 个网络接口');
      }
    } catch (e) {
      print('   ❌ 网络 API 调用失败: $e');
    }
  }

  print('\n✅ 所有测试完成！');
  print('\n📝 下一步:');
  print('   1. 如果所有测试通过，说明后端 API 工作正常');
  print('   2. 运行 Flutter 应用: flutter run');
  print('   3. 登录后查看 Dashboard 是否正常显示');
  print('   4. 检查 Flutter 控制台日志，查找 [Auth] 和 [Dashboard] 标记');
}
