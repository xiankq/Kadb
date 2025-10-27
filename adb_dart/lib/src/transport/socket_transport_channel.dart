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
  final Completer<void> _closeCompleter = Completer<void>();

  Duration? _readTimeout;
  Duration? _writeTimeout;

  SocketTransportChannel(this._socket) {
    _setupSocketListeners();
    // 监听socket关闭事件
    _socket.done.then((_) {
      if (!_closeCompleter.isCompleted) {
        _closeCompleter.complete();
      }
    }).catchError((error) {
      if (!_closeCompleter.isCompleted) {
        _closeCompleter.completeError(error);
      }
    });
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
      DateTime? startTime;
      
      if (_readTimeout != null) {
        startTime = DateTime.now();
      }

      StreamSubscription<Uint8List>? subscription;
      subscription = _inputController.stream.listen(
        (data) {
          try {
            buffer.add(data);
            print('读取数据块: ${data.length} 字节，缓冲区: ${buffer.length} 字节');
            
            if (buffer.length >= maxSize) {
              subscription?.cancel();
              final result = buffer.toBytes().sublist(0, maxSize);
              print('读取完成，返回 ${result.length} 字节');
              completer.complete(result);
            }
            
            // 检查超时
            if (_readTimeout != null && startTime != null) {
              final elapsed = DateTime.now().difference(startTime);
              if (elapsed > _readTimeout!) {
                subscription?.cancel();
                completer.completeError(
                  TransportException('Read timeout after ${elapsed.inMilliseconds}ms'),
                );
              }
            }
          } catch (e) {
            subscription?.cancel();
            completer.completeError(TransportException('Read processing error', e));
          }
        },
        onError: (error) {
          subscription?.cancel();
          print('读取流错误: $error');
          completer.completeError(TransportException('Read stream error', error));
        },
        onDone: () {
          subscription?.cancel();
          if (!completer.isCompleted) {
            final result = buffer.toBytes();
            if (result.isNotEmpty) {
              print('流结束，返回剩余 ${result.length} 字节');
              completer.complete(result);
            } else {
              print('流结束且无数据');
              completer.completeError(
                TransportException('Stream closed before reading complete'),
              );
            }
          }
        },
      );

      // 设置超时处理
      if (_readTimeout != null) {
        return await completer.future.timeout(
          _readTimeout!,
          onTimeout: () {
            subscription?.cancel();
            throw TransportException('Read operation timed out after ${_readTimeout!.inMilliseconds}ms');
          },
        );
      } else {
        return await completer.future;
      }
    } on TimeoutException {
      throw TransportException('Read timeout');
    } catch (e) {
      if (e is TransportException) rethrow;
      print('读取操作失败: $e');
      throw TransportException('Read operation failed', e);
    }
  }

  @override
  Future<int> write(Uint8List data) async {
    if (!isOpen) {
      throw TransportException('Transport channel is closed');
    }

    if (data.isEmpty) {
      return 0;
    }

    try {
      print('写入数据: ${data.length} 字节');
      
      // 分块写入大数据
      const maxChunkSize = 65536; // 64KB
      int totalWritten = 0;
      
      for (int offset = 0; offset < data.length; offset += maxChunkSize) {
        final chunkSize = (offset + maxChunkSize <= data.length) 
            ? maxChunkSize 
            : data.length - offset;
        final chunk = data.sublist(offset, offset + chunkSize);
        
        _socket.add(chunk);
        totalWritten += chunkSize;
        
        print('写入数据块: $chunkSize 字节，总计: $totalWritten 字节');
        
        // 刷新并等待确认
        if (_writeTimeout != null) {
          await _socket.flush().timeout(_writeTimeout!);
        } else {
          await _socket.flush();
        }
      }
      
      print('数据写入完成: $totalWritten 字节');
      return totalWritten;
    } on TimeoutException {
      throw TransportException('Write timeout after ${_writeTimeout?.inMilliseconds ?? 0}ms');
    } catch (e) {
      print('写入失败: $e');
      throw TransportException('Write failed', e);
    }
  }

  @override
  bool get isOpen {
    try {
      // 更全面的状态检查 - 使用Completer来判断连接状态
      return !_closeCompleter.isCompleted && 
             _socket.address != null && 
             !_inputController.isClosed;
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
