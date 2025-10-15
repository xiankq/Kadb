/// ADB流已关闭异常
/// 当尝试操作已关闭的ADB流时抛出
class AdbStreamClosed implements Exception {
  final int localId;
  final String message;

  AdbStreamClosed(this.localId, [String? message]) : message = message ?? 'ADB流已关闭，本地ID: 0x${localId.toRadixString(16)}';

  @override
  String toString() => 'AdbStreamClosed: $message';
}