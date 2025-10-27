/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

/// ADB流关闭异常
class AdbStreamClosed implements Exception {
  final String message;
  final dynamic cause;
  final int? streamId;

  AdbStreamClosed(this.message, [this.cause, this.streamId]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbStreamClosed: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    if (streamId != null) {
      buffer.write(' (stream: $streamId)');
    }
    return buffer.toString();
  }
}
