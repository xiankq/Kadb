/// Shell v2协议包格式定义
/// 定义Shell v2协议中各种包的类型和结构
library shell_packet_v2;

import 'dart:typed_data';

/// Shell v2协议包类型常量
class AdbShellPacketV2 {
  /// 标准输入
  static const int idStdin = 0;

  /// 标准输出
  static const int idStdout = 1;

  /// 标准错误输出
  static const int idStderr = 2;

  /// 退出码
  static const int idExit = 3;

  /// 关闭标准输入
  static const int idCloseStdin = 4;

  /// 窗口大小改变
  static const int idWindowSizeChange = 5;

  /// 无效包ID
  static const int idInvalid = 255;

  /// 获取包类型的名称（用于调试）
  static String getPacketName(int id) {
    switch (id) {
      case idStdin:
        return 'STDIN';
      case idStdout:
        return 'STDOUT';
      case idStderr:
        return 'STDERR';
      case idExit:
        return 'EXIT';
      case idCloseStdin:
        return 'CLOSE_STDIN';
      case idWindowSizeChange:
        return 'WINDOW_SIZE_CHANGE';
      case idInvalid:
        return 'INVALID';
      default:
        return 'UNKNOWN($id)';
    }
  }
}

/// Shell协议包基础类
abstract class AdbShellPacket {
  final int id;
  final Uint8List? payload;

  AdbShellPacket(this.id, this.payload);

  @override
  String toString() => 'AdbShellPacket(id: ${AdbShellPacketV2.getPacketName(id)}, payloadLength: ${payload?.length ?? 0})';
}

/// 标准输出包
class StdOutPacket extends AdbShellPacket {
  StdOutPacket(Uint8List payload) : super(AdbShellPacketV2.idStdout, payload);

  String get content => String.fromCharCodes(payload ?? []);
}

/// 标准错误包
class StdErrPacket extends AdbShellPacket {
  StdErrPacket(Uint8List payload) : super(AdbShellPacketV2.idStderr, payload);

  String get content => String.fromCharCodes(payload ?? []);
}

/// 退出码包
class ExitPacket extends AdbShellPacket {
  ExitPacket(Uint8List payload) : super(AdbShellPacketV2.idExit, payload);

  int get exitCode => payload != null && payload!.isNotEmpty ? payload![0] : -1;
}

/// 标准输入包
class StdInPacket extends AdbShellPacket {
  StdInPacket(Uint8List payload) : super(AdbShellPacketV2.idStdin, payload);
}

/// 关闭标准输入包
class CloseStdInPacket extends AdbShellPacket {
  CloseStdInPacket() : super(AdbShellPacketV2.idCloseStdin, null);
}

/// 窗口大小改变包
class WindowSizeChangePacket extends AdbShellPacket {
  WindowSizeChangePacket(Uint8List payload) : super(AdbShellPacketV2.idWindowSizeChange, payload);

  /// 解析窗口大小信息
  /// 格式: [rows, cols, xpixel, ypixel] (各4字节)
  Map<String, int> get windowSize {
    if (payload == null || payload!.length < 16) {
      return {};
    }
    final buffer = ByteData.view(payload!.buffer);
    return {
      'rows': buffer.getUint32(0, Endian.little),
      'cols': buffer.getUint32(4, Endian.little),
      'xpixel': buffer.getUint32(8, Endian.little),
      'ypixel': buffer.getUint32(12, Endian.little),
    };
  }
}