/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// 传输通道异常
class TransportException implements Exception {
  final String message;
  final dynamic cause;

  TransportException(this.message, [this.cause]);

  @override
  String toString() =>
      'TransportException: $message${cause != null ? ' (caused by: $cause)' : ''}';
}

/// 传输通道接口，抽象底层传输实现
abstract class TransportChannel {
  /// 检查通道是否打开
  bool get isOpen;

  /// 关闭通道
  Future<void> close();

  /// 读取数据
  Future<Uint8List> read(int maxSize);

  /// 写入数据
  Future<int> write(Uint8List data);

  /// 刷新输出缓冲区
  Future<void> flush();

  /// 获取数据流
  Stream<Uint8List> get dataStream;

  /// 获取完成Future
  Future<void> get done;

  /// 远程地址
  InternetAddress? get remoteAddress;

  /// 远程端口
  int? get remotePort;

  /// 本地地址
  InternetAddress? get localAddress;

  /// 本地端口
  int? get localPort;

  /// 读取超时
  Duration get readTimeout;

  /// 写入超时
  Duration get writeTimeout;

  /// 设置Socket选项
  void setSocketOption(SocketOption option, bool enabled);

  /// 销毁通道
  Future<void> destroy();
}
