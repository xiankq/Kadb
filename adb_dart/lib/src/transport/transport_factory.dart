/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:async';
import 'transport_channel.dart';
import 'socket_transport_channel.dart';

/// 传输工厂，创建传输通道实例
class TransportFactory {
  /// 创建传输通道
  static Future<TransportChannel> connect({
    required String host,
    required int port,
    Duration connectTimeout = const Duration(seconds: 10),
  }) async {
    // 默认使用Socket传输
    return await SocketTransportFactory.connect(
      host: host,
      port: port,
      connectTimeout: connectTimeout,
    );
  }
}
