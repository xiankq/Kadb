import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'transport_channel.dart' as base;

/// Socket传输通道
/// 实现基于Socket的ADB传输通道
class SocketTransportChannel implements base.TransportChannel {
  Socket? _socket;
  final List<int> _readBuffer = [];
  Completer<void> _dataAvailable = Completer<void>();
  bool _isConnected = false;
  bool _listenerStarted = false;
  
  SocketTransportChannel();

  @override
  Future<void> connect(String host, int port, {Duration? timeout}) async {
    try {
      final addresses = await InternetAddress.lookup(host);
      if (addresses.isEmpty) {
        throw Exception('无法解析主机地址: $host');
      }
      
      _socket = await Socket.connect(addresses.first, port, timeout: timeout);
      _isConnected = true;
      _startSocketListener();
    } on TimeoutException {
      throw Exception('连接超时: $host:$port');
    } on SocketException catch (e) {
      throw Exception('连接失败: $e');
    }
  }

  /// 启动Socket监听器
  void _startSocketListener() {
    if (_listenerStarted) return;
    _listenerStarted = true;
    
    _socket!.listen(
      (data) {
        _readBuffer.addAll(data);
        if (!_dataAvailable.isCompleted) {
          _dataAvailable.complete();
        }
      },
      onError: (error) {
        if (!_dataAvailable.isCompleted) {
          _dataAvailable.completeError(error);
        }
      },
      onDone: () {
        if (!_dataAvailable.isCompleted) {
          _dataAvailable.complete();
        }
      },
    );
  }

  @override
  Future<void> readExactly(Uint8List buffer, Duration timeout) async {
    if (_socket == null || !_isConnected) {
      throw Exception('通道未连接');
    }
    
    var totalRead = 0;
    while (totalRead < buffer.length) {
      // 如果缓冲区有足够数据，直接读取
      if (_readBuffer.length >= buffer.length - totalRead) {
        final bytesToRead = buffer.length - totalRead;
        for (int i = 0; i < bytesToRead; i++) {
          buffer[totalRead + i] = _readBuffer.removeAt(0);
        }
        totalRead += bytesToRead;
        continue;
      }
      
      // 如果缓冲区数据不足，等待更多数据
      if (_readBuffer.isNotEmpty) {
        final bytesToRead = _readBuffer.length;
        for (int i = 0; i < bytesToRead; i++) {
          buffer[totalRead + i] = _readBuffer.removeAt(0);
        }
        totalRead += bytesToRead;
      }
      
      // 等待更多数据到达
      try {
        await _dataAvailable.future.timeout(timeout);
        // 重置数据可用信号
        if (_dataAvailable.isCompleted) {
          _dataAvailable = Completer<void>();
        }
      } on TimeoutException {
        throw Exception('读取超时: 期望${buffer.length}字节，已读取$totalRead字节');
      }
    }
  }

  @override
  Future<int> write(Uint8List data, Duration timeout) async {
    if (_socket == null || !_isConnected) {
      throw Exception('通道未连接');
    }
    
    final completer = Completer<int>();
    final timer = Timer(timeout, () {
      completer.completeError(TimeoutException('写入超时'));
    });
    
    try {
      _socket!.add(data);
      await _socket!.flush();
      timer.cancel();
      completer.complete(data.length);
    } catch (e) {
      timer.cancel();
      completer.completeError(e);
    }
    
    return completer.future;
  }

  @override
  Future<int> read(Uint8List buffer, Duration timeout) async {
    if (_socket == null || !_isConnected) {
      throw Exception('通道未连接');
    }
    
    var totalRead = 0;
    if (_readBuffer.isNotEmpty) {
      final bytesToRead = _readBuffer.length < buffer.length ? _readBuffer.length : buffer.length;
      for (int i = 0; i < bytesToRead; i++) {
        buffer[i] = _readBuffer.removeAt(0);
      }
      totalRead = bytesToRead;
    }
    
    return totalRead;
  }

  @override
  Future<void> writeExactly(Uint8List data, Duration timeout) async {
    await write(data, timeout);
  }

  @override
  Future<void> shutdownInput() async {
    _socket?.destroy();
  }

  @override
  Future<void> shutdownOutput() async {
    _socket?.destroy();
  }

  @override
  Future<void> close() async {
    _isConnected = false;
    _socket?.destroy();
    _socket = null;
  }

  @override
  bool get isConnected => _isConnected;

  @override
  bool get isOpen => _isConnected;

  @override
  InternetAddress get localAddress => _socket?.address ?? InternetAddress('0.0.0.0');

  @override
  InternetAddress get remoteAddress {
    if (_socket == null) {
      return InternetAddress('0.0.0.0');
    }
    // 这里需要返回实际的远程地址，但Socket类没有直接提供
    // 暂时返回本地地址作为占位符
    return _socket!.address;
  }
}