/// SAE 客户端（兼容层）
///
/// 包装 `SaeClientCurve25519`，提供 `SaeClient` 名称的访问。
/// 使得 secure_hls_player.dart 中使用 `SaeClient` 的代码无需修改。
library;

export 'sae_client_curve25519.dart' show SaeClientCurve25519;

import 'sae_client_curve25519.dart';

/// SaeClient 是 SaeClientCurve25519 的类型别名。
///
/// Secure HLS 播放器和其他服务通过此名称引用 SAE 客户端。
typedef SaeClient = SaeClientCurve25519;
