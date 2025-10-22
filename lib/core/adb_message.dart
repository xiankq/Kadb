import 'dart:convert';

import 'adb_protocol.dart';
import '../utils/byte_utils.dart';

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
      case AdbProtocol.cmdAuth:
        if (arg0 == AdbProtocol.authTypeRsaPublic) {
          return utf8.decode(payload);
        }
        return 'auth[$payloadLength]';

      case AdbProtocol.cmdWrte:
        final shellPayload = _shellPayloadStr();
        if (shellPayload != null) return shellPayload;

        final syncPayload = _syncPayloadStr();
        if (syncPayload != null) return syncPayload;

        return 'payload[$payloadLength]';

      case AdbProtocol.cmdOpen:
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

    final length = ByteUtils.readIntLe(payload, 1);
    if (length != payloadLength - 5) return null;

    if (id == 3) {
      // ID_EXIT
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

    final syncIds = {
      'LIST',
      'RECV',
      'SEND',
      'STAT',
      'DATA',
      'DONE',
      'OKAY',
      'QUIT',
      'FAIL',
    };
    if (!syncIds.contains(id)) return null;

    final arg = ByteUtils.readIntLe(payload, 4);
    return '[sync] $id($arg)';
  }

  
  String _argStr(int arg) => arg.toRadixString(16).toUpperCase();

  String _commandStr() {
    switch (command) {
      case AdbProtocol.cmdAuth:
        return 'AUTH';
      case AdbProtocol.cmdCnxn:
        return 'CNXN';
      case AdbProtocol.cmdOpen:
        return 'OPEN';
      case AdbProtocol.cmdOkay:
        return 'OKAY';
      case AdbProtocol.cmdClse:
        return 'CLSE';
      case AdbProtocol.cmdWrte:
        return 'WRTE';
      default:
        return '????';
    }
  }
}
