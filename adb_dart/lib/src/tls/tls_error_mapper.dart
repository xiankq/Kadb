/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:io';

/// TLS错误映射器，将TLS错误转换为ADB特定的异常
class TlsErrorMapper {
  /// 映射TLS异常到ADB异常
  static Exception map(dynamic error) {
    if (error is SocketException) {
      return _mapSocketException(error);
    } else if (error is TlsException) {
      return _mapTlsException(error);
    } else if (error is HandshakeException) {
      return _mapHandshakeException(error);
    }

    // 默认映射
    return Exception('TLS error: ${error.toString()}');
  }

  /// 映射Socket异常
  static Exception _mapSocketException(SocketException error) {
    final message = error.message.toLowerCase();

    if (message.contains('connection refused')) {
      return Exception('TLS connection refused: ${error.message}');
    } else if (message.contains('connection reset')) {
      return Exception('TLS connection reset: ${error.message}');
    } else if (message.contains('timeout')) {
      return Exception('TLS connection timeout: ${error.message}');
    }

    return Exception('TLS socket error: ${error.message}');
  }

  /// 映射TLS异常
  static Exception _mapTlsException(TlsException error) {
    final message = error.message.toLowerCase();

    if (message.contains('certificate')) {
      return Exception('TLS certificate error: ${error.message}');
    } else if (message.contains('protocol')) {
      return Exception('TLS protocol error: ${error.message}');
    } else if (message.contains('handshake')) {
      return Exception('TLS handshake error: ${error.message}');
    }

    return Exception('TLS error: ${error.message}');
  }

  /// 映射握手异常
  static Exception _mapHandshakeException(HandshakeException error) {
    final message = error.message.toLowerCase();

    if (message.contains('certificate')) {
      return Exception('TLS handshake certificate error: ${error.message}');
    } else if (message.contains('protocol')) {
      return Exception('TLS handshake protocol error: ${error.message}');
    } else if (message.contains('cipher')) {
      return Exception('TLS handshake cipher error: ${error.message}');
    }

    return Exception('TLS handshake error: ${error.message}');
  }
}
