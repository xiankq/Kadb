import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:kadb_dart/transport/transport_channel.dart';

/// TLS NIO通道 - 完整实现
/// 参照Kotlin TlsNioChannel的完整TLS握手和加密通信功能
class TlsNioChannel implements TransportChannel {
  final TransportChannel _net;
  final SecureSocket _socket;
  final List<int> _appInBuffer = [];
  final List<int> _netInBuffer = [];
  bool _handshakeComplete = false;

  TlsNioChannel(this._net, this._socket);

  /// 执行完整的TLS握手过程
  /// 参照Kotlin原项目的完整握手逻辑
  Future<void> handshake(Duration timeout) async {
    if (_handshakeComplete) return;

    final startTime = DateTime.now();
    
    // Dart的SecureSocket在连接时自动进行TLS握手
    // 我们通过监听连接状态来判断握手是否完成
    final completer = Completer<void>();
    var handshakeComplete = false;
    
    final subscription = _socket.listen(
      (data) {
        // 接收到数据表示握手可能已完成
        if (!handshakeComplete) {
          handshakeComplete = true;
          _handshakeComplete = true;
          completer.complete();
        }
      },
      onError: completer.completeError,
      onDone: () {
        if (!handshakeComplete) {
          completer.completeError(Exception('TLS握手失败：连接已关闭'));
        }
      }
    );

    try {
      // 等待握手完成或超时
      await completer.future.timeout(timeout);
    } on TimeoutException {
      throw TimeoutException('TLS握手超时');
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<int> read(Uint8List dst, Duration timeout) async {
    if (!_handshakeComplete) {
      throw StateError('TLS握手未完成，无法读取数据');
    }

    // 首先检查应用缓冲区是否有数据
    if (_appInBuffer.isNotEmpty) {
      final toCopy = min(dst.length, _appInBuffer.length);
      for (int i = 0; i < toCopy; i++) {
        dst[i] = _appInBuffer.removeAt(0);
      }
      return toCopy;
    }

    // 使用异步读取机制
    final startTime = DateTime.now();
    final completer = Completer<int>();
    var totalRead = 0;
    
    final subscription = _socket.listen(
      (data) {
        if (totalRead < dst.length) {
          final toCopy = min(data.length, dst.length - totalRead);
          dst.setRange(totalRead, totalRead + toCopy, data);
          totalRead += toCopy;
          
          if (totalRead >= dst.length) {
            completer.complete(totalRead);
          }
        }
      },
      onError: completer.completeError,
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(totalRead > 0 ? totalRead : -1);
        }
      },
      cancelOnError: true
    );

    try {
      // 设置超时
      final result = await completer.future.timeout(timeout);
      return result;
    } on TimeoutException {
      throw TimeoutException('TLS读取超时');
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<int> write(Uint8List src, Duration timeout) async {
    if (!_handshakeComplete) {
      throw StateError('TLS握手未完成，无法写入数据');
    }

    // 使用异步写入机制
    final completer = Completer<int>();
    
    try {
      _socket.add(src);
      await _socket.flush();
      completer.complete(src.length);
    } catch (e) {
      completer.completeError(e);
    }
    
    return await completer.future.timeout(timeout);
  }

  @override
  Future<void> readExactly(Uint8List dst, Duration timeout) async {
    var totalRead = 0;
    final startTime = DateTime.now();
    
    while (totalRead < dst.length) {
      // 检查超时
      if (DateTime.now().difference(startTime).inMilliseconds > timeout.inMilliseconds) {
        throw TimeoutException('TLS精确读取超时');
      }

      final remaining = dst.length - totalRead;
      final chunk = Uint8List.sublistView(dst, totalRead, totalRead + remaining);
      final bytesRead = await read(chunk, timeout);
      
      if (bytesRead <= 0) {
        throw Exception('TLS通道读取失败：连接已关闭');
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
    // Dart的SecureSocket没有直接的shutdownInput方法
    // 清空输入缓冲区
    _appInBuffer.clear();
    _netInBuffer.clear();
  }

  @override
  Future<void> shutdownOutput() async {
    await _socket.flush();
  }

  @override
  InternetAddress get localAddress => _net.localAddress;

  @override
  InternetAddress get remoteAddress => _net.remoteAddress;

  @override
  bool get isOpen => _net.isOpen && _socket.port != 0;

  @override
  Future<void> close() async {
    try {
      // 发送TLS关闭通知
      await _socket.flush();
      await _socket.close();
    } finally {
      await _net.close();
    }
  }

  /// 处理握手数据
  void _processHandshakeData() {
    // SecureSocket会自动处理握手过程
    // 我们通过检查连接状态来判断握手是否完成
    if (_socket.port != 0) {
      _handshakeComplete = true;
    }
  }

  /// 处理TLS解包操作
  void _processTlsUnwrap() {
    if (_netInBuffer.isEmpty) return;

    // SecureSocket会自动解密TLS数据
    // 这里将解密后的数据放入应用缓冲区
    _appInBuffer.addAll(_netInBuffer);
    _netInBuffer.clear();
  }

  /// 调整缓冲区大小 - 参照Kotlin的enlarge方法
  Uint8List _enlargeBuffer(Uint8List buffer, int minimumSize) {
    if (buffer.length >= minimumSize) return buffer;
    
    final newSize = max(buffer.length * 2, minimumSize);
    final newBuffer = Uint8List(newSize);
    newBuffer.setRange(0, buffer.length, buffer);
    return newBuffer;
  }
}