import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// 传输通道基类
/// 定义数据传输的通用接口
abstract class TransportChannel {
  /// 连接到远程主机
  /// [host] 主机地址
  /// [port] 端口号
  /// [timeout] 连接超时时间
  Future<void> connect(String host, int port, {Duration? timeout});

  /// 读取数据
  /// [buffer] 数据缓冲区
  /// [timeout] 读取超时时间
  Future<int> read(Uint8List buffer, Duration timeout);

  /// 读取指定长度的数据
  /// [buffer] 数据缓冲区
  /// [timeout] 读取超时时间
  Future<void> readExactly(Uint8List buffer, Duration timeout);

  /// 写入数据
  /// [data] 要写入的数据
  /// [timeout] 写入超时时间
  Future<int> write(Uint8List data, Duration timeout);

  /// 写入指定长度的数据
  /// [data] 要写入的数据
  /// [timeout] 写入超时时间
  Future<void> writeExactly(Uint8List data, Duration timeout);

  /// 关闭输入流
  Future<void> shutdownInput();

  /// 关闭输出流
  Future<void> shutdownOutput();

  /// 关闭传输通道
  Future<void> close();

  /// 检查通道是否已连接
  bool get isConnected;

  /// 检查通道是否打开
  bool get isOpen;

  /// 获取本地地址
  InternetAddress get localAddress;

  /// 获取远程地址
  InternetAddress get remoteAddress;
}
