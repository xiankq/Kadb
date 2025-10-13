import 'dart:async';
import 'dart:collection';

import 'package:kadb_dart/core/adb_message.dart';

/// ADB消息队列类
/// 管理ADB协议的消息队列和异步处理
class AdbMessageQueue {
  final Queue<AdbMessage> _messageQueue = Queue<AdbMessage>();
  final Map<int, Completer<AdbMessage>> _pendingResponses = {};
  final StreamController<AdbMessage> _messageController = StreamController<AdbMessage>.broadcast();
  
  bool _isClosed = false;
  
  /// 添加消息到队列
  void addMessage(AdbMessage message) {
    if (_isClosed) {
      throw StateError('消息队列已关闭');
    }
    
    _messageQueue.add(message);
    _messageController.add(message);
    
    // 检查是否有等待此消息的Completer
    final completer = _pendingResponses[message.arg1];
    if (completer != null && !completer.isCompleted) {
      completer.complete(message);
      _pendingResponses.remove(message.arg1);
    }
  }
  
  /// 获取消息流
  Stream<AdbMessage> get messageStream => _messageController.stream;
  
  /// 等待特定响应
  /// [localId] 本地ID
  /// [timeout] 超时时间
  Future<AdbMessage> waitForResponse(int localId, {Duration? timeout}) async {
    if (_isClosed) {
      throw StateError('消息队列已关闭');
    }
    
    final completer = Completer<AdbMessage>();
    _pendingResponses[localId] = completer;
    
    final timeoutDuration = timeout ?? Duration(seconds: 30);
    final timeoutFuture = Future.delayed(timeoutDuration, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('等待响应超时'));
        _pendingResponses.remove(localId);
      }
    });
    
    try {
      final response = await completer.future;
      timeoutFuture.ignore();
      return response;
    } catch (e) {
      timeoutFuture.ignore();
      _pendingResponses.remove(localId);
      rethrow;
    }
  }
  
  /// 获取下一个消息
  Future<AdbMessage> nextMessage() async {
    if (_isClosed) {
      throw StateError('消息队列已关闭');
    }
    
    if (_messageQueue.isNotEmpty) {
      return _messageQueue.removeFirst();
    }
    
    final completer = Completer<AdbMessage>();
    StreamSubscription<AdbMessage>? subscription;
    
    subscription = _messageController.stream.listen((message) {
      if (!completer.isCompleted) {
        completer.complete(message);
        subscription?.cancel();
      }
    }, onError: (error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
        subscription?.cancel();
      }
    });
    
    return completer.future;
  }
  
  /// 过滤消息流
  Stream<AdbMessage> filterMessages(bool Function(AdbMessage) predicate) {
    return _messageController.stream.where(predicate);
  }
  
  /// 检查是否有特定消息
  bool hasMessageWithLocalId(int localId) {
    return _messageQueue.any((message) => message.arg1 == localId);
  }
  
  /// 获取队列大小
  int get queueSize => _messageQueue.length;
  
  /// 获取等待响应数量
  int get pendingResponseCount => _pendingResponses.length;
  
  /// 清空队列
  void clear() {
    _messageQueue.clear();
    
    // 完成所有等待的Completer
    for (final completer in _pendingResponses.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('消息队列已清空'));
      }
    }
    _pendingResponses.clear();
  }
  
  /// 关闭消息队列
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    
    _isClosed = true;
    
    // 完成所有等待的Completer
    for (final completer in _pendingResponses.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('消息队列已关闭'));
      }
    }
    _pendingResponses.clear();
    
    await _messageController.close();
    _messageQueue.clear();
  }
  
  /// 处理消息错误
  void handleError(Object error, [StackTrace? stackTrace]) {
    if (!_isClosed) {
      _messageController.addError(error, stackTrace);
    }
  }
}

/// 消息队列管理器类
/// 管理多个消息队列
class MessageQueueManager {
  final Map<String, AdbMessageQueue> _queues = {};
  
  /// 创建消息队列
  AdbMessageQueue createQueue(String queueId) {
    if (_queues.containsKey(queueId)) {
      throw StateError('消息队列 $queueId 已存在');
    }
    
    final queue = AdbMessageQueue();
    _queues[queueId] = queue;
    return queue;
  }
  
  /// 获取消息队列
  AdbMessageQueue? getQueue(String queueId) {
    return _queues[queueId];
  }
  
  /// 删除消息队列
  Future<void> removeQueue(String queueId) async {
    final queue = _queues[queueId];
    if (queue != null) {
      await queue.close();
      _queues.remove(queueId);
    }
  }
  
  /// 关闭所有消息队列
  Future<void> closeAll() async {
    for (final queue in _queues.values) {
      await queue.close();
    }
    _queues.clear();
  }
  
  /// 获取活跃队列数量
  int get activeQueueCount => _queues.length;
}