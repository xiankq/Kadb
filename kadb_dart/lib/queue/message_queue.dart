import 'dart:async';
import 'dart:collection';
import '../exception/adb_stream_closed.dart';

/// 消息队列抽象基类
/// 用于管理ADB消息的队列操作
abstract class MessageQueue<V> {
  final Map<int, Map<int, Queue<V>>> _queues = {};
  final Set<int> _openStreams = {};
  final StreamController<V> _messageController = StreamController.broadcast();
  bool _queueLocked = false;
  bool _readLocked = false;
  final List<Completer<void>> _queueWaiters = [];
  final List<Completer<void>> _readWaiters = [];

  /// 从队列中获取消息
  Future<V> take(int localId, int command) async {
    while (true) {
      await _acquireQueueLock();
      try {
        final message = _poll(localId, command);
        if (message != null) {
          return message;
        }
        
        // 尝试读取新消息
        if (await _tryAcquireReadLock()) {
          try {
            _releaseQueueLock();
            await _read();
            await _acquireQueueLock();
            // 通知等待的消费者
            _messageController.add(null as V);
          } finally {
            _releaseReadLock();
          }
        } else {
          // 等待新消息
          final completer = Completer<V>();
          StreamSubscription? subscription;
          
          subscription = _messageController.stream.listen((message) {
            if (message != null) {
              final messageLocalId = getLocalId(message);
              final messageCommand = getCommand(message);
              
              if (messageLocalId == localId && messageCommand == command) {
                completer.complete(message);
                subscription?.cancel();
              }
            } else {
              // 通知信号，重新检查队列
              final polledMessage = _poll(localId, command);
              if (polledMessage != null) {
                completer.complete(polledMessage);
                subscription?.cancel();
              }
            }
          });
          
          _releaseQueueLock();
          final result = await completer.future;
          _acquireQueueLock();
          return result;
        }
      } finally {
        _releaseQueueLock();
      }
    }
  }

  /// 开始监听指定本地ID的流
  void startListening(int localId) {
    _openStreams.add(localId);
    _queues.putIfAbsent(localId, () => {});
  }

  /// 停止监听指定本地ID的流
  void stopListening(int localId) {
    _openStreams.remove(localId);
    _queues.remove(localId);
  }

  /// 确保队列为空（用于测试）
  void ensureEmpty() {
    if (_queues.isNotEmpty) {
      throw StateError('队列不为空: ${_queues.keys.map((id) => '0x${id.toRadixString(16)}').join(', ')}');
    }
    if (_openStreams.isNotEmpty) {
      throw StateError('打开的流不为空: ${_openStreams.map((id) => '0x${id.toRadixString(16)}').join(', ')}');
    }
  }

  /// 从队列中轮询消息
  V? _poll(int localId, int command) {
    final streamQueues = _queues[localId];
    if (streamQueues == null) {
      throw StateError('未监听本地ID: $localId');
    }
    
    final message = streamQueues[command]?.first;
    if (message == null && !_openStreams.contains(localId)) {
      throw AdbStreamClosed(localId);
    }
    
    if (message != null) {
      streamQueues[command]?.removeFirst();
    }
    
    return message;
  }

  /// 读取消息并添加到队列
  Future<void> _read() async {
    final message = await readMessage();
    final localId = getLocalId(message);

    if (isCloseCommand(message)) {
      _openStreams.remove(localId);
      return;
    }

    final streamQueues = _queues[localId];
    if (streamQueues == null) {
      return;
    }

    final command = getCommand(message);
    final commandQueue = streamQueues.putIfAbsent(command, () => Queue());
    commandQueue.add(message);
    _messageController.add(message);
  }

  /// 获取队列锁
  Future<void> _acquireQueueLock() async {
    if (!_queueLocked) {
      _queueLocked = true;
      return;
    }
    
    final completer = Completer<void>();
    _queueWaiters.add(completer);
    await completer.future;
  }

  /// 释放队列锁
  void _releaseQueueLock() {
    if (_queueWaiters.isNotEmpty) {
      final next = _queueWaiters.removeAt(0);
      next.complete();
    } else {
      _queueLocked = false;
    }
  }

  /// 尝试获取读取锁
  Future<bool> _tryAcquireReadLock() async {
    if (!_readLocked) {
      _readLocked = true;
      return true;
    }
    return false;
  }

  /// 释放读取锁
  void _releaseReadLock() {
    if (_readWaiters.isNotEmpty) {
      final next = _readWaiters.removeAt(0);
      next.complete();
    } else {
      _readLocked = false;
    }
  }

  /// 抽象方法：读取消息
  Future<V> readMessage();

  /// 抽象方法：获取消息的本地ID
  int getLocalId(V message);

  /// 抽象方法：获取消息的命令
  int getCommand(V message);

  /// 抽象方法：判断是否为关闭命令
  bool isCloseCommand(V message);

  /// 关闭队列
  void close() {
    _messageController.close();
  }
}