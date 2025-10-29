/// ADB消息队列
///
/// 负责管理异步ADB消息的分发和路由
/// 基于local-id进行消息路由，支持超时和取消
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'adb_protocol.dart';
import 'adb_message.dart';

/// 消息队列异常
class MessageQueueException implements Exception {
  final String message;
  final int? localId;
  final int? command;

  MessageQueueException(this.message, {this.localId, this.command});

  @override
  String toString() {
    final buffer = StringBuffer('消息队列错误: $message');
    if (localId != null) {
      buffer.write(' (localId: 0x${localId!.toRadixString(16).toUpperCase()})');
    }
    if (command != null) {
      buffer.write(' (command: ${AdbProtocol.getCommandString(command!)})');
    }
    return buffer.toString();
  }
}

/// ADB消息队列
///
/// 提供基于local-id的消息路由和异步消息分发功能
class AdbMessageQueue {
  /// 本地流ID -> (命令 -> 消息队列)
  final Map<int, Map<int, Queue<AdbMessage>>> _messageQueues = {};

  /// 活跃的本地流ID集合
  final Set<int> _activeLocalIds = {};

  /// 消息监听器
  final StreamController<AdbMessage> _messageController =
      StreamController<AdbMessage>.broadcast();

  /// 关闭标志
  bool _isClosed = false;

  /// 获取消息流
  Stream<AdbMessage> get messageStream => _messageController.stream;

  /// 开始监听指定本地流ID
  void startListening(int localId) {
    if (_isClosed) {
      throw MessageQueueException('消息队列已关闭', localId: localId);
    }

    if (_activeLocalIds.contains(localId)) {
      throw MessageQueueException('已在监听此本地流ID', localId: localId);
    }

    _activeLocalIds.add(localId);
    _messageQueues[localId] = {};
  }

  /// 停止监听指定本地流ID
  void stopListening(int localId) {
    _activeLocalIds.remove(localId);
    _messageQueues.remove(localId);
  }

  /// 投递消息到队列
  void deliverMessage(AdbMessage message) {
    if (_isClosed) return;

    final localId = message.arg1; // 对于接收的消息，arg1是本地ID

    // 检查是否是关闭命令
    if (message.command == AdbProtocol.aClse) {
      _handleCloseMessage(localId);
      return;
    }

    // 检查是否在监听此本地流ID
    if (!_activeLocalIds.contains(localId)) {
      return; // 忽略未监听的流消息
    }

    // 获取或创建命令队列
    final commandQueues = _messageQueues[localId]!;
    final command = message.command;
    commandQueues.putIfAbsent(command, () => Queue<AdbMessage>());

    // 添加消息到队列
    commandQueues[command]!.add(message);

    // 通知有新消息到达
    _messageController.add(message);
  }

  /// 接收指定命令的消息
  Future<AdbMessage> take(int localId, int command, {Duration? timeout}) async {
    if (!_activeLocalIds.contains(localId)) {
      throw MessageQueueException('未监听此本地流ID',
          localId: localId, command: command);
    }

    final commandQueues = _messageQueues[localId]!;

    // 立即检查是否有可用消息
    if (commandQueues.containsKey(command) &&
        commandQueues[command]!.isNotEmpty) {
      return commandQueues[command]!.removeFirst();
    }

    // 等待消息到达
    final completer = Completer<AdbMessage>();
    StreamSubscription<AdbMessage>? subscription;
    Timer? timeoutTimer;

    // 设置超时
    if (timeout != null) {
      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.completeError(MessageQueueException('接收消息超时',
              localId: localId, command: command));
        }
      });
    }

    try {
      // 监听消息流
      subscription = _messageController.stream.listen(
        (message) {
          if (message.arg1 == localId && message.command == command) {
            if (!completer.isCompleted) {
              timeoutTimer?.cancel();
              completer.complete(message);
            }
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            timeoutTimer?.cancel();
            completer.completeError(error);
          }
        },
      );

      // 再次检查是否有可用消息（避免竞态条件）
      if (commandQueues.containsKey(command) &&
          commandQueues[command]!.isNotEmpty) {
        final message = commandQueues[command]!.removeFirst();
        if (!completer.isCompleted) {
          timeoutTimer?.cancel();
          completer.complete(message);
        }
      }

      return await completer.future;
    } finally {
      timeoutTimer?.cancel();
      await subscription?.cancel();
    }
  }

  /// 处理关闭消息
  void _handleCloseMessage(int localId) {
    // 停止监听此流
    stopListening(localId);

    // 通知所有等待此流的接收操作
    _messageController.addError(
      MessageQueueException('流已关闭', localId: localId),
    );
  }

  /// 获取指定本地流ID的待处理消息数量
  int getPendingMessageCount(int localId) {
    if (!_messageQueues.containsKey(localId)) {
      return 0;
    }

    int count = 0;
    for (final queue in _messageQueues[localId]!.values) {
      count += queue.length;
    }
    return count;
  }

  /// 获取所有待处理消息的总数量
  int get totalPendingMessageCount {
    int count = 0;
    for (final localId in _messageQueues.keys) {
      count += getPendingMessageCount(localId);
    }
    return count;
  }

  /// 关闭消息队列
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    // 清空所有队列
    _messageQueues.clear();
    _activeLocalIds.clear();

    // 关闭控制器
    await _messageController.close();
  }

  /// 检查是否已关闭
  bool get isClosed => _isClosed;

  /// 检查是否正在监听指定本地流ID
  bool isListening(int localId) {
    return _activeLocalIds.contains(localId);
  }

  /// 获取正在监听的本地流ID列表
  List<int> get activeLocalIds => List.from(_activeLocalIds);
}

/// ADB消息队列实现（完整复刻Kadb）
///
/// 提供基于AdbReader的消息队列功能，支持并发消息处理
class AdbMessageQueueImpl extends AdbMessageQueue {
  final AdbReader _adbReader;

  AdbMessageQueueImpl(this._adbReader);

  @override
  Future<AdbMessage> readMessage() async {
    return await _adbReader.readMessage();
  }

  @override
  int getLocalId(AdbMessage message) {
    return message.arg1;
  }

  @override
  int getCommand(AdbMessage message) {
    return message.command;
  }

  @override
  Future<void> close() async {
    await _adbReader.close();
  }

  @override
  bool isCloseCommand(AdbMessage message) {
    return message.command == AdbProtocol.aClse;
  }
}
