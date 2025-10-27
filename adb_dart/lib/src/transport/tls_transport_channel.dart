import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'transport_channel.dart';

/// TLS传输通道实现
/// 将Dart的SecureSocket适配到TransportChannel接口
class TlsTransportChannel implements TransportChannel {
  final SecureSocket _secureSocket;
  final Completer<void> _closeCompleter = Completer<void>();
  Duration? _readTimeout;
  Duration? _writeTimeout;

  TlsTransportChannel(this._secureSocket) {
    _secureSocket.done
        .then((_) {
          if (!_closeCompleter.isCompleted) {
            _closeCompleter.complete();
          }
        })
        .catchError((error) {
          if (!_closeCompleter.isCompleted) {
            _closeCompleter.completeError(error);
          }
        });

    _secureSocket.listen(
      (_) {},
      onError: (_) {},
      onDone: () {
        if (!_closeCompleter.isCompleted) {
          _closeCompleter.complete();
        }
      },
    );
  }

  @override
  Future<int> write(Uint8List data) async {
    if (!isOpen) {
      throw TransportException('TLS transport channel is closed');
    }

    if (data.isEmpty) {
      return 0;
    }

    try {
      print('TLS写入数据: ${data.length} 字节');
      
      // 分块写入大数据
      const maxChunkSize = 65536; // 64KB
      int totalWritten = 0;
      
      for (int offset = 0; offset < data.length; offset += maxChunkSize) {
        final chunkSize = (offset + maxChunkSize <= data.length) 
            ? maxChunkSize 
            : data.length - offset;
        final chunk = data.sublist(offset, offset + chunkSize);
        
        _secureSocket.add(chunk);
        totalWritten += chunkSize;
        
        print('TLS写入数据块: $chunkSize 字节，总计: $totalWritten 字节');
        await _secureSocket.flush();
      }
      
      print('TLS数据写入完成: $totalWritten 字节');
      return totalWritten;
    } catch (e) {
      print('TLS写入失败: $e');
      throw TransportException('TLS write failed', e);
    }
  }

  @override
  Future<Uint8List> read(int maxSize) async {
    if (!isOpen) {
      throw TransportException('TLS transport channel is closed');
    }

    try {
      print('TLS读取请求: 最大 $maxSize 字节');
      
      final completer = Completer<Uint8List>();
      final buffer = BytesBuilder();
      StreamSubscription<Uint8List>? subscription;
      
      subscription = _secureSocket.listen(
        (data) {
          if (data.isNotEmpty) {
            buffer.add(data);
            print('TLS接收到数据: ${data.length} 字节，缓冲区: ${buffer.length} 字节');
            
            if (buffer.length >= maxSize) {
              subscription?.cancel();
              final result = buffer.toBytes().sublist(0, maxSize);
              print('TLS读取完成，返回 ${result.length} 字节');
              completer.complete(result);
            }
          }
        },
        onError: (error) {
          subscription?.cancel();
          print('TLS读取错误: $error');
          completer.completeError(TransportException('TLS read error', error));
        },
        onDone: () {
          subscription?.cancel();
          if (!completer.isCompleted) {
            final result = buffer.toBytes();
            if (result.isNotEmpty) {
              print('TLS流结束，返回剩余 ${result.length} 字节');
              completer.complete(result);
            } else {
              print('TLS流结束且无数据');
              completer.complete(Uint8List(0));
            }
          }
        },
      );

      // 设置读取超时
      final readTimeout = _readTimeout;
      if (readTimeout != null) {
        return await completer.future.timeout(
          readTimeout,
          onTimeout: () {
            subscription?.cancel();
            throw TransportException('TLS read timeout after ${readTimeout.inMilliseconds}ms');
          },
        );
      } else {
        return await completer.future;
      }
    } on TimeoutException {
      throw TransportException('TLS read timeout');
    } catch (e) {
      print('TLS读取失败: $e');
      throw TransportException('TLS read failed', e);
    }
  }

  @override
  Future<void> close() async {
    try {
      await _secureSocket.close();
      await _closeCompleter.future;
    } catch (e) {
      throw TransportException('TLS close failed: $e');
    }
  }

  @override
  bool get isOpen {
    try {
      if (_closeCompleter.isCompleted) return false;
      
      // 检查SecureSocket状态 - 使用Completer来判断
      return true; // SecureSocket在Dart中没有直接的isOpen检查
    } catch (e) {
      return false;
    }
  }

  @override
  InternetAddress? get remoteAddress => _secureSocket.remoteAddress;

  @override
  int? get remotePort => _secureSocket.remotePort;

  @override
  InternetAddress? get localAddress => _secureSocket.address;

  @override
  int? get localPort => _secureSocket.port;

  @override
  Duration get readTimeout => _readTimeout ?? const Duration(seconds: 30);

  @override
  Duration get writeTimeout => _writeTimeout ?? const Duration(seconds: 30);

  @override
  void setReadTimeout(Duration timeout) {
    _readTimeout = timeout;
  }

  @override
  void setWriteTimeout(Duration timeout) {
    _writeTimeout = timeout;
  }

  @override
  Stream<Uint8List> get dataStream {
    return _secureSocket.map((data) => Uint8List.fromList(data));
  }

  @override
  Future<void> get done => _closeCompleter.future;

  /// 获取TLS连接信息
  String? get tlsProtocolVersion {
    try {
      return _secureSocket.selectedProtocol;
    } catch (e) {
      print('获取TLS协议版本失败: $e');
      return null;
    }
  }

  /// 获取TLS证书信息
  X509Certificate? get peerCertificate {
    try {
      return _secureSocket.peerCertificate;
    } catch (e) {
      print('获取对等证书失败: $e');
      return null;
    }
  }

  /// 刷新TLS连接
  @override
  Future<void> flush() async {
    try {
      await _secureSocket.flush();
    } catch (e) {
      throw TransportException('TLS flush failed: $e');
    }
  }

  /// 设置TLS连接选项
  @override
  void setSocketOption(SocketOption option, bool enabled) {
    try {
      _secureSocket.setOption(option, enabled);
    } catch (e) {
      // 忽略设置选项的错误
    }
  }

  /// 销毁TLS连接
  @override
  Future<void> destroy() async {
    try {
      _secureSocket.destroy();
      if (!_closeCompleter.isCompleted) {
        _closeCompleter.complete();
      }
    } catch (e) {
      if (!_closeCompleter.isCompleted) {
        _closeCompleter.completeError(e);
      }
    }
  }
}
