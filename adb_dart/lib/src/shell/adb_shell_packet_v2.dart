/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

/// Shell v2协议数据包类型定义
class AdbShellPacketV2 {
  /// 数据包类型ID
  static const int idStdin = 0;
  static const int idStdout = 1;
  static const int idStderr = 2;
  static const int idExit = 3;
  static const int idCloseStdin = 4;
  static const int idWindowSizeChange = 5;
  static const int idInvalid = 255;

  /// 获取数据包类型的字符串表示
  static String getPacketTypeName(int id) {
    switch (id) {
      case idStdin:
        return "STDIN";
      case idStdout:
        return "STDOUT";
      case idStderr:
        return "STDERR";
      case idExit:
        return "EXIT";
      case idCloseStdin:
        return "CLOSE_STDIN";
      case idWindowSizeChange:
        return "WINDOW_SIZE_CHANGE";
      default:
        return "INVALID($id)";
    }
  }
}
