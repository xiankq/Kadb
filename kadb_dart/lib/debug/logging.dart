/// 调试日志工具
class Logging {
  /// 日志输出函数
  static void log(String message) {
    print('[ADB] $message');
  }
  
  /// 条件日志输出
  static void logIf(bool condition, String Function() message) {
    if (condition) {
      log(message());
    }
  }
}

