/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:async';
import 'dart:typed_data';
import '../transport/transport_channel.dart';
import 'adb_message.dart';
import 'adb_protocol.dart';

/// ADB消息读取器
class AdbReader {
  final TransportChannel _channel;
  final StreamController<AdbMessage> _messageController =
      StreamController<AdbMessage>();
  final BytesBuilder _buffer = BytesBuilder();

  AdbReader(this._channel) {
    _startReading();
  }

  /// 开始读取消息
  void _startReading() {
    if (_messageController.hasListener) return; // 避免重复监听
    
    _channel.dataStream.listen(
      (data) {
        try {
          // 将数据添加到缓冲区
          _buffer.add(data);
          
          // 尝试解析完整的消息
          _tryParseMessages();
        } catch (e) {
          if (!_messageController.isClosed) {
            _messageController.addError(e);
          }
        }
      },
      onError: (error) {
        if (!_messageController.isClosed) {
          _messageController.addError(error);
        }
      },
      onDone: () {
        if (!_messageController.isClosed) {
          _messageController.close();
        }
      },
      cancelOnError: false,
    );
  }

  /// 尝试从缓冲区解析消息
  void _tryParseMessages() {
    if (_messageController.isClosed) return;
    
    while (_buffer.length >= AdbProtocol.adbHeaderLength) {
      try {
        // 查看缓冲区中的数据
        final bufferBytes = _buffer.toBytes();
        
        // 解析消息头
        final headerData = ByteData.sublistView(bufferBytes, 0, AdbProtocol.adbHeaderLength);
        final payloadLength = headerData.getUint32(12, Endian.little);
        
        // 检查是否有足够的数据
        if (bufferBytes.length < AdbProtocol.adbHeaderLength + payloadLength) {
          break; // 等待更多数据
        }
        
        // 提取完整消息
        final messageBytes = bufferBytes.sublist(0, AdbProtocol.adbHeaderLength + payloadLength);
        final message = AdbMessage.fromBytes(messageBytes);
        
        if (message.isValid()) {
          if (!_messageController.isClosed) {
            _messageController.add(message);
            print('接收到消息: $message');
          }
        } else {
          print('警告：收到无效的ADB消息，magic值不匹配');
        }
        
        // 从缓冲区中移除已处理的数据
        _buffer.clear();
        if (bufferBytes.length > messageBytes.length) {
          _buffer.add(bufferBytes.sublist(messageBytes.length));
        }
        
      } catch (e) {
        print('解析ADB消息时出错：$e');
        // 如果解析失败，清空缓冲区避免死循环
        _buffer.clear();
        break;
      }
    }
  }

  /// 读取下一条消息
  Future<AdbMessage> readMessage() async {
    print('AdbReader.readMessage() called');
    if (_messageController.isClosed) {
      throw StateError('Message controller is closed');
    }
    print('等待消息流中的第一条消息...');
    final message = await _messageController.stream.first;
    print('成功读取消息: ${message.command.toRadixString(16)}');
    return message;
  }

  /// 关闭读取器
  void close() {
    print('关闭AdbReader...');
    if (!_messageController.isClosed) {
      _messageController.close();
    }
  }

  /// 获取消息流
  Stream<AdbMessage> get messageStream => _messageController.stream;
}
