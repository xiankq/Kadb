/// ADB消息格式实现
///
/// 表示一个完整的ADB消息，包含24字节头部和可选的数据载荷
/// 支持序列化和反序列化，以及调试信息输出
library;

import 'dart:convert';
import 'dart:typed_data';
import 'adb_protocol.dart';

/// ADB消息类
class AdbMessage {
  /// 命令标识符
  final int command;

  /// 第一个参数
  final int arg0;

  /// 第二个参数
  final int arg1;

  /// 数据载荷长度
  final int payloadLength;

  /// 数据校验和
  final int checksum;

  /// 魔法数（command ^ 0xffffffff）
  final int magic;

  /// 数据载荷
  final Uint8List? payload;

  /// 构造函数
  AdbMessage({
    required this.command,
    required this.arg0,
    required this.arg1,
    required this.payloadLength,
    required this.checksum,
    required this.magic,
    this.payload,
  });

  /// 从字节缓冲区创建消息
  factory AdbMessage.fromBytes(Uint8List data) {
    if (data.length < AdbProtocol.adbHeaderLength) {
      throw ArgumentError('数据长度不足24字节，无法解析ADB消息头');
    }

    final buffer = ByteData.sublistView(data, 0, AdbProtocol.adbHeaderLength);
    int offset = 0;

    // 读取头部（小端字节序）
    final command = _readInt32(buffer, offset);
    offset += 4;
    final arg0 = _readInt32(buffer, offset);
    offset += 4;
    final arg1 = _readInt32(buffer, offset);
    offset += 4;
    final payloadLength = _readInt32(buffer, offset);
    offset += 4;
    final checksum = _readInt32(buffer, offset);
    offset += 4;
    final magic = _readInt32(buffer, offset);
    offset += 4;

    // 验证魔法数
    final expectedMagic = command ^ 0xffffffff;
    if (magic != expectedMagic) {
      throw ArgumentError('消息魔法数验证失败: 期望 $expectedMagic, 实际 $magic');
    }

    // 读取载荷数据
    Uint8List? payload;
    if (payloadLength > 0) {
      if (data.length < AdbProtocol.adbHeaderLength + payloadLength) {
        throw ArgumentError('数据长度不足，无法读取完整的载荷数据');
      }
      payload = Uint8List.sublistView(data, AdbProtocol.adbHeaderLength,
          AdbProtocol.adbHeaderLength + payloadLength);

      // 验证校验和
      final calculatedChecksum = AdbProtocol.calculateChecksum(payload);
      if (checksum != calculatedChecksum) {
        throw ArgumentError('消息校验和验证失败: 期望 $calculatedChecksum, 实际 $checksum');
      }
    }

    return AdbMessage(
      command: command,
      arg0: arg0,
      arg1: arg1,
      payloadLength: payloadLength,
      checksum: checksum,
      magic: magic,
      payload: payload,
    );
  }

  /// 将消息序列化为字节数组
  Uint8List toBytes() {
    final totalLength = AdbProtocol.adbHeaderLength + (payload?.length ?? 0);
    final buffer = ByteData(totalLength);
    int offset = 0;

    // 写入头部（小端字节序）
    offset = _writeInt32(buffer, offset, command);
    offset = _writeInt32(buffer, offset, arg0);
    offset = _writeInt32(buffer, offset, arg1);
    offset = _writeInt32(buffer, offset, payloadLength);
    offset = _writeInt32(buffer, offset, checksum);
    offset = _writeInt32(buffer, offset, magic);

    // 写入载荷数据
    if (payload != null && payload!.isNotEmpty) {
      final payloadBytes = buffer.buffer.asUint8List().sublist(offset);
      payloadBytes.setAll(0, payload!);
    }

    return buffer.buffer.asUint8List();
  }

  /// 获取载荷数据的字符串表示（用于调试）
  String getPayloadString() {
    if (payload == null || payload!.isEmpty) {
      return '';
    }

    switch (command) {
      case AdbProtocol.aAuth:
        if (arg0 == AdbProtocol.authTypeRsaPublic) {
          // RSA公钥载荷，尝试解码为字符串
          try {
            return utf8.decode(payload!);
          } catch (e) {
            return 'RSA公钥数据[${payload!.length}字节]';
          }
        } else {
          return '认证数据[${payload!.length}字节]';
        }

      case AdbProtocol.aOpen:
        // OPEN命令载荷通常是目标字符串
        try {
          // 去除末尾的null终止符
          final stringData = payload!.sublist(0, payloadLength - 1);
          return utf8.decode(stringData);
        } catch (e) {
          return 'OPEN数据[${payload!.length}字节]';
        }

      case AdbProtocol.aWrte:
        return '写入数据[${payload!.length}字节]';

      default:
        return '数据[${payload!.length}字节]';
    }
  }

  /// 转换为调试字符串
  @override
  String toString() {
    final commandStr = AdbProtocol.getCommandString(command);
    final payloadStr = getPayloadString();

    return '$commandStr[arg0=0x${arg0.toRadixString(16).toUpperCase()}, '
        'arg1=0x${arg1.toRadixString(16).toUpperCase()}] '
        'payloadLength=$payloadLength, checksum=$checksum'
        '${payloadStr.isNotEmpty ? ', payload: $payloadStr' : ''}';
  }

  /// 将整数写入缓冲区（小端字节序）
  static int _writeInt32(ByteData buffer, int offset, int value) {
    buffer.setUint32(offset, value, Endian.little);
    return offset + 4;
  }

  /// 从缓冲区读取整数（小端字节序）
  static int _readInt32(ByteData buffer, int offset) {
    return buffer.getUint32(offset, Endian.little);
  }
}
