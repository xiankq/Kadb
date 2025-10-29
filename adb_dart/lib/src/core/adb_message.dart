/// ADB消息结构
/// 基于Android ADB协议规范
library;

import 'dart:typed_data';
import '../utils/crc32.dart';
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

    final data = ByteData.sublistView(header);
    return AdbMessage(
      command: data.getUint32(0, Endian.little),
      arg0: data.getUint32(4, Endian.little),
      arg1: data.getUint32(8, Endian.little),
      dataLength: data.getUint32(12, Endian.little),
      dataCrc32: data.getUint32(16, Endian.little),
      magic: data.getUint32(20, Endian.little),
    );
  }

  /// 序列化消息头部到字节数组
  Uint8List serializeHeader() {
    final buffer = Uint8List(adbMessageHeaderSize);
    final data = ByteData.sublistView(buffer);

    data.setUint32(0, command, Endian.little);
    data.setUint32(4, arg0, Endian.little);
    data.setUint32(8, arg1, Endian.little);
    data.setUint32(12, dataLength, Endian.little);
    data.setUint32(16, dataCrc32, Endian.little);
    data.setUint32(20, magic, Endian.little);

    return buffer;
  }

  /// 验证消息魔数
  bool isValid() {
    return magic == (command ^ 0xffffffff);
  }

  /// 验证数据CRC32
  bool verifyCrc32() {
    if (payload == null || payload!.isEmpty) {
      return dataCrc32 == 0;
    }

    final crc32 = _calculateCrc32(payload!);
    return crc32 == dataCrc32;
  }

  /// 计算CRC32校验和
  static int _calculateCrc32(Uint8List data) {
    return Crc32.calculate(data);
  }

  /// 创建CONNECT消息
  factory AdbMessage.connect(int version, int maxData, String systemIdentity) {
    final payload = Uint8List.fromList(systemIdentity.codeUnits);
    final crc32 = _calculateCrc32(payload);

    return AdbMessage(
      command: AdbProtocol.cmdCnxn,
      arg0: version,
      arg1: maxData,
      dataLength: payload.length,
      dataCrc32: crc32,
      magic: AdbProtocol.cmdCnxn ^ 0xffffffff,
      payload: payload,
    );
  }

  /// 创建AUTH消息
  factory AdbMessage.auth(int type, Uint8List data) {
    final crc32 = data.isEmpty ? 0 : _calculateCrc32(data);

    return AdbMessage(
      command: AdbProtocol.cmdAuth,
      arg0: type,
      arg1: 0,
      dataLength: data.length,
      dataCrc32: crc32,
      magic: AdbProtocol.cmdAuth ^ 0xffffffff,
      payload: data,
    );
  }

  /// 创建OPEN消息
  factory AdbMessage.open(int localId, String destination) {
    final payload = Uint8List.fromList(destination.codeUnits);
    final crc32 = _calculateCrc32(payload);

    return AdbMessage(
      command: AdbProtocol.cmdOpen,
      arg0: localId,
      arg1: 0,
      dataLength: payload.length,
      dataCrc32: crc32,
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
    final crc32 = data.isEmpty ? 0 : _calculateCrc32(data);

    return AdbMessage(
      command: AdbProtocol.cmdWrte,
      arg0: localId,
      arg1: remoteId,
      dataLength: data.length,
      dataCrc32: crc32,
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
