import 'dart:convert';
import 'dart:typed_data';
import 'package:hashlib/hashlib.dart' as hashlib;

/// SAE 工具函数
class SaeUtils {
  /// 将任意长度的设备ID哈希为32字节
  ///
  /// 与 Rust 端保持一致，确保设备ID总是32字节
  static Uint8List hashDeviceId(String deviceId) {
    final hash = hashlib.sha3_256.convert(utf8.encode(deviceId));
    return Uint8List.fromList(hash.bytes);
  }

  /// 从字符串创建32字节设备ID
  ///
  /// 如果输入已经是32字节的十六进制字符串，直接解码
  /// 否则使用 SHA3-256 哈希
  static Uint8List deviceIdFromString(String input) {
    // 尝试解析为十六进制
    if (input.length == 64) {
      try {
        final bytes = <int>[];
        for (int i = 0; i < input.length; i += 2) {
          bytes.add(int.parse(input.substring(i, i + 2), radix: 16));
        }
        if (bytes.length == 32) {
          return Uint8List.fromList(bytes);
        }
      } catch (_) {
        // 不是有效的十六进制，继续使用哈希
      }
    }

    // 使用 SHA3-256 哈希
    return hashDeviceId(input);
  }

  /// 将32字节设备ID转换为十六进制字符串
  static String deviceIdToHex(Uint8List deviceId) {
    if (deviceId.length != 32) {
      throw ArgumentError('Device ID must be 32 bytes');
    }
    return deviceId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 验证设备ID是否有效（32字节）
  static bool isValidDeviceId(Uint8List deviceId) {
    return deviceId.length == 32;
  }

  /// 比较两个设备ID的字典序
  ///
  /// 返回：
  /// - 负数：id1 < id2
  /// - 0：id1 == id2
  /// - 正数：id1 > id2
  static int compareDeviceIds(Uint8List id1, Uint8List id2) {
    final minLen = id1.length < id2.length ? id1.length : id2.length;
    for (int i = 0; i < minLen; i++) {
      if (id1[i] < id2[i]) return -1;
      if (id1[i] > id2[i]) return 1;
    }
    return id1.length.compareTo(id2.length);
  }

  /// 生成随机设备ID（用于测试）
  static Uint8List generateRandomDeviceId() {
    final random =
        List.generate(32, (_) => DateTime.now().microsecondsSinceEpoch % 256);
    return Uint8List.fromList(random);
  }

  /// 验证密码强度
  ///
  /// 返回：
  /// - 0: 弱密码（< 8 字符）
  /// - 1: 中等密码（8-15 字符）
  /// - 2: 强密码（>= 16 字符）
  static int checkPasswordStrength(String password) {
    if (password.length < 8) return 0;
    if (password.length < 16) return 1;
    return 2;
  }

  /// 安全地清除敏感数据
  ///
  /// 注意：Dart 的垃圾回收机制可能不会立即清除内存
  /// 这只是尽力而为的清除
  static void clearSensitiveData(Uint8List data) {
    for (int i = 0; i < data.length; i++) {
      data[i] = 0;
    }
  }

  /// 将字节数组转换为 Base64（URL 安全）
  static String toBase64Url(Uint8List bytes) {
    return base64Url.encode(bytes);
  }

  /// 从 Base64（URL 安全）解码字节数组
  static Uint8List fromBase64Url(String encoded) {
    return Uint8List.fromList(base64Url.decode(encoded));
  }
}

/// SAE 错误类型
class SaeException implements Exception {
  final String message;
  final SaeErrorType type;

  SaeException(this.message, this.type);

  @override
  String toString() => 'SaeException: $message (type: $type)';
}

/// SAE 错误类型枚举
enum SaeErrorType {
  cryptoError,
  invalidState,
  invalidCommit,
  unsupportedGroup,
  confirmVerificationFailed,
  maxSyncReached,
  invalidCredentials,
  protocolError,
  networkError,
}

/// SAE 状态枚举
enum SaeState {
  nothing,
  committed,
  confirmed,
  accepted,
}

/// SAE 配置
class SaeConfig {
  /// 最大 PWE 迭代次数
  final int maxPweLoop;

  /// PWE 偏移量迭代次数
  final int pweOffsetIterations;

  /// 最大同步重试次数
  final int maxSync;

  /// 椭圆曲线组 ID
  final int groupId;

  const SaeConfig({
    this.maxPweLoop = 40,
    this.pweOffsetIterations = 8,
    this.maxSync = 3,
    this.groupId = 19, // Curve25519
  });

  /// 默认配置
  static const SaeConfig defaultConfig = SaeConfig();

  /// 快速配置（用于测试，减少迭代次数）
  static const SaeConfig fastConfig = SaeConfig(
    maxPweLoop: 10,
    pweOffsetIterations: 4,
  );
}
