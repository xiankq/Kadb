import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'transport_channel.dart';

/// TLS传输通道实现
/// 将Dart的SecureSocket适配到TransportChannel接口
class TlsTransportChannel implements TransportChannel {
  final SecureSocket _secureSocket;
  final Completer<void> _closeCompleter = Completer<void>();

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
    try {
      _secureSocket.add(data);
      await _secureSocket.flush();
      return data.length;
    } catch (e) {
      throw TransportException('TLS write failed: $e');
    }
  }

  @override
  Future<Uint8List> read(int maxSize) async {
    try {
      // 从SecureSocket读取数据
      final subscription = _secureSocket.listen((data) {});

      // 等待数据可用
      await for (final data in _secureSocket) {
        if (data.isNotEmpty) {
          subscription.cancel();

          // 限制读取大小
          if (data.length > maxSize) {
            return data.sublist(0, maxSize);
          }
          return data;
        }
      }

      subscription.cancel();
      return Uint8List(0);
    } catch (e) {
      throw TransportException('TLS read failed: $e');
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

      // 简单的状态检查
      return true;
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
  Duration get readTimeout => const Duration(seconds: 30);

  @override
  Duration get writeTimeout => const Duration(seconds: 30);

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
      return null;
    }
  }

  /// 获取TLS证书信息
  X509Certificate? get peerCertificate {
    try {
      return _secureSocket.peerCertificate;
    } catch (e) {
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
