// 登录调试工具
// 在 main.dart 中导入并调用 debugLogin() 来测试

import 'dart:convert';
import 'dart:io';

Future<void> debugLogin({
  required String baseUrl,
  required String username,
  required String password,
}) async {
  print('🔍 开始调试登录...');
  print('📍 Base URL: $baseUrl');
  print('👤 Username: $username');
  print('');

  // 步骤 1: 测试健康检查
  print('📝 步骤 1: 测试健康检查端点');
  try {
    final healthUrl = '$baseUrl/health';
    print('   请求: GET $healthUrl');

    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) =>
          true..connectionTimeout = const Duration(seconds: 5);

    final request = await client.getUrl(Uri.parse(healthUrl));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    print('   响应状态: ${response.statusCode}');
    print('   响应内容: $body');

    if (response.statusCode == 200) {
      print('   ✅ 健康检查成功');
    } else {
      print('   ❌ 健康检查失败');
      return;
    }

    client.close();
  } catch (e) {
    print('   ❌ 健康检查异常: $e');
    return;
  }

  print('');

  // 步骤 2: 测试登录端点
  print('📝 步骤 2: 测试登录端点');
  try {
    final loginUrl = '$baseUrl/api/v1/auth/login';
    print('   请求: POST $loginUrl');

    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) =>
          true..connectionTimeout = const Duration(seconds: 10);

    final request = await client.postUrl(Uri.parse(loginUrl));
    request.headers.set('Content-Type', 'application/json; charset=utf-8');
    request.headers.set('Accept', 'application/json');

    final requestBody = jsonEncode({
      'username': username,
      'password': password,
    });

    print('   请求体: $requestBody');
    request.write(requestBody);

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    print('   响应状态: ${response.statusCode}');
    print('   响应头:');
    response.headers.forEach((name, values) {
      print('     $name: ${values.join(', ')}');
    });
    print('   响应内容: $body');

    if (response.statusCode == 200) {
      print('   ✅ 登录请求成功');

      // 解析响应
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        print('');
        print('   📊 解析后的响应:');
        print('     success: ${json['success']}');
        print('     message: ${json['message']}');
        print('     user: ${json['user'] != null ? '存在' : 'null'}');
        print('     tokens: ${json['tokens'] != null ? '存在' : 'null'}');

        if (json['user'] != null) {
          final user = json['user'] as Map<String, dynamic>;
          print('');
          print('   👤 用户信息:');
          print('     id: ${user['id']}');
          print('     username: ${user['username']}');
          print('     email: ${user['email']}');
          print('     role: ${user['role']}');
          print('     created_at: ${user['created_at']}');
        }

        if (json['tokens'] != null) {
          final tokens = json['tokens'] as Map<String, dynamic>;
          print('');
          print('   🔑 Token 信息:');
          print(
              '     access_token: ${tokens['access_token']?.toString().substring(0, 20)}...');
          print(
              '     refresh_token: ${tokens['refresh_token']?.toString().substring(0, 20)}...');
          print('     token_type: ${tokens['token_type']}');
          print('     expires_in: ${tokens['expires_in']}');
        }
      } catch (e) {
        print('   ❌ JSON 解析失败: $e');
      }
    } else {
      print('   ❌ 登录请求失败');
    }

    client.close();
  } catch (e) {
    print('   ❌ 登录请求异常: $e');
    print('   堆栈跟踪: ${StackTrace.current}');
  }

  print('');
  print('🏁 调试完成');
}

// 测试注册端点
Future<void> debugRegister({
  required String baseUrl,
  required String username,
  required String email,
  required String password,
}) async {
  print('🔍 开始调试注册...');
  print('📍 Base URL: $baseUrl');
  print('👤 Username: $username');
  print('📧 Email: $email');
  print('');

  try {
    final registerUrl = '$baseUrl/api/v1/auth/register';
    print('   请求: POST $registerUrl');

    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) =>
          true..connectionTimeout = const Duration(seconds: 10);

    final request = await client.postUrl(Uri.parse(registerUrl));
    request.headers.set('Content-Type', 'application/json; charset=utf-8');
    request.headers.set('Accept', 'application/json');

    final requestBody = jsonEncode({
      'username': username,
      'email': email,
      'password': password,
    });

    print('   请求体: $requestBody');
    request.write(requestBody);

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    print('   响应状态: ${response.statusCode}');
    print('   响应内容: $body');

    if (response.statusCode == 200) {
      print('   ✅ 注册请求成功');

      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        print('');
        print('   📊 解析后的响应:');
        print('     success: ${json['success']}');
        print('     message: ${json['message']}');
      } catch (e) {
        print('   ❌ JSON 解析失败: $e');
      }
    } else {
      print('   ❌ 注册请求失败');
    }

    client.close();
  } catch (e) {
    print('   ❌ 注册请求异常: $e');
  }

  print('');
  print('🏁 调试完成');
}
