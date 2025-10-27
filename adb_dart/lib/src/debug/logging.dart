/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

/// 日志级别枚举
enum LogLevel { debug, info, warning, error }

/// 日志记录器
class Logger {
  static LogLevel _currentLevel = LogLevel.info;
  static bool _enabled = true;

  /// 设置日志级别
  static void setLogLevel(LogLevel level) {
    _currentLevel = level;
  }

  /// 启用/禁用日志
  static void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// 检查是否应该记录日志
  static bool _shouldLog(LogLevel level) {
    if (!_enabled) return false;
    return level.index >= _currentLevel.index;
  }

  /// 调试日志
  static void debug(String message) {
    if (_shouldLog(LogLevel.debug)) {
      print('[DEBUG] $message');
    }
  }

  /// 信息日志
  static void info(String message) {
    if (_shouldLog(LogLevel.info)) {
      print('[INFO] $message');
    }
  }

  /// 警告日志
  static void warning(String message) {
    if (_shouldLog(LogLevel.warning)) {
      print('[WARNING] $message');
    }
  }

  /// 错误日志
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    if (_shouldLog(LogLevel.error)) {
      print('[ERROR] $message');
      if (error != null) {
        print('  Error: $error');
      }
      if (stackTrace != null) {
        print('  StackTrace: $stackTrace');
      }
    }
  }

  /// 记录异常
  static void exception(String context, dynamic error, StackTrace stackTrace) {
    error('$context failed', error, stackTrace);
  }
}
