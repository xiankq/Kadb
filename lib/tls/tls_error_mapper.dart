/// TLS错误映射器
class TlsErrorMapper {
  /// 映射异常
  static Exception map(Exception throwable) {
    final messages = _extractExceptionMessages(throwable);

    if (_containsCertificateError(messages)) {
      return Exception('ADB认证失败: 证书错误');
    }

    if (_isTimeoutError(throwable)) {
      return Exception('TLS握手超时');
    }

    if (_isTlsHandshakeError(throwable)) {
      final message = throwable.toString();
      return Exception('TLS握手失败${message.isNotEmpty ? ': $message' : ''}');
    }

    return throwable;
  }

  /// 提取异常消息链
  static String _extractExceptionMessages(Exception throwable) {
    return throwable.toString().toLowerCase();
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
    return throwable.toString().toLowerCase().contains('timeout') ||
        throwable.toString().toLowerCase().contains('timed out');
  }

  /// 检查是否为TLS握手错误
  static bool _isTlsHandshakeError(Exception throwable) {
    return throwable.toString().toLowerCase().contains('ssl') ||
        throwable.toString().toLowerCase().contains('tls') ||
        throwable.toString().toLowerCase().contains('handshake');
  }
}
