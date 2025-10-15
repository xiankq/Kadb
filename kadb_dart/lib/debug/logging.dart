/// 调试日志工具 - 模拟真实ADB行为
class Logging {
  static bool _debugEnabled = false;
  static bool _verboseEnabled = false;

  /// 设置调试模式
  static void setDebug(bool enabled) {
    _debugEnabled = enabled;
  }

  /// 设置详细模式（显示更多调试信息）
  static void setVerbose(bool enabled) {
    _verboseEnabled = enabled;
  }

  /// 标准日志输出 - 模拟真实ADB的反馈打印
  static void log(String message) {
    if (_debugEnabled) {
      print('[ADB] $message');
    }
  }

  /// 详细日志输出 - 仅在详细模式下显示
  static void verbose(String message) {
    if (_verboseEnabled) {
      print('[ADB-DEBUG] $message');
    }
  }

  /// 错误日志输出 - 总是显示，模拟真实ADB的错误反馈
  static void error(String message) {
    print('[ADB-ERROR] $message');
  }

  /// 警告日志输出 - 总是显示重要警告
  static void warning(String message) {
    print('[ADB-WARN] $message');
  }

  /// 状态信息输出 - 模拟真实ADB的状态反馈
  static void status(String message) {
    print('[ADB] $message');
  }

  /// 条件日志输出
  static void logIf(bool condition, String Function() message) {
    if (condition && _debugEnabled) {
      log(message());
    }
  }

  /// 条件详细日志输出
  static void verboseIf(bool condition, String Function() message) {
    if (condition && _verboseEnabled) {
      verbose(message());
    }
  }
}

