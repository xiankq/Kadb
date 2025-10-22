import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'transport_channel.dart';
import 'socket_transport_channel.dart';

/// TLS传输通道
/// 实现基于TLS的ADB安全传输通道
class TlsTransportChannel implements TransportChannel {
  final SecureSocket _secureSocket;
  final InternetAddress _remoteAddress;
  final List<int> _readBuffer = [];
  bool _isClosed = false;

  TlsTransportChannel._internal(this._secureSocket, this._remoteAddress);

  /// 升级Socket通道到TLS通道
  /// [channel] 基础Socket通道
  /// [port] 端口号（需要从外部传入）
  /// 返回TlsTransportChannel实例
  static Future<TlsTransportChannel> upgrade(
    TransportChannel channel,
    int port,
  ) async {
    if (channel is! SocketTransportChannel) {
      throw Exception('只能升级SocketTransportChannel到TLS');
    }

    try {
      // 直接使用Socket.connect创建新的TLS连接
      // 因为Dart不支持直接获取SocketTransportChannel的底层Socket
      final remoteAddress = channel.remoteAddress;
      final secureSocket = await SecureSocket.connect(
        remoteAddress.address,
        port,
        onBadCertificate: (certificate) {
          // ADB允许自签名证书
          // Note: This print is left as-is since it's important security information
          // that should be visible during TLS connection debugging
          print('警告: 使用自签名证书: ${certificate.subject}');
          return true;
        },
      );

      // 关闭原始通道
      await channel.close();

      return TlsTransportChannel._internal(secureSocket, remoteAddress);
    } catch (e) {
      throw Exception('TLS升级失败: $e');
    }
  }

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
      completer.completeError(TimeoutException('TLS读取超时'));
    });

    subscription = _secureSocket.listen(
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
    final timer = Timer(
      timeout,
      () => completer.completeError(TimeoutException('TLS写入超时')),
    );

    try {
      _secureSocket.add(src);
      await _secureSocket.flush();
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
      final chunk = Uint8List.sublistView(
        dst,
        totalRead,
        totalRead + remaining,
      );
      final bytesRead = await read(chunk, timeout);
      if (bytesRead <= 0) {
        throw Exception('TLS连接已关闭');
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
    _secureSocket.destroy();
  }

  @override
  Future<void> shutdownOutput() async {
    _secureSocket.destroy();
  }

  @override
  InternetAddress get localAddress => _secureSocket.address;

  @override
  InternetAddress get remoteAddress => _remoteAddress;

  @override
  bool get isOpen => !_isClosed;

  @override
  Future<void> close() async {
    _isClosed = true;
    _secureSocket.destroy();
  }
}
