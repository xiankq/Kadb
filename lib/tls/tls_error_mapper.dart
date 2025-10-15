import '../exception/adb_auth_exception.dart';

/// TLS错误映射器
/// 用于将TLS相关异常映射为ADB特定的异常
class TlsErrorMapper {
  /// 映射异常
  /// [throwable] 原始异常
  /// 返回映射后的异常
  static Exception map(Exception throwable) {
    final messages = _extractExceptionMessages(throwable);

    // 检查证书相关错误
    if (_containsCertificateError(messages)) {
      return AdbAuthException();
    }

    // 检查超时错误
    if (_isTimeoutError(throwable)) {
      return Exception('TLS握手超时');
    }

    // 检查TLS握手错误
    if (_isTlsHandshakeError(throwable)) {
      final message = throwable.toString();
      return Exception('TLS握手失败${message.isNotEmpty ? ': $message' : ''}');
    }

    return throwable;
  }

  /// 提取异常消息链
  static String _extractExceptionMessages(Exception throwable) {
    final messages = StringBuffer();
    var current = throwable;

    while (current != null) {
      final message = current.toString().toLowerCase();
      messages.writeln(message);
      // Dart异常没有cause属性，直接返回当前异常的消息
      break;
    }

    return messages.toString();
  }

  /// 检查是否包含证书错误
  static bool _containsCertificateError(String messages) {
    return messages.contains('certificate_required') ||
        messages.contains('unknown_ca') ||
        messages.contains('access_denied') ||
        messages.contains('certificate_unknown');
  }

  /// 检查是否为超时错误
  static bool _isTimeoutError(Exception throwable) {
    // Dart中的超时异常检查
    return throwable.toString().toLowerCase().contains('timeout') ||
        throwable.toString().toLowerCase().contains('timed out');
  }

  /// 检查是否为TLS握手错误
  static bool _isTlsHandshakeError(Exception throwable) {
    // Dart中的TLS相关异常检查
    return throwable.toString().toLowerCase().contains('ssl') ||
        throwable.toString().toLowerCase().contains('tls') ||
        throwable.toString().toLowerCase().contains('handshake');
  }
}

// 扩展Exception类以支持cause属性
extension ExceptionCause on Exception {
  Exception? get cause {
    // Dart标准异常没有cause属性，这里返回null
    // 在实际使用中，可能需要根据具体异常类型处理
    return null;
  }
}
