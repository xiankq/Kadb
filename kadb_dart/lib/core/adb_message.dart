import 'dart:convert';

import 'package:kadb_dart/core/adb_protocol.dart';

/// ADB消息类
/// 表示ADB协议中的一个完整消息
class AdbMessage {
  final int command;
  final int arg0;
  final int arg1;
  final int payloadLength;
  final int checksum;
  final int magic;
  final List<int> payload;

  AdbMessage({
    required this.command,
    required this.arg0,
    required this.arg1,
    required this.payloadLength,
    required this.checksum,
    required this.magic,
    required this.payload,
  });

  @override
  String toString() {
    return '${_commandStr()}[${_argStr(arg0)}, ${_argStr(arg1)}] ${_payloadStr()}';
  }

  String _payloadStr() {
    if (payloadLength == 0) return '';
    
    switch (command) {
      case AdbProtocol.CMD_AUTH:
        if (arg0 == AdbProtocol.AUTH_TYPE_RSA_PUBLIC) {
          return utf8.decode(payload);
        }
        return 'auth[$payloadLength]';
      
      case AdbProtocol.CMD_WRTE:
        final shellPayload = _shellPayloadStr();
        if (shellPayload != null) return shellPayload;
        
        final syncPayload = _syncPayloadStr();
        if (syncPayload != null) return syncPayload;
        
        return 'payload[$payloadLength]';
      
      case AdbProtocol.CMD_OPEN:
        try {
          return utf8.decode(payload.sublist(0, payloadLength - 1));
        } catch (e) {
          return 'open[${payloadLength - 1}]';
        }
      
      default:
        return 'payload[$payloadLength]';
    }
  }

  String? _shellPayloadStr() {
    if (payloadLength < 5) return null;

    final id = payload[0];
    if (id < 0 || id > 3) return null;

    final length = _readIntLe(payload, 1);
    if (length != payloadLength - 5) return null;

    if (id == 3) { // ID_EXIT
      return '[shell] exit(${payload[5]})';
    }

    // 安全地解码shell payload，避免UTF-8解码错误
    try {
      final payloadStr = utf8.decode(payload.sublist(5, payloadLength));
      return '[shell] $payloadStr';
    } catch (e) {
      // 如果UTF-8解码失败，返回简单的长度信息
      return '[shell] binary[${payloadLength - 5}]';
    }
  }

  String? _syncPayloadStr() {
    if (payloadLength < 8) return null;

    // 安全地解码sync协议ID，避免UTF-8解码错误
    String id;
    try {
      id = utf8.decode(payload.sublist(0, 4));
    } catch (e) {
      // 如果UTF-8解码失败，这不是一个有效的sync协议消息
      return null;
    }

    final syncIds = {'LIST', 'RECV', 'SEND', 'STAT', 'DATA', 'DONE', 'OKAY', 'QUIT', 'FAIL'};
    if (!syncIds.contains(id)) return null;

    final arg = _readIntLe(payload, 4);
    return '[sync] $id($arg)';
  }

  int _readIntLe(List<int> data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  String _argStr(int arg) => arg.toRadixString(16).toUpperCase();

  String _commandStr() {
    switch (command) {
      case AdbProtocol.CMD_AUTH: return 'AUTH';
      case AdbProtocol.CMD_CNXN: return 'CNXN';
      case AdbProtocol.CMD_OPEN: return 'OPEN';
      case AdbProtocol.CMD_OKAY: return 'OKAY';
      case AdbProtocol.CMD_CLSE: return 'CLSE';
      case AdbProtocol.CMD_WRTE: return 'WRTE';
      default: return '????';
    }
  }
}