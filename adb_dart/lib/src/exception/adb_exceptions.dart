/**
 * ADB异常定义
 * 包含各种ADB操作可能抛出的异常
 */

library adb_exceptions;

/// ADB基础异常
class AdbException implements Exception {
  final String message;
  final dynamic cause;

  AdbException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return 'AdbException: $message, cause: $cause';
    }
    return 'AdbException: $message';
  }
}

/// ADB协议异常
class AdbProtocolException extends AdbException {
  AdbProtocolException(String message, [dynamic cause]) : super(message, cause);
}

/// ADB连接异常
class AdbConnectionException extends AdbException {
  AdbConnectionException(String message, [dynamic cause]) : super(message, cause);
}

/// ADB认证异常
class AdbAuthException extends AdbException {
  AdbAuthException(String message, [dynamic cause]) : super(message, cause);
}

/// ADB流异常
class AdbStreamException extends AdbException {
  AdbStreamException(String message, [dynamic cause]) : super(message, cause);
}

/// ADB配对认证异常
class AdbPairAuthException extends AdbException {
  AdbPairAuthException(String message, [dynamic cause]) : super(message, cause);
}

/// ADB流已关闭异常
class AdbStreamClosed extends AdbException {
  AdbStreamClosed() : super('Stream has been closed');
}

/// TLS异常
class TlsException extends AdbException {
  TlsException(String message, [dynamic cause]) : super(message, cause);
}

/// 文件操作异常
class AdbFileException extends AdbException {
  AdbFileException(String message, [dynamic cause]) : super(message, cause);
}