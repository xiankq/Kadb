/// TLS错误映射器
/// 将TLS相关异常映射为ADB特定异常
library tls_error_mapper;

import '../exception/adb_exceptions.dart';

/// TLS错误映射器
class TlsErrorMapper {
  /// 将Throwable映射为更具体的ADB异常
  static Exception map(dynamic throwable) {
    final messages = _buildMessageChain(throwable);

    // 证书相关错误
    if (messages.contains('certificate_required') ||
        messages.contains('unknown_ca') ||
        messages.contains('access_denied') ||
        messages.contains('certificate_unknown')) {
      return AdbPairAuthException('TLS证书认证失败: ${throwable.toString()}');
    }

    // 超时错误
    if (_containsTimeoutException(throwable)) {
      return AdbConnectionException('TLS握手超时', throwable);
    }

    // 握手相关错误
    if (_containsSslException(throwable)) {
      final message = throwable.toString();
      final errorMessage = 'TLS握手失败${message.isNotEmpty ? ': $message' : ''}';
      return AdbConnectionException(errorMessage, throwable);
    }

    // 默认返回原始异常
    if (throwable is Exception) {
      return throwable;
    } else {
      return AdbException('TLS错误: ${throwable.toString()}', throwable);
    }
  }

  /// 构建错误消息链
  static String _buildMessageChain(dynamic throwable) {
    final buffer = StringBuffer();
    dynamic current = throwable;

    while (current != null) {
      final message = current.toString().toLowerCase();
      buffer.writeln(message);
      current = _getCause(current);
    }

    return buffer.toString();
  }

  /// 获取异常原因
  static dynamic _getCause(dynamic throwable) {
    try {
      // 尝试获取cause属性
      if (throwable is Exception) {
        // 对于Dart异常，通常没有cause属性，返回null
        return null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 检查是否包含超时异常
  static bool _containsTimeoutException(dynamic throwable) {
    dynamic current = throwable;
    while (current != null) {
      if (current.toString().contains('timeout') ||
          current.toString().contains('TimeoutException')) {
        return true;
      }
      current = _getCause(current);
    }
    return false;
  }

  /// 检查是否包含SSL异常
  static bool _containsSslException(dynamic throwable) {
    dynamic current = throwable;
    while (current != null) {
      final message = current.toString().toLowerCase();
      if (message.contains('ssl') ||
          message.contains('handshake') ||
          message.contains('certificate')) {
        return true;
      }
      current = _getCause(current);
    }
    return false;
  }
}
