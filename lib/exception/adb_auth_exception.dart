/// ADB认证异常
/// 当需要ADB权限时抛出
class AdbAuthException implements Exception {
  final String message;

  AdbAuthException([this.message = '需要ADB权限']);

  @override
  String toString() => 'AdbAuthException: $message';
}