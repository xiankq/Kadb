/// 传输层抽象接口
///
/// 定义了ADB连接所需的底层传输功能
/// 支持TCP、TLS等不同传输方式的统一接口
library;

import 'dart:async';
import 'dart:typed_data';

/// 传输通道状态枚举
enum TransportState {
  /// 连接已建立
  connected,

  /// 连接已关闭
  closed,

  /// 连接出错
  error,
}

/// 传输通道异常
class TransportException implements Exception {
  final String message;
  final Object? cause;

  TransportException(this.message, {this.cause});

  @override
  String toString() {
    if (cause != null) {
      return '传输错误: $message (原因: $cause)';
    }
    return '传输错误: $message';
  }
}

/// 传输通道抽象接口
///
/// 提供双向数据传输功能，支持同步和异步操作
abstract class TransportChannel {
  /// 本地地址
  String get localAddress;

  /// 远程地址
  String get remoteAddress;

  /// 本地端口
  int get localPort;

  /// 远程端口
  int get remotePort;

  /// 通道是否打开
  bool get isOpen;

  /// 通道状态
  TransportState get state;

  /// 读取数据流到缓冲区
  ///
  /// [buffer] 目标缓冲区
  /// [length] 要读取的最大字节数
  /// [timeout] 超时时间（可选）
  ///
  /// 返回实际读取的字节数，如果连接关闭则返回0
  Future<int> read(Uint8List buffer, {int? length, Duration? timeout});

  /// 从通道读取指定数量的字节
  ///
  /// [buffer] 目标缓冲区
  /// [length] 要读取的字节数
  /// [timeout] 超时时间（可选）
  ///
  /// 如果无法读取指定数量的字节，则抛出异常
  Future<void> readFully(Uint8List buffer, {int? length, Duration? timeout});

  /// 写入数据到通道
  ///
  /// [data] 要写入的数据
  /// [offset] 数据起始偏移
  /// [length] 要写入的字节数
  /// [timeout] 超时时间（可选）
  ///
  /// 返回实际写入的字节数
  Future<int> write(Uint8List data,
      {int offset = 0, int? length, Duration? timeout});

  /// 将数据完全写入通道
  ///
  /// [data] 要写入的数据
  /// [offset] 数据起始偏移
  /// [length] 要写入的字节数
  /// [timeout] 超时时间（可选）
  ///
  /// 如果无法写入所有数据，则抛出异常
  Future<void> writeFully(Uint8List data,
      {int offset = 0, int? length, Duration? timeout});

  /// 刷新输出缓冲区
  Future<void> flush();

  /// 关闭输入流
  Future<void> shutdownInput();

  /// 关闭输出流
  Future<void> shutdownOutput();

  /// 关闭通道
  Future<void> close();

  /// 创建输入流
  Stream<Uint8List> get inputStream;

  /// 创建输出流接收器
  Sink<Uint8List> get outputSink;
}

/// 传输通道工厂
///
/// 用于创建不同类型的传输通道
abstract class TransportChannelFactory {
  /// 创建TCP传输通道
  Future<TransportChannel> createTcpChannel({
    required String host,
    required int port,
    Duration? connectionTimeout,
    Duration? readTimeout,
    Duration? writeTimeout,
  });

  /// 创建TLS传输通道
  Future<TransportChannel> createTlsChannel({
    required String host,
    required int port,
    Duration? connectionTimeout,
    Duration? readTimeout,
    Duration? writeTimeout,
    // TODO: TLS配置参数
  });
}

/// 基础传输通道实现
abstract class BaseTransportChannel implements TransportChannel {
  @override
  Future<void> readFully(Uint8List buffer,
      {int? length, Duration? timeout}) async {
    final targetLength = length ?? buffer.length;
    int totalRead = 0;

    while (totalRead < targetLength) {
      final remaining = targetLength - totalRead;
      final readBuffer = buffer.sublist(totalRead, totalRead + remaining);
      final bytesRead =
          await read(readBuffer, length: remaining, timeout: timeout);

      if (bytesRead == 0) {
        throw TransportException('连接关闭，无法读取完整的 $targetLength 字节');
      }

      totalRead += bytesRead;
    }
  }

  @override
  Future<void> writeFully(Uint8List data,
      {int offset = 0, int? length, Duration? timeout}) async {
    final targetLength = length ?? (data.length - offset);
    int totalWritten = 0;

    while (totalWritten < targetLength) {
      final currentOffset = offset + totalWritten;
      final remaining = targetLength - totalWritten;
      final bytesWritten = await write(data,
          offset: currentOffset, length: remaining, timeout: timeout);

      if (bytesWritten == 0) {
        throw TransportException('连接关闭，无法写入完整的 $targetLength 字节');
      }

      totalWritten += bytesWritten;
    }
  }
}
