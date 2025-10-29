/// 传输通道抽象
/// 定义统一的传输层接口
library transport_channel;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// 传输通道接口
abstract class TransportChannel {
  /// 读取数据到缓冲区
  Future<int> read(Uint8List buffer, Duration timeout);

  /// 写入数据
  Future<int> write(Uint8List data, Duration timeout);

  /// 精确读取指定数量的字节
  Future<void> readExact(Uint8List buffer, Duration timeout);

  /// 精确写入所有数据
  Future<void> writeExact(Uint8List data, Duration timeout);

  /// 关闭输入
  Future<void> shutdownInput();

  /// 关闭输出
  Future<void> shutdownOutput();

  /// 获取本地地址
  InternetAddress get localAddress;

  /// 获取远程地址
  InternetAddress get remoteAddress;

  /// 是否打开
  bool get isOpen;

  /// 关闭通道
  Future<void> close();
}

/// TCP传输通道实现
class TcpTransportChannel implements TransportChannel {
  final Socket _socket;
  bool _isClosed = false;

  TcpTransportChannel(this._socket);

  @override
  Future<int> read(Uint8List buffer, Duration timeout) async {
    final completer = Completer<int>();
    late StreamSubscription subscription;

    subscription = _socket.listen(
      (data) {
        if (!completer.isCompleted) {
          final bytesToRead = data.length < buffer.length ? data.length : buffer.length;
          buffer.setAll(0, data.sublist(0, bytesToRead));
          completer.complete(bytesToRead);
          subscription.cancel();
        }
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(-1);
        }
      },
    );

    // 设置超时
    Timer(timeout, () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.completeError(TimeoutException('Read timeout after $timeout'));
      }
    });

    return completer.future;
  }

  @override
  Future<int> write(Uint8List data, Duration timeout) async {
    _socket.add(data);
    await _socket.flush();
    return data.length;
  }

  @override
  Future<void> readExact(Uint8List buffer, Duration timeout) async {
    int offset = 0;
    while (offset < buffer.length) {
      final tempBuffer = Uint8List(buffer.length - offset);
      final bytesRead = await read(tempBuffer, timeout);
      if (bytesRead <= 0) {
        throw Exception('Connection closed while reading');
      }
      buffer.setAll(offset, tempBuffer.sublist(0, bytesRead));
      offset += bytesRead;
    }
  }

  @override
  Future<void> writeExact(Uint8List data, Duration timeout) async {
    int offset = 0;
    while (offset < data.length) {
      final chunk = data.sublist(offset);
      final bytesWritten = await write(chunk, timeout);
      if (bytesWritten <= 0) {
        throw Exception('Connection closed while writing');
      }
      offset += bytesWritten;
    }
  }

  @override
  Future<void> shutdownInput() async {
    _socket.destroy();
    _isClosed = true;
  }

  @override
  Future<void> shutdownOutput() async {
    _socket.destroy();
    _isClosed = true;
  }

  @override
  InternetAddress get localAddress => _socket.address;

  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;

  @override
  bool get isOpen => !_isClosed;

  @override
  Future<void> close() async {
    _isClosed = true;
    await _socket.close();
  }
}

/// 传输通道工厂
class TransportFactory {
  static Future<TransportChannel> connect(String host, int port, Duration connectTimeout) async {
    final socket = await Socket.connect(host, port, timeout: connectTimeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    return TcpTransportChannel(socket);
  }
}

/// 超时异常
class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}