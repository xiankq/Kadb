/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:async';
import 'dart:typed_data';
import '../core/adb_connection.dart';
import '../core/adb_message.dart';
import '../core/adb_protocol.dart';

/// ADB流类，表示一个与服务器的双向通信通道
class AdbStream {
  final AdbConnection _connection;
  final int localId;
  final int remoteId;
  final int maxPayloadSize;
  
  final StreamController<Uint8List> _dataController = StreamController<Uint8List>();
  final StreamController<void> _closeController = StreamController<void>();
  
  bool _isClosed = false;
  Function(AdbMessage)? _messageHandler;
  
  AdbStream({
    required AdbConnection connection,
    required this.localId,
    required this.remoteId,
    required this.maxPayloadSize,
  }) : _connection = connection {
    _registerWithConnection();
  }

  /// 注册到连接
  void _registerWithConnection() {
    _connection.registerStreamController(localId, this);
  }

  /// 开始监听消息
  void _startListening() {
    print('开始监听流消息，localId: $localId');
  }
  
  /// 处理接收到的消息（由消息队列直接调用）
  void handleMessage(AdbMessage message) {
    _handleMessage(message);
  }

  /// 处理接收到的消息
  void _handleMessage(AdbMessage message) {
    switch (message.command) {
      case AdbProtocol.cmdWrte:
        // 发送OKAY确认
        _connection.sendOkay(localId, remoteId);

        // 转发数据到数据流
        if (message.payloadLength > 0) {
          _dataController.add(message.payload);
        }
        break;

      case AdbProtocol.cmdClse:
        // 对方关闭了连接
        _isClosed = true;
        _closeController.add(null);
        _closeController.close();
        _dataController.close();
        break;
    }
  }

  /// 写入数据到流
  Future<void> write(List<int> data) async {
    if (_isClosed) {
      throw StateError('流已关闭');
    }

    // 如果数据太大，需要分块发送
    int offset = 0;
    while (offset < data.length) {
      final chunkSize = (data.length - offset) > maxPayloadSize
          ? maxPayloadSize
          : (data.length - offset);

      final chunk = data.sublist(offset, offset + chunkSize);
      await _connection.sendWrite(localId, remoteId, chunk);

      offset += chunkSize;
    }
  }

  /// 读取数据（完整实现）
  Future<Uint8List> read() async {
    if (_isClosed) {
      throw StateError('流已关闭');
    }

    try {
      // 等待数据到达
      final data = await _dataController.stream.first;
      return data;
    } catch (e) {
      if (_isClosed) {
        return Uint8List(0);
      }
      rethrow;
    }
  }

  /// 读取所有数据直到流关闭
  Future<Uint8List> readAll() async {
    final buffer = <int>[];

    await for (final data in _dataController.stream) {
      buffer.addAll(data);
    }

    return Uint8List.fromList(buffer);
  }

  /// 读取指定长度的数据
  Future<Uint8List> readBytes(int length) async {
    final buffer = <int>[];

    while (buffer.length < length && !_isClosed) {
      try {
        final data = await _dataController.stream.first.timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('读取数据超时'),
        );
        buffer.addAll(data);
      } catch (e) {
        if (_isClosed) break;
        rethrow;
      }
    }

    return Uint8List.fromList(buffer.take(length).toList());
  }

  /// 关闭流
  Future<void> close() async {
    if (_isClosed) return;

    _isClosed = true;

    // 从连接中注销
    _connection.unregisterStreamController(localId);

    await _connection.sendClose(localId, remoteId);

    _dataController.close();
    _closeController.add(null);
    _closeController.close();
  }

  /// 检查流是否已关闭
  bool get isClosed => _isClosed;

  /// 数据流
  Stream<Uint8List> get dataStream => _dataController.stream;

  /// 关闭事件流
  Stream<void> get closeStream => _closeController.stream;
}
