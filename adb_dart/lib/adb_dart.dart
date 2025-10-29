/// 纯Dart实现的Android Debug Bridge (ADB)协议库
///
/// 这个库完整复刻了Kadb的功能，实现了完整的ADB协议栈，包括：
/// - ADB连接建立和认证
/// - RSA密钥管理和Android格式转换
/// - 文件推送/拉取（SYNC协议）
/// - Shell命令执行（v2协议）
/// - APK安装/卸载
/// - TCP端口转发
/// - WiFi设备配对
///
/// 使用示例：
/// ```dart
/// import 'package:adb_dart/adb_dart.dart';
///
/// void main() async {
///   final adb = Kadb('localhost', 5555);
///
///   // 执行shell命令
///   final response = await adb.shell('ls -la /sdcard');
///   print('输出: ${response.output}');
///   print('错误: ${response.errorOutput}');
///   print('退出码: ${response.exitCode}');
///
///   // 推送文件
///   await adb.push(File('local.txt'), '/sdcard/remote.txt');
///
///   // 拉取文件
///   await adb.pull(File('local_copy.txt'), '/sdcard/remote.txt');
///
///   adb.close();
/// }
/// ```
library adb_dart;

// 核心协议
export 'src/core/adb_protocol.dart';
export 'src/core/adb_message.dart';
export 'src/core/adb_connection.dart' hide AdbStream;

// 证书和密钥
export 'src/cert/adb_key_pair.dart';
export 'src/cert/android_pubkey.dart';
export 'src/cert/cert_utils.dart';

// 传输层
export 'src/transport/transport_channel.dart';
export 'src/transport/tls_transport_channel.dart';

// 流管理
export 'src/stream/adb_stream.dart';

// 转发
export 'src/forwarding/tcp_forwarder.dart';

// 配对
export 'src/pair/pairing_connection_ctx.dart';
export 'src/stream/adb_sync_stream.dart';
export 'src/stream/adb_shell_stream.dart';

// 主类
export 'src/adb_dart.dart';

// 异常
export 'src/exception/adb_exceptions.dart';

// Shell响应
export 'src/shell/adb_shell_response.dart';
