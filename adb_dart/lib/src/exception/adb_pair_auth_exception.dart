/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

/// ADB配对认证异常
class AdbPairAuthException implements Exception {
  final String message;
  final dynamic cause;
  final String? pairingCode;

  AdbPairAuthException(this.message, [this.cause, this.pairingCode]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbPairAuthException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    if (pairingCode != null) {
      buffer.write(' (pairing code: $pairingCode)');
    }
    return buffer.toString();
  }
}
