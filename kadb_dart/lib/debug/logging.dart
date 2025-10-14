/// 调试日志工具
class Logging {
  static bool _debugEnabled = false;

  /// 设置调试模式
  static void setDebug(bool enabled) {
    _debugEnabled = enabled;
  }

  /// 日志输出函数
  static void log(String message) {
    if (_debugEnabled) {
      print('[ADB] $message');
    }
  }

  /// 条件日志输出
  static void logIf(bool condition, String Function() message) {
    if (condition && _debugEnabled) {
      log(message());
    }
  }
}

