/// ADB消息队列
/// 管理异步消息的分发和处理
library adb_message_queue;

import 'dart:async';
import 'dart:collection';
import '../core/adb_message.dart';
import '../core/adb_reader.dart';
import '../core/adb_protocol.dart';
import '../exception/adb_exceptions.dart';

/// 消息监听器
typedef MessageListener = void Function(AdbMessage message);

/// ADB消息队列管理器
class AdbMessageQueue {
  final AdbReader _reader;
  final Map<int, Completer<AdbMessage>> _pendingMessages = {};
  final Map<int, MessageListener> _listeners = {};
  final Queue<AdbMessage> _messageQueue = Queue<AdbMessage>();

  bool _isRunning = false;
  bool _isClosed = false;
  StreamSubscription<void>? _subscription;

  AdbMessageQueue(this._reader);

  /// 启动消息队列
  void start() {
    if (_isRunning || _isClosed) return;

    _isRunning = true;
    _startMessageLoop();
  }

  /// 停止消息队列
  void stop() {
    _isRunning = false;
    _subscription?.cancel();
    _subscription = null;
  }

  /// 关闭消息队列
  void close() {
    _isClosed = true;
    stop();

    // 拒绝所有待处理的消息
    for (final completer in _pendingMessages.values) {
      if (!completer.isCompleted) {
        completer.completeError(AdbStreamException('Message queue closed'));
      }
    }
    _pendingMessages.clear();
    _listeners.clear();
    _messageQueue.clear();
  }

  /// 开始监听指定本地ID的消息
  void startListening(int localId) {
    // 为数据流消息添加监听器
    _listeners[localId] = (message) {
      // 数据消息直接处理，不需要等待
      if (message.command == AdbProtocol.cmdWrte && message.payload != null) {
        // 这里应该调用流的数据处理器
        // 暂时存储在队列中供流读取
        _messageQueue.add(message);
      }
    };
  }

  /// 停止监听指定本地ID的消息
  void stopListening(int localId) {
    _pendingMessages.remove(localId);
    _listeners.remove(localId);
  }

  /// 等待指定命令的消息
  Future<AdbMessage> take(int localId, int expectedCommand) async {
    if (_isClosed) {
      throw AdbStreamException('Message queue is closed');
    }

    // 首先检查队列中是否已有匹配的消息
    final matchingMessage = _findMatchingMessage(localId, expectedCommand);
    if (matchingMessage != null) {
      return matchingMessage;
    }

    // 等待消息到达
    final completer = Completer<AdbMessage>();
    _pendingMessages[localId] = completer;

    try {
      return await completer.future.timeout(
        const Duration(seconds: 10), // 增加超时时间用于诊断
        onTimeout: () {
          _pendingMessages.remove(localId);
          throw TimeoutException(
              '等待命令超时: ${AdbProtocol.getCommandName(expectedCommand)} '
              '本地ID: $localId - 设备可能无响应或协议不匹配');
        },
      );
    } catch (e) {
      _pendingMessages.remove(localId);
      rethrow;
    }
  }

  /// 查找匹配的消息
  AdbMessage? _findMatchingMessage(int localId, int expectedCommand) {
    for (final message in _messageQueue) {
      if (_isMatchingMessage(message, localId, expectedCommand)) {
        _messageQueue.remove(message);
        return message;
      }
    }
    return null;
  }

  /// 检查消息是否匹配
  bool _isMatchingMessage(
      AdbMessage message, int localId, int expectedCommand) {
    // 检查命令类型
    if (message.command != expectedCommand) {
      return false;
    }

    // 检查消息类型和对应的ID
    switch (expectedCommand) {
      case AdbProtocol.cmdOkay:
      case AdbProtocol.cmdClse:
      case AdbProtocol.cmdWrte:
        // 这些消息使用arg1作为远程ID（对应我们的本地ID）
        return message.arg1 == localId;

      default:
        // 其他消息使用arg0作为本地ID
        return message.arg0 == localId;
    }
  }

  /// 启动消息循环
  void _startMessageLoop() async {
    while (_isRunning && !_isClosed) {
      try {
        final message = await _reader.readMessage();
        _processMessage(message);
      } catch (e) {
        if (!_isClosed) {
          print('消息循环错误: $e');
          // 可以在这里添加重试逻辑或错误处理
        }
        break;
      }
    }
  }

  /// 处理接收到的消息
  void _processMessage(AdbMessage message) {
    // 首先检查是否有等待此消息的completer
    final localId = _getLocalIdFromMessage(message);
    final completer = _pendingMessages.remove(localId);

    if (completer != null && !completer.isCompleted) {
      completer.complete(message);
      return;
    }

    // 检查是否有监听器
    final listener = _listeners[localId];
    if (listener != null) {
      listener(message);
      return;
    }

    // 如果没有等待者，将消息加入队列
    _messageQueue.add(message);

    // 限制队列大小，防止内存泄漏
    if (_messageQueue.length > 100) {
      _messageQueue.removeFirst();
    }
  }

  /// 从消息中提取本地ID
  int _getLocalIdFromMessage(AdbMessage message) {
    switch (message.command) {
      case AdbProtocol.cmdOkay:
      case AdbProtocol.cmdClse:
      case AdbProtocol.cmdWrte:
        // 这些消息使用arg1作为远程ID
        return message.arg1;

      default:
        // 其他消息使用arg0作为本地ID
        return message.arg0;
    }
  }

  /// 确保队列为空（用于测试）
  void ensureEmpty() {
    if (_messageQueue.isNotEmpty) {
      throw StateError(
          'Message queue is not empty, contains ${_messageQueue.length} messages');
    }
  }
}
