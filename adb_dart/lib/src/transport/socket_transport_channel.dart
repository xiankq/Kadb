/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'transport_channel.dart';

/// Socket传输通道实现
class SocketTransportChannel implements TransportChannel {
  final Socket _socket;
  final StreamController<Uint8List> _inputController =
      StreamController<Uint8List>();

  Duration? _readTimeout;
  Duration? _writeTimeout;

  SocketTransportChannel(this._socket) {
    _setupSocketListeners();
  }

  /// 设置Socket监听器
  void _setupSocketListeners() {
    print('设置Socket监听器...');
    _socket.listen(
      (data) {
        print('Socket接收到数据，长度: ${data.length}');
        if (data is Uint8List) {
          _inputController.add(data);
        } else if (data is List<int>) {
          _inputController.add(Uint8List.fromList(data));
        }
      },
      onError: (error) {
        print('Socket错误: $error');
        _inputController.addError(error);
      },
      onDone: () {
        print('Socket连接关闭');
        _inputController.close();
      },
      cancelOnError: false,
    );
  }

  @override
  Future<Uint8List> read(int maxSize) async {
    if (!isOpen) {
      throw TransportException('Transport channel is closed');
    }

    try {
      final completer = Completer<Uint8List>();
      final buffer = BytesBuilder();

      StreamSubscription<Uint8List>? subscription;
      subscription = _inputController.stream.listen(
        (data) {
          buffer.add(data);
          if (buffer.length >= maxSize) {
            subscription?.cancel();
            completer.complete(buffer.toBytes().sublist(0, maxSize));
          }
        },
        onError: (error) {
          subscription?.cancel();
          completer.completeError(TransportException('Read error', error));
        },
        onDone: () {
          subscription?.cancel();
          if (!completer.isCompleted) {
            final result = buffer.toBytes();
            if (result.isNotEmpty) {
              completer.complete(result);
            } else {
              completer.completeError(
                TransportException('Stream closed before reading complete'),
              );
            }
          }
        },
      );

      if (_readTimeout != null) {
        return await completer.future.timeout(_readTimeout!);
      } else {
        return await completer.future;
      }
    } catch (e) {
      if (e is TransportException) rethrow;
      throw TransportException('Read failed', e);
    }
  }

  @override
  Future<int> write(Uint8List data) async {
    if (!isOpen) {
      throw TransportException('Transport channel is closed');
    }

    try {
      _socket.add(data);
      if (_writeTimeout != null) {
        await _socket.flush().timeout(_writeTimeout!);
      } else {
        await _socket.flush();
      }
      return data.length;
    } catch (e) {
      throw TransportException('Write failed', e);
    }
  }

  @override
  bool get isOpen {
    try {
      // 简单的状态检查 - 检查socket地址是否可用
      return _socket.address != null;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> close() async {
    try {
      await _inputController.close();
      await _socket.close();
    } catch (e) {
      throw TransportException('Close failed', e);
    }
  }

  @override
  Future<void> flush() async {
    if (!isOpen) {
      throw TransportException('Transport channel is closed');
    }

    try {
      await _socket.flush();
    } catch (e) {
      throw TransportException('Flush failed', e);
    }
  }

  @override
  Stream<Uint8List> get dataStream => _inputController.stream;

  @override
  void setReadTimeout(Duration timeout) {
    _readTimeout = timeout;
  }

  @override
  void setWriteTimeout(Duration timeout) {
    _writeTimeout = timeout;
  }

  @override
  Duration get readTimeout => _readTimeout ?? const Duration(seconds: 30);

  @override
  Duration get writeTimeout => _writeTimeout ?? const Duration(seconds: 30);

  @override
  Stream<Uint8List> get inputStream => _inputController.stream;

  @override
  Future<void> get done => _socket.done;

  @override
  InternetAddress? get remoteAddress => _socket.remoteAddress;

  @override
  int? get remotePort => _socket.remotePort;

  @override
  InternetAddress? get localAddress => _socket.address;

  @override
  int? get localPort => _socket.port;

  @override
  void setSocketOption(SocketOption option, bool enabled) {
    try {
      _socket.setOption(option, enabled);
    } catch (e) {
      // 忽略设置选项的错误
    }
  }

  @override
  Future<void> destroy() async {
    try {
      _socket.destroy();
      await _inputController.close();
    } catch (e) {
      throw TransportException('Destroy failed', e);
    }
  }
}

/// Socket传输工厂
class SocketTransportFactory {
  static Future<SocketTransportChannel> connect({
    required String host,
    required int port,
    Duration connectTimeout = const Duration(seconds: 10),
  }) async {
    try {
      final socket = await Socket.connect(host, port, timeout: connectTimeout);
      return SocketTransportChannel(socket);
    } catch (e) {
      throw Exception('Failed to connect to $host:$port: $e');
    }
  }
}
