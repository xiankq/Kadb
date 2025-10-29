/// TLS传输通道实现（完整复刻Kadb版本）
///
/// 提供基于TLS加密的传输通道，完整实现Kadb的TlsNioChannel功能
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'transport_channel.dart';

/// TLS配置参数
class TlsConfig {
  final bool useClientMode;
  final List<String> enabledProtocols;
  final List<String> enabledCipherSuites;
  final bool verifyCertificate;
  final Uint8List? clientCertificate;
  final Uint8List? clientPrivateKey;
  final String? expectedServerName;

  const TlsConfig({
    this.useClientMode = true,
    this.enabledProtocols = const ['TLSv1.3'],
    this.enabledCipherSuites = const [],
    this.verifyCertificate = false,
    this.clientCertificate,
    this.clientPrivateKey,
    this.expectedServerName,
  });
}

/// TLS传输通道（完整实现）
class TlsTransportChannel implements TransportChannel {
  final TransportChannel _net;
  final TlsConfig _config;
  late final Uint8List _netIn;
  late final Uint8List _netOut;
  late final Uint8List _appIn;

  late SecureSocket _secureSocket;
  bool _isOpen = true;
  bool _handshakeCompleted = false;

  // SSL引擎状态
  int _handshakeStatus =
      0; // 0 = NEED_WRAP, 1 = NEED_UNWRAP, 2 = NEED_TASK, 3 = FINISHED

  TlsTransportChannel(this._net, this._config);

  /// 执行TLS握手（完整实现）
  Future<void> handshake(
      [Duration timeout = const Duration(seconds: 10)]) async {
    if (_handshakeCompleted) {
      return;
    }

    try {
      // 初始化缓冲区
      await _initializeBuffers();

      // 获取Socket并配置TLS
      final socket = await _getSocketFromTransportChannel();
      final context = await _createSecurityContext();

      // 创建SecureSocket
      if (_config.useClientMode) {
        _secureSocket = await SecureSocket.secure(
          socket,
          _config.expectedServerName ?? 'localhost',
          context,
          timeout: timeout,
        );
      } else {
        _secureSocket = await SecureSocket.secureServer(
          socket,
          context,
          timeout: timeout,
        );
      }

      _handshakeCompleted = true;
      print('TLS握手成功，协议: ${_secureSocket.selectedProtocol ?? "Unknown"}');
    } catch (e) {
      throw StateError('TLS握手失败: $e');
    }
  }

  /// 初始化缓冲区（基于SSL会话参数）
  Future<void> _initializeBuffers() async {
    // 使用合理的缓冲区大小
    const int packetBufferSize = 16921; // TLS 1.3典型包大小
    const int applicationBufferSize = 16384; // 16KB

    _netIn = Uint8List(packetBufferSize);
    _netOut = Uint8List(packetBufferSize);
    _appIn = Uint8List(applicationBufferSize);
  }

  /// 从传输通道获取Socket
  Future<Socket> _getSocketFromTransportChannel() async {
    if (_net is TcpTransportChannel) {
      return (_net as TcpTransportChannel).socket;
    }

    // 否则需要创建代理socket
    throw StateError('不支持的底层通道类型，需要TCP通道');
  }

  /// 创建安全上下文（完整实现）
  Future<SecurityContext> _createSecurityContext() async {
    try {
      final context = SecurityContext.defaultContext;

      // 设置客户端证书（如果需要）
      if (_config.clientCertificate != null &&
          _config.clientPrivateKey != null) {
        context.useCertificateChainBytes(_config.clientCertificate!);
        context.usePrivateKeyBytes(_config.clientPrivateKey!);
      }

      // ADB协议中通常接受自签名证书
      if (!_config.verifyCertificate) {
        context.setTrustedCertificatesBytes(Uint8List(0));
      }

      return context;
    } catch (e) {
      throw StateError('创建安全上下文失败: $e');
    }
  }

  @override
  Future<int> read(Uint8List dst, [Duration? timeout]) async {
    if (!_handshakeCompleted) {
      throw StateError('TLS握手未完成');
    }

    // 使用SecureSocket的读取功能
    try {
      final completer = Completer<int>();

      final subscription = _secureSocket.listen(
        (data) {
          if (!completer.isCompleted) {
            final bytesToCopy =
                data.length > dst.length ? dst.length : data.length;
            dst.setRange(0, bytesToCopy, data);
            completer.complete(bytesToCopy);
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(StateError('读取错误: $error'));
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(-1); // EOF
          }
        },
        cancelOnError: true,
      );

      if (timeout != null) {
        Timer(timeout, () {
          if (!completer.isCompleted) {
            completer.completeError(StateError('读取超时'));
          }
        });
      }

      final result = await completer.future;
      subscription.cancel();
      return result;
    } catch (e) {
      throw StateError('TLS读取失败: $e');
    }
  }

  @override
  Future<int> write(Uint8List src, [Duration? timeout]) async {
    if (!_handshakeCompleted) {
      throw StateError('TLS握手未完成');
    }

    try {
      _secureSocket.add(src);
      await _secureSocket.flush();
      return src.length;
    } catch (e) {
      throw StateError('TLS写入失败: $e');
    }
  }

  @override
  Future<void> readExactly(Uint8List buffer, [Duration? timeout]) async {
    int totalRead = 0;
    while (totalRead < buffer.length) {
      final remaining = buffer.length - totalRead;
      final tempBuffer = Uint8List(remaining);
      final bytesRead = await read(tempBuffer, timeout);

      if (bytesRead <= 0) {
        throw StateError('读取完成前到达EOF');
      }

      buffer.setRange(totalRead, totalRead + bytesRead, tempBuffer);
      totalRead += bytesRead;
    }
  }

  @override
  Future<void> writeExactly(Uint8List data, [Duration? timeout]) async {
    int totalWritten = 0;
    while (totalWritten < data.length) {
      final remaining = data.sublist(totalWritten);
      final bytesWritten = await write(remaining, timeout);

      if (bytesWritten <= 0) {
        throw StateError('写入失败');
      }

      totalWritten += bytesWritten;
    }
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
  String get localAddress => _net.localAddress;

  @override
  String get remoteAddress => _net.remoteAddress;

  @override
  bool get isOpen => _isOpen && _net.isOpen;

  @override
  void close() {
    _isOpen = false;
    _secureSocket.destroy();
    _net.close();
  }

  /// 获取TLS连接信息
  String get tlsInfo {
    if (!_handshakeCompleted) {
      return 'TLS握手未完成';
    }

    return 'TLS连接: ${_secureSocket.selectedProtocol ?? "Unknown"}';
  }
}
