import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// 传输通道接口，抽象网络连接，支持同步和异步IO操作
abstract class TransportChannel {
  /// 从通道读取数据到缓冲区
  Future<int> read(Uint8List dst, Duration timeout);

  /// 从缓冲区写入数据到通道
  Future<int> write(Uint8List src, Duration timeout);

  /// 完全读取指定长度的数据
  Future<void> readExactly(Uint8List dst, Duration timeout);

  /// 完全写入缓冲区数据
  Future<void> writeExactly(Uint8List src, Duration timeout);

  /// 关闭输入流
  Future<void> shutdownInput();

  /// 关闭输出流
  Future<void> shutdownOutput();

  /// 获取本地地址
  InternetAddress get localAddress;

  /// 获取远程地址
  InternetAddress get remoteAddress;

  /// 检查通道是否打开
  bool get isOpen;

  /// 关闭通道
  Future<void> close();
}
