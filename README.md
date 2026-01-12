# RockZero UI

Flutter 跨平台客户端，支持 Android、Windows、Linux 和 Web。

## 功能特性

- **Material Design 3** - 完整支持 MD3 设计规范，包括动态主题色和 Expressive 动画
- **设备自动发现** - 自动扫描局域网中的 RockZero 设备（不受 VPN 影响）
- **安全认证** - JWT 认证、FIDO2/WebAuthn 支持、零知识证明登录
- **文件管理** - 完整的文件浏览、上传、下载功能
- **媒体播放** - 支持硬件加速的视频/音频播放
- **应用商店** - Docker 应用安装和管理
- **系统监控** - 实时 CPU、内存、磁盘、USB 设备监控

## 运行

```bash
# 获取依赖
flutter pub get

# 运行 (选择平台)
flutter run -d windows
flutter run -d linux
flutter run -d android
flutter run -d chrome
```

## 构建

```bash
# Android APK
flutter build apk --release

# Windows
flutter build windows --release

# Linux
flutter build linux --release

# Web
flutter build web --release
```

## API 对接

所有 API 端点与 Rust 后端完全对齐：

- `/api/v1/auth/*` - 认证相关
- `/api/v1/files/*` - 文件管理
- `/api/v1/media/*` - 媒体管理
- `/api/v1/widgets/*` - 小组件
- `/api/v1/system/*` - 系统信息
- `/api/v1/appstore/*` - 应用商店
- `/api/v1/filemanager/*` - 文件管理器
- `/api/v1/fido/*` - FIDO2 认证
