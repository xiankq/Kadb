import 'dart:async';

import 'adb_message.dart';
import 'adb_protocol.dart';
import '../utils/logging.dart';
import '../utils/byte_utils.dart';

/// ADB消息读取器，负责从数据源读取ADB协议消息
class AdbReader {
  final Future<List<int>> Function(int) _readBytes;
  final bool _debug;

  AdbReader(this._readBytes, {bool debug = false}) : _debug = debug;

  /// 读取一个完整的ADB消息，返回解析后的AdbMessage对象
  Future<AdbMessage> readMessage() async {
    // 读取消息头（24字节）- 阻塞等待完整数据
    final headerBytes = await _readBytesExact(AdbProtocol.headerLength);

    // 解析消息头
    final command = ByteUtils.readIntLe(headerBytes, 0);
    final arg0 = ByteUtils.readIntLe(headerBytes, 4);
    final arg1 = ByteUtils.readIntLe(headerBytes, 8);
    final payloadLength = ByteUtils.readIntLe(headerBytes, 12);
    final checksum = ByteUtils.readIntLe(headerBytes, 16);
    final magic = ByteUtils.readIntLe(headerBytes, 20);

    // 验证魔数
    if ((command ^ magic) != 0xFFFFFFFF) {
      throw Exception('ADB消息魔数验证失败: command=$command, magic=$magic');
    }

    // 读取负载数据
    final payload = payloadLength > 0
        ? await _readBytesExact(payloadLength)
        : <int>[];

    final message = AdbMessage(
      command: command,
      arg0: arg0,
      arg1: arg1,
      payloadLength: payloadLength,
      checksum: checksum,
      magic: magic,
      payload: payload,
    );

    // 只在详细模式下显示消息读取，避免过度打印
    if (_debug) {
      Logging.verbose('(${DateTime.now()}) < $message');
    }

    return message;
  }

  /// 读取指定长度的字节，确保读取完整数据
  Future<List<int>> _readBytesExact(int length) async {
    final buffer = <int>[];
    while (buffer.length < length) {
      final chunk = await _readBytes(length - buffer.length);
      if (chunk.isEmpty) {
        throw Exception('连接已关闭，期望读取$length字节，但只读取了${buffer.length}字节');
      }
      buffer.addAll(chunk);
    }
    return buffer;
  }

  /// 关闭读取器
  void close() {
    // Dart中不需要显式关闭，由GC处理
  }
}
