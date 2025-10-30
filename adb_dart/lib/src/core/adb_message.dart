/// ADB消息结构
/// 基于Android ADB协议规范
library;

import 'dart:typed_data';
import 'adb_protocol.dart';

/// ADB消息头部大小（24字节）
const int adbMessageHeaderSize = 24;

/// ADB当前版本
const int adbVersion = 0x01000000;

/// 最大数据载荷大小
const int adbMaxPayload = 256 * 1024;

/// 旧版本最大数据载荷大小（用于兼容性）
const int adbMaxPayloadLegacy = 4096;

/// ADB消息类，表示一个完整的ADB消息
class AdbMessage {
  final int command;
  final int arg0;
  final int arg1;
  final int dataLength;
  final int dataCrc32;
  final int magic;
  final Uint8List? payload;

  const AdbMessage({
    required this.command,
    required this.arg0,
    required this.arg1,
    required this.dataLength,
    required this.dataCrc32,
    required this.magic,
    this.payload,
  });

  /// 从字节数组解析消息头部
  factory AdbMessage.fromHeader(Uint8List header) {
    if (header.length != adbMessageHeaderSize) {
      throw ArgumentError(
          'Invalid header size: ${header.length}, expected: $adbMessageHeaderSize');
    }

    // 边界检查：确保header足够长
    if (header.length < 24) {
      throw ArgumentError('Header too short: ${header.length} bytes');
    }

    final data = ByteData.sublistView(header);

    // 安全地读取所有字段
    try {
      return AdbMessage(
        command: data.getUint32(0, Endian.little),
        arg0: data.getUint32(4, Endian.little),
        arg1: data.getUint32(8, Endian.little),
        dataLength: data.getUint32(12, Endian.little),
        dataCrc32: data.getUint32(16, Endian.little),
        magic: data.getUint32(20, Endian.little),
      );
    } catch (e) {
      throw ArgumentError('Failed to parse header: $e');
    }
  }

  /// 序列化消息头部到字节数组
  Uint8List serializeHeader() {
    print('DEBUG: 序列化头部 - 命令: $command (${command.toRadixString(16)}), arg0: $arg0, arg1: $arg1, dataLength: $dataLength, dataCrc32: $dataCrc32, magic: $magic');

    final buffer = Uint8List(adbMessageHeaderSize);

    // 边界检查：确保所有值都在有效范围内
    if (command < 0 || command > 0xFFFFFFFF) {
      throw ArgumentError('Invalid command value: $command');
    }
    if (arg0 < 0 || arg0 > 0xFFFFFFFF) {
      throw ArgumentError('Invalid arg0 value: $arg0');
    }
    if (arg1 < 0 || arg1 > 0xFFFFFFFF) {
      throw ArgumentError('Invalid arg1 value: $arg1');
    }
    if (dataLength < 0 || dataLength > 0xFFFFFFFF) {
      throw ArgumentError('Invalid dataLength value: $dataLength');
    }
    if (dataCrc32 < 0 || dataCrc32 > 0xFFFFFFFF) {
      throw ArgumentError('Invalid dataCrc32 value: $dataCrc32');
    }
    if (magic < 0 || magic > 0xFFFFFFFF) {
      throw ArgumentError('Invalid magic value: $magic');
    }

    final data = ByteData.sublistView(buffer);

    try {
      data.setUint32(0, command, Endian.little);
      data.setUint32(4, arg0, Endian.little);
      data.setUint32(8, arg1, Endian.little);
      data.setUint32(12, dataLength, Endian.little);
      data.setUint32(16, dataCrc32, Endian.little);
      data.setUint32(20, magic, Endian.little);
    } catch (e) {
      print('DEBUG: 序列化头部失败: $e');
      rethrow;
    }

    return buffer;
  }

  /// 验证消息魔数
  bool isValid() {
    return magic == (command ^ 0xffffffff);
  }

  /// 验证数据校验和（Kadb使用简单校验和，非CRC32）
  bool verifyChecksum() {
    if (payload == null || payload!.isEmpty) {
      return dataCrc32 == 0;
    }

    final checksum = _calculateChecksum(payload!);
    return checksum == dataCrc32;
  }

  /// 计算简单校验和（兼容Kadb实现）
  static int _calculateChecksum(Uint8List data) {
    int checksum = 0;
    for (int i = 0; i < data.length; i++) {
      checksum += data[i] & 0xFF;
    }
    // 确保校验和是32位无符号整数
    return checksum & 0xFFFFFFFF;
  }

  /// 创建CONNECT消息
  factory AdbMessage.connect(int version, int maxData, String systemIdentity) {
    final payload = Uint8List.fromList(systemIdentity.codeUnits);
    final checksum = _calculateChecksum(payload);

    return AdbMessage(
      command: AdbProtocol.cmdCnxn,
      arg0: version,
      arg1: maxData,
      dataLength: payload.length,
      dataCrc32: checksum,
      magic: AdbProtocol.cmdCnxn ^ 0xffffffff,
      payload: payload,
    );
  }

  /// 创建AUTH消息
  factory AdbMessage.auth(int type, Uint8List data) {
    final checksum = data.isEmpty ? 0 : _calculateChecksum(data);

    return AdbMessage(
      command: AdbProtocol.cmdAuth,
      arg0: type,
      arg1: 0,
      dataLength: data.length,
      dataCrc32: checksum,
      magic: AdbProtocol.cmdAuth ^ 0xffffffff,
      payload: data,
    );
  }

  /// 创建OPEN消息
  factory AdbMessage.open(int localId, String destination) {
    final payload = Uint8List.fromList(destination.codeUnits);
    final checksum = _calculateChecksum(payload);

    return AdbMessage(
      command: AdbProtocol.cmdOpen,
      arg0: localId,
      arg1: 0,
      dataLength: payload.length,
      dataCrc32: checksum,
      magic: AdbProtocol.cmdOpen ^ 0xffffffff,
      payload: payload,
    );
  }

  /// 创建OKAY消息
  factory AdbMessage.okay(int localId, int remoteId) {
    return AdbMessage(
      command: AdbProtocol.cmdOkay,
      arg0: localId,
      arg1: remoteId,
      dataLength: 0,
      dataCrc32: 0,
      magic: AdbProtocol.cmdOkay ^ 0xffffffff,
    );
  }

  /// 创建CLOSE消息
  factory AdbMessage.close(int localId, int remoteId) {
    return AdbMessage(
      command: AdbProtocol.cmdClse,
      arg0: localId,
      arg1: remoteId,
      dataLength: 0,
      dataCrc32: 0,
      magic: AdbProtocol.cmdClse ^ 0xffffffff,
    );
  }

  /// 创建WRITE消息
  factory AdbMessage.write(int localId, int remoteId, Uint8List data) {
    final checksum = data.isEmpty ? 0 : _calculateChecksum(data);

    return AdbMessage(
      command: AdbProtocol.cmdWrte,
      arg0: localId,
      arg1: remoteId,
      dataLength: data.length,
      dataCrc32: checksum,
      magic: AdbProtocol.cmdWrte ^ 0xffffffff,
      payload: data,
    );
  }

  /// 创建STLS消息
  factory AdbMessage.stls(int version) {
    return AdbMessage(
      command: AdbProtocol.cmdStls,
      arg0: version,
      arg1: 0,
      dataLength: 0,
      dataCrc32: 0,
      magic: AdbProtocol.cmdStls ^ 0xffffffff,
    );
  }

  @override
  String toString() {
    return 'AdbMessage{command: ${AdbProtocol.getCommandName(command)}(0x${command.toRadixString(16)}), '
        'arg0: $arg0, arg1: $arg1, dataLength: $dataLength, '
        'dataCrc32: 0x${dataCrc32.toRadixString(16)}, valid: ${isValid()}}';
  }
}
