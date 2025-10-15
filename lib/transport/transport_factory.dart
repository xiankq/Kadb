import 'dart:io';
import 'transport_channel.dart';

/// 传输工厂类
/// 负责创建传输通道
class TransportFactory {
  /// 连接到指定主机和端口
  static Future<TransportChannel> connect(
    String host,
    int port,
    int connectTimeoutMs,
  ) async {
    // 使用Socket连接
    final socket = await Socket.connect(host, port);
    return SocketTransportChannel(socket);
  }
}
