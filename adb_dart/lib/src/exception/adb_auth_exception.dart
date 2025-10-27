/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

/// ADB认证异常
class AdbAuthException implements Exception {
  final String message;
  final dynamic cause;
  final String? authType;

  AdbAuthException(this.message, [this.cause, this.authType]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbAuthException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    if (authType != null) {
      buffer.write(' (auth type: $authType)');
    }
    return buffer.toString();
  }
}
