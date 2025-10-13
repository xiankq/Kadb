/// ADB配对认证异常
/// 当需要配对或信任缺失时抛出
class AdbPairAuthException implements Exception {
  final String message;

  AdbPairAuthException([this.message = '需要配对或信任缺失']);

  @override
  String toString() => 'AdbPairAuthException: $message';
}