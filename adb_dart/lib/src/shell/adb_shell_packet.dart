/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:typed_data';
import 'adb_shell_packet_v2.dart';

/// Shell数据包基类
abstract class AdbShellPacket {
  /// 数据包ID
  abstract final int id;

  /// 载荷数据
  abstract final Uint8List payload;

  @override
  String toString() {
    return '${AdbShellPacketV2.getPacketTypeName(id)}: ${_getPayloadString()}';
  }

  String _getPayloadString() {
    if (payload.isEmpty) return "";

    try {
      return String.fromCharCodes(payload);
    } catch (e) {
      return "Binary data (${payload.length} bytes)";
    }
  }
}

/// 标准输出数据包
class StdOutPacket extends AdbShellPacket {
  @override
  final int id = AdbShellPacketV2.idStdout;
  @override
  final Uint8List payload;

  StdOutPacket(this.payload);

  @override
  String toString() => "STDOUT: ${String.fromCharCodes(payload)}";
}

/// 标准错误数据包
class StdErrorPacket extends AdbShellPacket {
  @override
  final int id = AdbShellPacketV2.idStderr;
  @override
  final Uint8List payload;

  StdErrorPacket(this.payload);

  @override
  String toString() => "STDERR: ${String.fromCharCodes(payload)}";
}

/// 退出码数据包
class ExitPacket extends AdbShellPacket {
  @override
  final int id = AdbShellPacketV2.idExit;
  @override
  final Uint8List payload;

  ExitPacket(this.payload) {
    if (payload.length != 1) {
      throw ArgumentError('Exit packet payload must be exactly 1 byte');
    }
  }

  /// 获取退出码
  int get exitCode => payload[0];

  @override
  String toString() => "EXIT: $exitCode";
}

/// 关闭标准输入数据包
class CloseStdinPacket extends AdbShellPacket {
  @override
  final int id = AdbShellPacketV2.idCloseStdin;
  @override
  final Uint8List payload;

  CloseStdinPacket([Uint8List? payload]) : payload = payload ?? Uint8List(0);

  @override
  String toString() => "CLOSE_STDIN";
}

/// 窗口大小变更数据包
class WindowSizeChangePacket extends AdbShellPacket {
  @override
  final int id = AdbShellPacketV2.idWindowSizeChange;
  @override
  final Uint8List payload;

  WindowSizeChangePacket(this.payload) {
    if (payload.length != 8) {
      throw ArgumentError(
        'Window size change packet payload must be exactly 8 bytes',
      );
    }
  }

  /// 获取窗口宽度
  int get width {
    final buffer = ByteData.sublistView(payload);
    return buffer.getUint32(0, Endian.little);
  }

  /// 获取窗口高度
  int get height {
    final buffer = ByteData.sublistView(payload);
    return buffer.getUint32(4, Endian.little);
  }

  @override
  String toString() => "WINDOW_SIZE_CHANGE: $width x $height";
}

/// 标准输入数据包
class StdInPacket extends AdbShellPacket {
  @override
  final int id = AdbShellPacketV2.idStdin;
  @override
  final Uint8List payload;

  StdInPacket(this.payload);

  @override
  String toString() => "STDIN: ${String.fromCharCodes(payload)}";
}

/// Shell数据包工厂类
class AdbShellPacketFactory {
  /// 从原始数据创建数据包
  static AdbShellPacket? createPacket(int packetId, Uint8List payload) {
    switch (packetId) {
      case AdbShellPacketV2.idStdin:
        return StdInPacket(payload);
      case AdbShellPacketV2.idStdout:
        return StdOutPacket(payload);
      case AdbShellPacketV2.idStderr:
        return StdErrorPacket(payload);
      case AdbShellPacketV2.idExit:
        return ExitPacket(payload);
      case AdbShellPacketV2.idCloseStdin:
        return CloseStdinPacket(payload);
      case AdbShellPacketV2.idWindowSizeChange:
        return WindowSizeChangePacket(payload);
      default:
        print('未知的Shell数据包类型: $packetId');
        return null;
    }
  }

  /// 从原始数据解析数据包
  static AdbShellPacket? parseFromData(Uint8List data) {
    if (data.isEmpty) return null;

    final packetId = data[0];
    final payload = data.sublist(1);

    return createPacket(packetId, payload);
  }

  /// 创建标准输出数据包
  static StdOutPacket createStdout(String data) {
    return StdOutPacket(Uint8List.fromList(data.codeUnits));
  }

  /// 创建标准错误数据包
  static StdErrorPacket createStderr(String data) {
    return StdErrorPacket(Uint8List.fromList(data.codeUnits));
  }

  /// 创建退出数据包
  static ExitPacket createExit(int exitCode) {
    return ExitPacket(Uint8List.fromList([exitCode & 0xFF]));
  }

  /// 创建标准输入数据包
  static StdInPacket createStdin(String data) {
    return StdInPacket(Uint8List.fromList(data.codeUnits));
  }
}
