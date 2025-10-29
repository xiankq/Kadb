/// ADB异常定义
/// 包含各种ADB操作可能抛出的异常

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
  AdbProtocolException(super.message, [super.cause]);
}

/// ADB连接异常
class AdbConnectionException extends AdbException {
  AdbConnectionException(super.message, [super.cause]);
}

/// ADB认证异常
class AdbAuthException extends AdbException {
  AdbAuthException(super.message, [super.cause]);
}

/// ADB流异常
class AdbStreamException extends AdbException {
  AdbStreamException(super.message, [super.cause]);
}

/// ADB配对认证异常
class AdbPairAuthException extends AdbException {
  AdbPairAuthException(super.message, [super.cause]);
}

/// ADB流已关闭异常
class AdbStreamClosed extends AdbException {
  AdbStreamClosed() : super('Stream has been closed');
}

/// TLS异常
class TlsException extends AdbException {
  TlsException(super.message, [super.cause]);
}

/// 文件操作异常
class AdbFileException extends AdbException {
  AdbFileException(super.message, [super.cause]);
}
