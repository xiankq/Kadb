import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// 传输通道接口
/// 抽象网络连接，支持同步和异步IO操作
abstract class TransportChannel {
  /// 从通道读取数据到缓冲区
  /// [dst] 目标缓冲区
  /// [timeout] 超时时间
  /// 返回读取的字节数
  Future<int> read(Uint8List dst, Duration timeout);
  
  /// 从缓冲区写入数据到通道
  /// [src] 源缓冲区
  /// [timeout] 超时时间
  /// 返回写入的字节数
  Future<int> write(Uint8List src, Duration timeout);
  
  /// 完全读取指定长度的数据
  /// [dst] 目标缓冲区
  /// [timeout] 超时时间
  Future<void> readExactly(Uint8List dst, Duration timeout);
  
  /// 完全写入缓冲区数据
  /// [src] 源缓冲区
  /// [timeout] 超时时间
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

/// Socket传输通道实现
class SocketTransportChannel implements TransportChannel {
  final Socket _socket;
  final List<int> _readBuffer = [];
  bool _isClosed = false;
  
  SocketTransportChannel(this._socket);
  
  @override
  Future<int> read(Uint8List dst, Duration timeout) async {
    if (_isClosed) throw Exception('通道已关闭');
    
    // 如果缓冲区已有足够数据，直接返回
    if (_readBuffer.length >= dst.length) {
      final bytesToCopy = dst.length;
      for (int i = 0; i < bytesToCopy; i++) {
        dst[i] = _readBuffer.removeAt(0);
      }
      return bytesToCopy;
    }
    
    // 等待数据到达
    final completer = Completer<int>();
    late StreamSubscription<List<int>> subscription;
    final timer = Timer(timeout, () {
      subscription.cancel();
      completer.completeError(TimeoutException('读取超时'));
    });
    
    subscription = _socket.listen(
      (data) {
        _readBuffer.addAll(data);
        if (_readBuffer.length >= dst.length) {
          final bytesToCopy = dst.length;
          for (int i = 0; i < bytesToCopy; i++) {
            dst[i] = _readBuffer.removeAt(0);
          }
          timer.cancel();
          subscription.cancel();
          completer.complete(bytesToCopy);
        }
      },
      onError: (error) {
        timer.cancel();
        subscription.cancel();
        completer.completeError(error);
      },
      onDone: () {
        timer.cancel();
        subscription.cancel();
        completer.complete(-1);
      },
    );
    
    return completer.future;
  }
  
  @override
  Future<int> write(Uint8List src, Duration timeout) async {
    if (_isClosed) throw Exception('通道已关闭');
    
    final completer = Completer<int>();
    final timer = Timer(timeout, () => completer.completeError(TimeoutException('写入超时')));
    
    try {
      _socket.add(src);
      await _socket.flush();
      timer.cancel();
      completer.complete(src.length);
    } catch (e) {
      timer.cancel();
      completer.completeError(e);
    }
    
    return completer.future;
  }
  
  @override
  Future<void> readExactly(Uint8List dst, Duration timeout) async {
    var totalRead = 0;
    while (totalRead < dst.length) {
      final remaining = dst.length - totalRead;
      final chunk = Uint8List.sublistView(dst, totalRead, totalRead + remaining);
      final bytesRead = await read(chunk, timeout);
      if (bytesRead <= 0) {
        throw Exception('连接已关闭');
      }
      totalRead += bytesRead;
    }
  }
  
  @override
  Future<void> writeExactly(Uint8List src, Duration timeout) async {
    await write(src, timeout);
  }
  
  @override
  Future<void> shutdownInput() async {
    _socket.destroy();
  }
  
  @override
  Future<void> shutdownOutput() async {
    _socket.destroy();
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
    _socket.destroy();
  }
  
  /// 连接到指定主机和端口
  /// [host] 主机地址
  /// [port] 端口号
  /// [timeout] 连接超时时间
  /// 返回TransportChannel对象
  static Future<TransportChannel> connect(
    String host, int port, Duration timeout,
  ) async {
    final completer = Completer<Socket>();
    final timer = Timer(timeout, () => completer.completeError(TimeoutException('连接超时')));
    
    try {
      final socket = await Socket.connect(host, port);
      timer.cancel();
      completer.complete(socket);
    } catch (e) {
      timer.cancel();
      completer.completeError(e);
    }
    
    final socket = await completer.future;
    return SocketTransportChannel(socket);
  }
}