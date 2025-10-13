/// Kadb Dart - 纯Dart实现的ADB客户端库
/// 
/// 提供完整的ADB协议实现，包括：
/// - ADB连接管理
/// - Shell命令执行
/// - 文件同步操作
/// - TCP端口转发
/// - 设备配对功能
/// 
/// 所有功能都完整复刻自Kotlin版本，确保功能一致性。
library;

// 核心协议组件
export 'core/adb_protocol.dart';
export 'core/adb_message.dart';
export 'core/adb_reader.dart';
export 'core/adb_writer.dart';
export 'core/adb_connection.dart';
export 'core/adb_message_queue.dart';

// 证书和密钥管理
export 'cert/adb_key_pair.dart';
export 'cert/cert_utils.dart';
export 'cert/key_pair_storage.dart';

// 传输通道
export 'transport/transport_channel.dart';

// 流操作
export 'stream/adb_stream.dart';
export 'stream/adb_shell_stream.dart';
export 'stream/adb_sync_stream.dart';

// 转发功能
export 'forwarding/tcp_forwarder.dart';

// 配对功能
export 'pair/pairing_connection_ctx.dart';

import 'core/adb_connection.dart';
import 'cert/adb_key_pair.dart';
import 'stream/adb_shell_stream.dart';
import 'stream/adb_sync_stream.dart';
import 'forwarding/tcp_forwarder.dart';

/// ADB客户端主类
/// 提供高级API来管理ADB连接和操作
class KadbDart {
  /// 连接到ADB服务器
  /// [host] 主机地址（默认localhost）
  /// [port] 端口号（默认5037）
  /// [keyPair] ADB密钥对（可选，自动生成）
  /// [connectTimeoutMs] 连接超时时间（毫秒）
  /// [ioTimeoutMs] IO超时时间（毫秒）
  static Future<AdbConnection> connect({
    String host = 'localhost',
    int port = 5037,
    AdbKeyPair? keyPair,
    int connectTimeoutMs = 10000,
    int ioTimeoutMs = 30000,
    bool debug = false,
  }) async {
    final actualKeyPair = keyPair ?? await AdbKeyPair.generate();
    final connection = AdbConnection(
      keyPair: actualKeyPair,
      ioTimeout: Duration(milliseconds: ioTimeoutMs),
      debug: debug,
    );
    await connection.connect(host, port);
    return connection;
  }
  
  /// 执行Shell命令
  /// [connection] ADB连接
  /// [command] Shell命令
  /// [args] 命令参数
  /// [debug] 是否启用调试模式
  static Future<AdbShellStream> executeShell(
    AdbConnection connection,
    String command, [
    List<String> args = const [],
    bool debug = false,
  ]) async {
    return AdbShellStream.execute(connection, command, args, debug);
  }
  
  /// 打开同步流
  /// [connection] ADB连接
  static Future<AdbSyncStream> openSync(AdbConnection connection) async {
    return AdbSyncStream.open(connection);
  }
  
  /// 创建TCP转发器
  /// [connection] ADB连接
  /// [hostPort] 本地端口
  /// [targetPort] 设备端口
  static TcpForwarder createTcpForwarder(AdbConnection connection, int hostPort, int targetPort) {
    return TcpForwarder(connection, hostPort, targetPort);
  }
  
  /// 创建反向TCP转发器
  /// [connection] ADB连接
  /// [devicePort] 设备端口
  /// [hostPort] 本地端口
  static ReverseTcpForwarder createReverseTcpForwarder(AdbConnection connection, int devicePort, int hostPort) {
    return ReverseTcpForwarder(connection, devicePort, hostPort);
  }
}

/// ADB Dart库的主入口点
void main() {
  print('Kadb Dart - Android Debug Bridge Dart实现');
  print('版本: 1.0.0');
  print('使用示例:');
  print('  final kadb = KadbDart();');
  print('  await kadb.connect("localhost", 5037);');
}