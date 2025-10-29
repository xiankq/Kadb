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
      StreamController<AdbMessage>.broadcast();
  final Socket _socket;
  final _buffer = BytesBuilder();
  final _dataAvailable = StreamController<void>.broadcast();
  bool _isClosed = false;

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

      // 验证校验和（Kadb使用简单校验和，非CRC32）
      if (!fullMessage.verifyChecksum()) {
        throw AdbProtocolException('Checksum verification failed');
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
    if (_isClosed) return;

    // 简单的轮询方式，检查数据是否可用
    const maxWaitTime = Duration(seconds: 10);
    const checkInterval = Duration(milliseconds: 10);
    final startTime = DateTime.now();
    int lastBufferSize = _buffer.length;

    while (DateTime.now().difference(startTime) < maxWaitTime) {
      if (_buffer.length > lastBufferSize) {
        // 有新数据到达，继续处理
        return;
      }

      if (_buffer.length >= adbMessageHeaderSize) {
        // 数据已足够
        return;
      }

      await Future.delayed(checkInterval);
    }

    throw TimeoutException('等待数据超时 - 设备可能无响应 (等待了${maxWaitTime.inSeconds}秒)');
  }

  /// 处理接收到的数据
  void _onData(Uint8List data) {
    _buffer.add(data);
    // 通知等待者数据已到达
    if (!_dataAvailable.isClosed) {
      _dataAvailable.add(null);
    }
  }

  /// 处理错误
  void _onError(dynamic error) {
    _messageController.addError(error);
  }

  /// 处理连接关闭
  void _onDone() {
    _isClosed = true;
    _dataAvailable.close();
    _messageController.close();
  }

  /// 关闭读取器
  void close() {
    _isClosed = true;
    _dataAvailable.close();
    _messageController.close();
  }
}
