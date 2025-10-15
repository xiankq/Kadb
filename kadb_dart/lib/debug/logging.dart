/// 调试日志工具
class Logging {
  static bool _debugEnabled = false;
  static bool _verboseEnabled = false;

  static void setDebug(bool enabled) {
    _debugEnabled = enabled;
  }

  static void setVerbose(bool enabled) {
    _verboseEnabled = enabled;
  }

  static void log(String message) {
    if (_debugEnabled) {
      print(message);
    }
  }

  static void verbose(String message) {
    if (_verboseEnabled) {
      print(message);
    }
  }

  static void error(String message) {
    print(message);
  }

  static void warning(String message) {
    print(message);
  }

  static void status(String message) {
    print(message);
  }

  static void logIf(bool condition, String Function() message) {
    if (condition && _debugEnabled) {
      log(message());
    }
  }

  static void verboseIf(bool condition, String Function() message) {
    if (condition && _verboseEnabled) {
      verbose(message());
    }
  }
}

