/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:typed_data';
import 'adb_protocol.dart';

/// ADB消息类，表示一个ADB协议消息
class AdbMessage {
  final int command;
  final int arg0;
  final int arg1;
  final int payloadLength;
  final int checksum;
  final int magic;
  final Uint8List payload;

  AdbMessage({
    required this.command,
    required this.arg0,
    required this.arg1,
    required this.payloadLength,
    required this.checksum,
    required this.magic,
    required this.payload,
  });

  /// 从字节数据解析ADB消息
  factory AdbMessage.fromBytes(Uint8List data) {
    if (data.length < AdbProtocol.adbHeaderLength) {
      throw ArgumentError('数据长度不足，无法解析ADB消息头');
    }

    final byteData = ByteData.sublistView(data, 0, AdbProtocol.adbHeaderLength);

    final command = byteData.getUint32(0, Endian.little);
    final arg0 = byteData.getUint32(4, Endian.little);
    final arg1 = byteData.getUint32(8, Endian.little);
    final payloadLength = byteData.getUint32(12, Endian.little);
    final checksum = byteData.getUint32(16, Endian.little);
    final magic = byteData.getUint32(20, Endian.little);

    Uint8List payload;
    if (payloadLength > 0) {
      if (data.length < AdbProtocol.adbHeaderLength + payloadLength) {
        throw ArgumentError('数据长度不足，无法解析ADB消息载荷');
      }
      payload = Uint8List.sublistView(
        data,
        AdbProtocol.adbHeaderLength,
        AdbProtocol.adbHeaderLength + payloadLength,
      );
    } else {
      payload = Uint8List(0);
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

  /// 将消息转换为字节数据
  List<int> toBytes() {
    return AdbProtocol.generateMessage(command, arg0, arg1, payload.toList());
  }

  @override
  String toString() {
    return '${_commandToString(command)}[${arg0.toRadixString(16)}, ${arg1.toRadixString(16)}] ${payloadStr()}';
  }

  /// 将命令转换为字符串表示
  static String _commandToString(int command) {
    switch (command) {
      case AdbProtocol.cmdAuth:
        return "AUTH";
      case AdbProtocol.cmdCnxc:
        return "CNXN";
      case AdbProtocol.cmdOpen:
        return "OPEN";
      case AdbProtocol.cmdOkay:
        return "OKAY";
      case AdbProtocol.cmdClse:
        return "CLSE";
      case AdbProtocol.cmdWrte:
        return "WRTE";
      default:
        return "????";
    }
  }

  String payloadStr() {
    if (payloadLength == 0) return '';

    switch (command) {
      case AdbProtocol.cmdAuth:
        return arg0 == AdbProtocol.authTypeRsaPublic
            ? String.fromCharCodes(payload)
            : 'auth[$payloadLength]';
      case AdbProtocol.cmdWrte:
        return writePayloadStr();
      case AdbProtocol.cmdOpen:
        return String.fromCharCodes(payload.take(payloadLength - 1));
      default:
        return 'payload[$payloadLength]';
    }
  }

  String writePayloadStr() {
    return shellPayloadStr() ?? syncPayloadStr() ?? 'payload[$payloadLength]';
  }

  String? shellPayloadStr() {
    if (payloadLength < 5) return null;
    
    final buffer = ByteData.sublistView(payload, 0, 5);
    final id = buffer.getUint8(0);
    final length = buffer.getUint32(1, Endian.little);
    
    if (id < 0 || id > 3) return null;
    if (length != payloadLength - 5) return null;
    
    if (id == 3) { // AdbShellPacketV2.ID_EXIT
      if (payloadLength == 6) {
        final exitCode = payload[5];
        return '[shell] exit($exitCode)';
      }
    }
    
    final payloadStr = String.fromCharCodes(payload, 5, payloadLength);
    return '[shell] $payloadStr';
  }

  String? syncPayloadStr() {
    if (payloadLength < 8) return null;
    
    final buffer = ByteData.sublistView(payload, 0, 8);
    final id = String.fromCharCodes(payload, 0, 4);
    final arg = buffer.getUint32(4, Endian.little);
    
    const syncIds = {'STAT', 'LIST', 'SEND', 'RECV', 'DENT', 'DATA', 'DONE', 'OKAY', 'FAIL'};
    if (!syncIds.contains(id)) return null;
    
    return '[sync] $id($arg)';
  }

  /// 验证消息的magic值
  bool isValid() {
    return magic == (command ^ 0xFFFFFFFF);
  }
}
