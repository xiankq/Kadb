import 'dart:typed_data';

/// ADB Shell数据包常量
class AdbShellPacket {
  static const int idStdout = 1;
  static const int idStderr = 2;
  static const int idExit = 3;
  static const int idCloseStdin = 4;
  static const int idWindowSizeChange = 5;
  static const int idStdin = 0;
  static const int idInvalid = -1;
}

/// ADB Shell数据包基类
abstract class AdbShellPacketBase {
  final Uint8List payload;

  AdbShellPacketBase(this.payload);

  /// 获取数据包ID
  int get id;

  @override
  String toString() => 'AdbShellPacket{id: $id, payload: ${payload.length} bytes}';
}

/// 标准输出数据包
class StdOut extends AdbShellPacketBase {
  StdOut(super.payload);

  @override
  int get id => AdbShellPacket.idStdout;

  @override
  String toString() => 'STDOUT: ${String.fromCharCodes(payload)}';
}

/// 标准错误数据包
class StdError extends AdbShellPacketBase {
  StdError(super.payload);

  @override
  int get id => AdbShellPacket.idStderr;

  @override
  String toString() => 'STDERR: ${String.fromCharCodes(payload)}';
}

/// 退出数据包
class Exit extends AdbShellPacketBase {
  Exit(super.payload);

  @override
  int get id => AdbShellPacket.idExit;

  @override
  String toString() => 'EXIT: ${payload.isNotEmpty ? payload[0] : 0}';
}

/// 关闭标准输入数据包
class CloseStdin extends AdbShellPacketBase {
  CloseStdin(super.payload);

  @override
  int get id => AdbShellPacket.idCloseStdin;

  @override
  String toString() => 'CLOSE_STDIN';
}

/// 窗口大小变化数据包
class WindowSizeChange extends AdbShellPacketBase {
  final int rows;
  final int cols;
  final int xpixel;
  final int ypixel;

  WindowSizeChange(super.payload, this.rows, this.cols, this.xpixel, this.ypixel);

  @override
  int get id => AdbShellPacket.idWindowSizeChange;

  @override
  String toString() => 'WINDOW_SIZE_CHANGE: ${rows}x$cols (${xpixel}x$ypixel)';
}

/// 无效数据包
class InvalidPacket extends AdbShellPacketBase {
  InvalidPacket(super.payload);

  @override
  int get id => AdbShellPacket.idInvalid;

  @override
  String toString() => 'INVALID_PACKET';
}