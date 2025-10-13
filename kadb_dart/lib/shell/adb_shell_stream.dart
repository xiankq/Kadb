import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:kadb_dart/stream/adb_stream.dart';
import 'package:kadb_dart/shell/adb_shell_packet.dart';
import 'package:kadb_dart/shell/adb_shell_response.dart';
import 'package:kadb_dart/debug/logging.dart';

/// ADB Shell流
/// 用于执行Shell命令和处理Shell数据包
class AdbShellStream {
  final AdbStream _stream;
  StreamSink<List<int>>? _stdinSink;

  AdbShellStream(this._stream);

  /// 读取所有Shell输出
  Future<AdbShellResponse> readAll() async {
    final output = StringBuffer();
    final errorOutput = StringBuffer();

    while (true) {
      final packet = await read();
      
      if (packet is Exit) {
        final exitCode = packet.payload.isNotEmpty ? packet.payload[0] : 0;
        return AdbShellResponse(
          output.toString(), 
          errorOutput.toString(), 
          exitCode,
        );
      } else if (packet is StdOut) {
        output.write(utf8.decode(packet.payload));
      } else if (packet is StdError) {
        errorOutput.write(utf8.decode(packet.payload));
      } else {
        throw StateError('意外的Shell数据包: $packet');
      }
    }
  }

  /// 读取单个Shell数据包
  Future<AdbShellPacketBase> read() async {
    final source = _stream.source;
    
    final idByte = await source.readByte();
    final id = _checkId(idByte);
    
    final lengthBytes = await source.readBytes(4);
    final length = _checkLength(id, _bytesToIntLe(lengthBytes));
    
    final payload = await source.readBytes(length);
    
    switch (id) {
      case AdbShellPacket.idStdout:
        return StdOut(payload);
      case AdbShellPacket.idStderr:
        return StdError(payload);
      case AdbShellPacket.idExit:
        return Exit(payload);
      case AdbShellPacket.idCloseStdin:
        // 关闭标准输入流
        await _stdinSink?.close();
        return CloseStdin(payload);
      case AdbShellPacket.idWindowSizeChange:
        // 处理窗口大小变化
        final rows = payload[0] | (payload[1] << 8);
        final cols = payload[2] | (payload[3] << 8);
        final xpixel = payload[4] | (payload[5] << 8);
        final ypixel = payload[6] | (payload[7] << 8);
        return WindowSizeChange(payload, rows, cols, xpixel, ypixel);
      case AdbShellPacket.idInvalid:
        // 无效数据包，记录日志并忽略
        Logging.log('收到无效的Shell数据包ID: $id');
        return InvalidPacket(payload);
      default:
        throw ArgumentError('无效的Shell数据包ID: $id');
    }
  }

  /// 写入字符串到Shell
  Future<void> write(String string) async {
    await writeBytes(AdbShellPacket.idStdin, utf8.encode(string));
  }

  /// 写入字节数据到Shell
  Future<void> writeBytes(int id, List<int> payload) async {
    final sink = _stream.sink;
    
    await sink.writeByte(id);
    await sink.writeBytes(_intToBytesLe(payload.length));
    if (payload.isNotEmpty) {
      await sink.writeBytes(payload);
    }
    await sink.flush();
  }

  /// 关闭Shell流
  Future<void> close() async {
    await _stream.close();
  }

  /// 检查数据包ID是否有效
  int _checkId(int id) {
    if (id != AdbShellPacket.idStdout && 
        id != AdbShellPacket.idStderr && 
        id != AdbShellPacket.idExit) {
      throw ArgumentError('无效的Shell数据包ID: $id');
    }
    return id;
  }

  /// 检查数据包长度是否有效
  int _checkLength(int id, int length) {
    if (length < 0) {
      throw ArgumentError('Shell数据包长度必须 >= 0: $length');
    }
    if (id == AdbShellPacket.idExit && length != 1) {
      throw ArgumentError('Shell退出数据包负载长度必须为1: $length');
    }
    return length;
  }

  /// 将小端字节序转换为整数
  int _bytesToIntLe(Uint8List bytes) {
    int result = 0;
    for (int i = 0; i < bytes.length; i++) {
      result |= bytes[i] << (i * 8);
    }
    return result;
  }

  /// 将整数转换为小端字节序
  Uint8List _intToBytesLe(int value) {
    final bytes = Uint8List(4);
    for (int i = 0; i < 4; i++) {
      bytes[i] = (value >> (i * 8)) & 0xFF;
    }
    return bytes;
  }
}