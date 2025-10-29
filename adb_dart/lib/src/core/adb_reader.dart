/// ADB消息读取器
/// 从传输通道读取ADB消息
library adb_reader;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'adb_message.dart' hide adbMessageHeaderSize;
import 'adb_protocol.dart';
import '../exception/adb_exceptions.dart';

/// ADB消息读取器
class AdbReader {
  final StreamController<AdbMessage> _messageController =
      StreamController<AdbMessage>();
  final Socket _socket;
  final _buffer = BytesBuilder();

  AdbReader(this._socket) {
    _socket.listen(_onData, onError: _onError, onDone: _onDone);
  }

  /// 读取一个消息
  Future<AdbMessage> readMessage() async {
    // 等待完整的头部
    while (_buffer.length < adbMessageHeaderSize) {
      await _waitForData();
    }

    // 解析头部
    final headerData = _buffer.toBytes();
    final header = headerData.sublist(0, adbMessageHeaderSize);
    final message = AdbMessage.fromHeader(header);

    // 验证消息
    if (!message.isValid()) {
      throw AdbProtocolException('Invalid message magic number');
    }

    // 如果有数据载荷，继续读取
    if (message.dataLength > 0) {
      while (_buffer.length < adbMessageHeaderSize + message.dataLength) {
        await _waitForData();
      }

      // 提取数据载荷
      final allData = _buffer.toBytes();
      final payload = allData.sublist(
          adbMessageHeaderSize, adbMessageHeaderSize + message.dataLength);

      // 重新创建包含载荷的消息
      final fullMessage = AdbMessage(
        command: message.command,
        arg0: message.arg0,
        arg1: message.arg1,
        dataLength: message.dataLength,
        dataCrc32: message.dataCrc32,
        magic: message.magic,
        payload: payload,
      );

      // 验证CRC32
      if (!fullMessage.verifyCrc32()) {
        throw AdbProtocolException('CRC32 verification failed');
      }

      // 从缓冲区中移除已处理的数据
      _buffer.clear();
      if (allData.length > adbMessageHeaderSize + message.dataLength) {
        _buffer.add(allData.sublist(adbMessageHeaderSize + message.dataLength));
      }

      return fullMessage;
    } else {
      // 没有数据载荷，直接移除头部
      _buffer.clear();
      if (headerData.length > adbMessageHeaderSize) {
        _buffer.add(headerData.sublist(adbMessageHeaderSize));
      }
      return message;
    }
  }

  /// 等待数据到达
  Future<void> _waitForData() async {
    final completer = Completer<void>();
    late StreamSubscription subscription;

    subscription = _messageController.stream.listen((_) {
      completer.complete();
      subscription.cancel();
    });

    await completer.future;
  }

  /// 处理接收到的数据
  void _onData(Uint8List data) {
    _buffer.add(data);
    _messageController.add(_buildDummyMessage());
  }

  /// 处理错误
  void _onError(dynamic error) {
    _messageController.addError(error);
  }

  /// 处理连接关闭
  void _onDone() {
    _messageController.close();
  }

  /// 构建虚拟消息（用于触发读取）
  AdbMessage _buildDummyMessage() {
    return AdbMessage(
      command: 0,
      arg0: 0,
      arg1: 0,
      dataLength: _buffer.length,
      dataCrc32: 0,
      magic: 0,
    );
  }

  /// 关闭读取器
  void close() {
    _messageController.close();
  }
}
