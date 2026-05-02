/// SAE 客户端兼容层
///
/// 包装 SaeClientCurve25519，并继续提供 SaeClient 这个名称，
/// 这样 Secure HLS 播放链路中的现有调用点无需改名。
library;

export 'sae_client_curve25519.dart' show SaeClientCurve25519;

import 'sae_client_curve25519.dart';

/// SaeClient 是 SaeClientCurve25519 的类型别名。
typedef SaeClient = SaeClientCurve25519;
