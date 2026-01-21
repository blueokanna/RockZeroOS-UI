// ignore_for_file: avoid_print
// JSON 解析测试脚本
// 运行方法: dart run test_json_parsing.dart

import 'dart:convert';

void main() {
  print('🧪 开始测试 JSON 解析...\n');

  // 测试 1: 正常响应
  testNormalResponse();

  // 测试 2: null 字段
  testNullFields();

  // 测试 3: 缺失字段
  testMissingFields();

  // 测试 4: 错误响应
  testErrorResponse();

  print('\n✅ 所有测试完成！');
}

void testNormalResponse() {
  print('📝 测试 1: 正常响应');

  final json = {
    'success': true,
    'message': 'Login successful',
    'user': {
      'id': '123',
      'username': 'testuser',
      'email': 'test@example.com',
      'role': 'user',
      'created_at': '2024-01-01T00:00:00Z',
    },
    'tokens': {
      'access_token': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
      'refresh_token': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
      'token_type': 'Bearer',
      'expires_in': 7200,
    },
  };

  try {
    // 模拟解析
    final success = json['success'] as bool? ?? false;
    final message = json['message'] as String? ?? '';
    final user = json['user'] as Map<String, dynamic>?;
    final tokens = json['tokens'] as Map<String, dynamic>?;

    print('  ✅ success: $success');
    print('  ✅ message: $message');
    print('  ✅ user: ${user?['username']}');
    print('  ✅ tokens: ${tokens?['token_type']}');
  } catch (e) {
    print('  ❌ 解析失败: $e');
  }
  print('');
}

void testNullFields() {
  print('📝 测试 2: null 字段');

  final json = {
    'success': null,
    'message': null,
    'user': null,
    'tokens': null,
  };

  try {
    final success = json['success'] as bool? ?? false;
    final message = json['message'] as String? ?? '';
    final user = json['user'] as Map<String, dynamic>?;
    final tokens = json['tokens'] as Map<String, dynamic>?;

    print('  ✅ success (默认值): $success');
    print('  ✅ message (默认值): "$message"');
    print('  ✅ user: $user');
    print('  ✅ tokens: $tokens');
  } catch (e) {
    print('  ❌ 解析失败: $e');
  }
  print('');
}

void testMissingFields() {
  print('📝 测试 3: 缺失字段');

  final json = {
    'success': false,
    'message': 'Invalid credentials',
    // user 和 tokens 缺失
  };

  try {
    final success = json['success'] as bool? ?? false;
    final message = json['message'] as String? ?? '';
    final user = json['user'] as Map<String, dynamic>?;
    final tokens = json['tokens'] as Map<String, dynamic>?;

    print('  ✅ success: $success');
    print('  ✅ message: $message');
    print('  ✅ user (缺失): $user');
    print('  ✅ tokens (缺失): $tokens');
  } catch (e) {
    print('  ❌ 解析失败: $e');
  }
  print('');
}

void testErrorResponse() {
  print('📝 测试 4: 错误响应');

  final json = {
    'success': false,
    'message': 'Username or email already exists',
  };

  try {
    final success = json['success'] as bool? ?? false;
    final message = json['message'] as String? ?? '';

    print('  ✅ success: $success');
    print('  ✅ message: $message');
  } catch (e) {
    print('  ❌ 解析失败: $e');
  }
  print('');
}

// 测试实际的 JSON 字符串解析
void testJsonStringParsing() {
  print('📝 测试 5: JSON 字符串解析');

  final jsonString = '''
  {
    "success": true,
    "message": "Login successful",
    "user": {
      "id": "123",
      "username": "testuser",
      "email": "test@example.com",
      "role": "user",
      "created_at": "2024-01-01T00:00:00Z"
    },
    "tokens": {
      "access_token": "token123",
      "refresh_token": "refresh123",
      "token_type": "Bearer",
      "expires_in": 7200
    }
  }
  ''';

  try {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    final success = json['success'] as bool? ?? false;
    final message = json['message'] as String? ?? '';

    print('  ✅ 解析成功');
    print('  ✅ success: $success');
    print('  ✅ message: $message');
  } catch (e) {
    print('  ❌ 解析失败: $e');
  }
  print('');
}
