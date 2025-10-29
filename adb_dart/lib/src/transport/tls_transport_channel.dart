/// TLS传输通道实现
///
/// 提供基于TLS加密的传输通道，支持TLS 1.3协议
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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

/// TLS传输通道
class TlsTransportChannel implements TransportChannel {
  final TransportChannel _underlyingChannel;
  late final SecureSocket _secureSocket;
  final TlsConfig _config;
  bool _isOpen = true;
  bool _handshakeCompleted = false;

  TlsTransportChannel(this._underlyingChannel, this._config);

  /// 执行TLS握手
  Future<void> handshake(
      [Duration timeout = const Duration(seconds: 10)]) async {
    if (_handshakeCompleted) {
      return;
    }

    try {
      // 将底层通道转换为Socket
      final socket = await _getSocketFromTransportChannel();

      // 配置TLS上下文
      final context = await _createSecurityContext();

      // 创建安全socket
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
    } catch (e) {
      throw StateError('TLS握手失败: $e');
    }
  }

  /// 从传输通道获取Socket
  Future<Socket> _getSocketFromTransportChannel() async {
    // 如果是TCP传输通道，直接获取socket
    if (_underlyingChannel is TcpTransportChannel) {
      return (_underlyingChannel as TcpTransportChannel).socket;
    }

    // 否则需要创建代理socket
    throw StateError('不支持的底层通道类型，需要TCP通道');
  }

  /// 创建安全上下文
  Future<SecurityContext> _createSecurityContext() async {
    final context = SecurityContext.defaultContext;

    // 如果需要客户端认证，设置证书
    if (_config.clientCertificate != null && _config.clientPrivateKey != null) {
      try {
        // 设置客户端证书
        context.useCertificateChainBytes(_config.clientCertificate!);
        context.usePrivateKeyBytes(_config.clientPrivateKey!);
      } catch (e) {
        throw StateError('设置客户端证书失败: $e');
      }
    }

    // 如果不验证证书，接受所有证书
    if (!_config.verifyCertificate) {
      context.setTrustedCertificatesBytes(Uint8List(0)); // 清空信任证书
      // 注意：在生产环境中，应该始终验证证书
    }

    return context;
  }

  @override
  Future<int> read(Uint8List buffer, [Duration? timeout]) async {
    if (!_handshakeCompleted) {
      throw StateError('TLS握手未完成');
    }

    try {
      final completer = Completer<int>();

      if (timeout != null) {
        Timer(timeout, () {
          if (!completer.isCompleted) {
            completer.completeError(StateError('读取超时'));
          }
        });
      }

      final subscription = _secureSocket.listen(
        (data) {
          if (!completer.isCompleted) {
            final bytesToCopy =
                data.length > buffer.length ? buffer.length : data.length;
            buffer.setRange(0, bytesToCopy, data);
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

      final result = await completer.future;
      subscription.cancel();
      return result;
    } catch (e) {
      throw StateError('TLS读取失败: $e');
    }
  }

  @override
  Future<int> write(Uint8List data, [Duration? timeout]) async {
    if (!_handshakeCompleted) {
      throw StateError('TLS握手未完成');
    }

    try {
      final completer = Completer<int>();

      if (timeout != null) {
        Timer(timeout, () {
          if (!completer.isCompleted) {
            completer.completeError(StateError('写入超时'));
          }
        });
      }

      _secureSocket.add(data);
      await _secureSocket.flush();
      completer.complete(data.length);

      return await completer.future;
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
  String get localAddress => _underlyingChannel.localAddress;

  @override
  String get remoteAddress => _underlyingChannel.remoteAddress;

  @override
  bool get isOpen => _isOpen && _underlyingChannel.isOpen;

  @override
  void close() {
    _isOpen = false;
    _secureSocket.destroy();
    _underlyingChannel.close();
  }

  /// 获取TLS连接信息
  String get tlsInfo {
    if (!_handshakeCompleted) {
      return 'TLS握手未完成';
    }

    return 'TLS连接: ${_secureSocket.selectedProtocol ?? "Unknown"}';
  }
}
