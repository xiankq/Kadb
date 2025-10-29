/// TCP传输通道实现
///
/// 基于Dart内置Socket的TCP传输实现
/// 提供异步读写、超时控制和连接管理功能
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'transport_channel.dart';

/// TCP传输通道
///
/// 使用Dart的Socket类实现TCP连接，支持异步操作和超时控制
class TcpTransportChannel extends BaseTransportChannel {
  final Socket _socket;
  final StreamController<Uint8List> _inputController;
  final StreamController<Uint8List> _outputController;
  TransportState _state = TransportState.connected;

  TcpTransportChannel._(this._socket)
      : _inputController = StreamController<Uint8List>(),
        _outputController = StreamController<Uint8List>() {
    _setupSocketListeners();
  }

  /// 创建TCP传输通道
  static Future<TcpTransportChannel> connect({
    required String host,
    required int port,
    Duration? connectionTimeout,
    Duration? readTimeout,
    Duration? writeTimeout,
  }) async {
    try {
      final socket = await Socket.connect(host, port).timeout(
        connectionTimeout ?? Duration(seconds: 10),
        onTimeout: () {
          throw TransportException('连接超时: $host:$port');
        },
      );

      // 设置Socket选项
      socket.setOption(SocketOption.tcpNoDelay, true);

      return TcpTransportChannel._(socket);
    } on SocketException catch (e) {
      throw TransportException('连接失败: $host:$port', cause: e);
    } on TimeoutException catch (e) {
      throw TransportException('连接超时: $host:$port', cause: e);
    } catch (e) {
      throw TransportException('连接错误: $host:$port', cause: e);
    }
  }

  void _setupSocketListeners() {
    // 监听输入数据
    _socket.listen(
      (data) {
        _inputController.add(Uint8List.fromList(data));
      },
      onError: (error) {
        _state = TransportState.error;
        _inputController.addError(TransportException('Socket错误', cause: error));
        _inputController.close();
        _outputController.close();
      },
      onDone: () {
        _state = TransportState.closed;
        _inputController.close();
        _outputController.close();
      },
      cancelOnError: true,
    );

    // 监听输出数据
    _outputController.stream.listen(
      (data) {
        _socket.add(data);
      },
      onError: (error) {
        _state = TransportState.error;
        _inputController.addError(TransportException('输出错误', cause: error));
      },
      onDone: () {
        // 输出流关闭时，关闭Socket的输出
        _socket.flush().then((_) {
          _socket.destroy();
        });
      },
    );
  }

  @override
  String get localAddress => _socket.address.address;

  @override
  String get remoteAddress => _socket.remoteAddress.address;

  @override
  int get localPort => _socket.port;

  @override
  int get remotePort => _socket.remotePort;

  @override
  bool get isOpen => !_socket.isDestroyed && _state == TransportState.connected;

  @override
  TransportState get state => _state;

  @override
  Future<int> read(Uint8List buffer, {int? length, Duration? timeout}) async {
    if (!isOpen) {
      throw TransportException('通道已关闭');
    }

    final targetLength = length ?? buffer.length;
    final completer = Completer<int>();

    // 设置超时
    Timer? timeoutTimer;
    if (timeout != null) {
      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.completeError(TransportException('读取超时'));
        }
      });
    }

    try {
      // 监听输入流
      final subscription = _inputController.stream.listen(
        (data) {
          if (!completer.isCompleted) {
            final bytesToCopy =
                data.length < targetLength ? data.length : targetLength;
            buffer.setRange(0, bytesToCopy, data);
            timeoutTimer?.cancel();
            completer.complete(bytesToCopy);
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            timeoutTimer?.cancel();
            completer.completeError(error);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            timeoutTimer?.cancel();
            completer.complete(0); // 连接关闭
          }
        },
      );

      final result = await completer.future;
      await subscription.cancel();
      return result;
    } catch (e) {
      timeoutTimer?.cancel();
      rethrow;
    }
  }

  @override
  Future<int> write(Uint8List data,
      {int offset = 0, int? length, Duration? timeout}) async {
    if (!isOpen) {
      throw TransportException('通道已关闭');
    }

    final targetLength = length ?? (data.length - offset);
    final writeData =
        Uint8List.sublistView(data, offset, offset + targetLength);

    try {
      _outputController.add(writeData);
      await _socket.flush();
      return targetLength;
    } catch (e) {
      throw TransportException('写入失败', cause: e);
    }
  }

  @override
  Future<void> flush() async {
    if (!isOpen) {
      throw TransportException('通道已关闭');
    }

    try {
      await _socket.flush();
    } catch (e) {
      throw TransportException('刷新失败', cause: e);
    }
  }

  @override
  Future<void> shutdownInput() async {
    try {
      _socket.destroy();
    } catch (e) {
      // 忽略错误
    }
  }

  @override
  Future<void> shutdownOutput() async {
    try {
      await _socket.flush();
      _socket.destroy();
    } catch (e) {
      // 忽略错误
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    try {
      await _outputController.close();
      await _inputController.close();
      _socket.destroy();
    } catch (e) {
      // 忽略关闭错误
    }
  }

  bool _isClosed = false;

  @override
  Stream<Uint8List> get inputStream => _inputController.stream;

  @override
  Sink<Uint8List> get outputSink => _outputController.sink;
}

/// TCP传输通道工厂
class TcpTransportChannelFactory implements TransportChannelFactory {
  @override
  Future<TransportChannel> createTcpChannel({
    required String host,
    required int port,
    Duration? connectionTimeout,
    Duration? readTimeout,
    Duration? writeTimeout,
  }) async {
    return await TcpTransportChannel.connect(
      host: host,
      port: port,
      connectionTimeout: connectionTimeout,
      readTimeout: readTimeout,
      writeTimeout: writeTimeout,
    );
  }

  @override
  Future<TransportChannel> createTlsChannel({
    required String host,
    required int port,
    Duration? connectionTimeout,
    Duration? readTimeout,
    Duration? writeTimeout,
  }) async {
    // 创建基础TCP连接
    final tcpChannel = await createTcpChannel(
      host: host,
      port: port,
      connectionTimeout: connectionTimeout,
      readTimeout: readTimeout,
      writeTimeout: writeTimeout,
    );

    // 这里应该实现TLS升级，但目前ADB协议中TLS支持不常见
    // 参考Kadb实现，TLS通常是通过STLS命令协商的
    // 所以我们这里返回基础TCP连接，TLS升级在连接层处理
    return tcpChannel;
  }
}
