/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:async';
import 'dart:collection';
import '../core/adb_message.dart';
import '../core/adb_protocol.dart';
import '../core/adb_reader.dart';
import '../stream/adb_stream.dart';
import 'message_queue.dart';

/// ADB消息队列实现
class AdbMessageQueue extends MessageQueue<AdbMessage> {
  final AdbReader _adbReader;
  final Map<int, Completer<AdbMessage>> _pendingMessages = {};
  final Map<int, AdbStream> _streamHandlers = {};
  final StreamController<AdbMessage> _messageController = StreamController<AdbMessage>();
  
  bool _isListening = false;
  StreamSubscription<AdbMessage>? _messageSubscription;

  AdbMessageQueue(this._adbReader) {
    startListening();
  }

  @override
  Future<AdbMessage> readMessage() async {
    return _adbReader.readMessage();
  }

  @override
  int getLocalId(AdbMessage message) => message.arg1;

  @override
  int getCommand(AdbMessage message) => message.command;

  @override
  void close() {
    print('关闭消息队列...');
    stopListening();
    
    if (!_messageController.isClosed) {
      print('关闭消息控制器...');
      _messageController.close();
    }
    
    print('关闭ADB读取器...');
    _adbReader.close();
    
    // 清理所有pending的消息
    for (final completer in _pendingMessages.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Message queue closed'));
      }
    }
    _pendingMessages.clear();
    
    // 清理所有流处理器
    _streamHandlers.clear();
    print('消息队列关闭完成');
  }

  @override
  bool isCloseCommand(AdbMessage message) =>
      message.command == AdbProtocol.cmdClse;

  @override
  void startListening() {
    if (_isListening) return;

    _isListening = true;
    _messageSubscription = _adbReader.messageStream.listen(
      (message) {
        _handleMessage(message);
      },
      onError: (error) {
        _messageController.addError(error);
        // 通知所有pending的消息
        for (final completer in _pendingMessages.values) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        }
        _pendingMessages.clear();
      },
      onDone: () {
        _isListening = false;
        _messageController.close();
      },
    );
  }

  @override
  void stopListening() {
    if (!_isListening) return;

    _isListening = false;
    _messageSubscription?.cancel();
    _messageSubscription = null;
  }

  /// 处理接收到的消息
  void _handleMessage(AdbMessage message) {
    final localId = getLocalId(message);
    final command = getCommand(message);

    print('处理消息 - 命令: 0x${command.toRadixString(16)}, localId: $localId');

    // 检查是否是pending消息的响应
    final completer = _pendingMessages.remove(localId);
    if (completer != null) {
      completer.complete(message);
      return;
    }

    // 检查是否有对应的流处理器
    final streamHandler = _streamHandlers[localId];
    if (streamHandler != null) {
      streamHandler.handleMessage(message);
      return;
    }

    // 检查是否是关闭命令
    if (isCloseCommand(message)) {
      print('收到关闭命令，localId: $localId');
      // 清理相关的流处理器
      _streamHandlers.remove(localId);
      return;
    }

    // 广播到主消息流
    if (!_messageController.isClosed) {
      _messageController.add(message);
    }
  }

  /// 等待特定消息
  Future<AdbMessage> waitForMessage(int localId, int expectedCommand) async {
    print(
      '等待消息 - localId: $localId, expectedCommand: 0x${expectedCommand.toRadixString(16)}',
    );

    final completer = Completer<AdbMessage>();
    _pendingMessages[localId] = completer;

    try {
      final message = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('等待消息超时 - localId: $localId');
          throw TimeoutException('等待消息超时');
        },
      );

      print(
        '收到消息 - 命令: 0x${message.command.toRadixString(16)}, localId: ${message.arg1}',
      );

      if (message.command != expectedCommand) {
        throw Exception('收到意外的消息类型：${message.command}，期望：$expectedCommand');
      }

      return message;
    } finally {
      _pendingMessages.remove(localId);
    }
  }

  /// 注册流处理器
  void registerStreamHandler(int localId, AdbStream stream) {
    if (_streamHandlers.containsKey(localId)) {
      print('警告：流处理器已存在，localId: $localId');
      return;
    }
    _streamHandlers[localId] = stream;
  }
  
  /// 注销流处理器
  void unregisterStreamHandler(int localId) {
    _streamHandlers.remove(localId);
  }

  /// 获取消息流
  Stream<AdbMessage> get messageStream => _messageController.stream;

  /// 检查是否正在监听
  bool get isListening => _isListening;
}
