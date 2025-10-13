import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:kadb_dart/core/adb_message.dart';
import 'package:kadb_dart/core/adb_protocol.dart';
import 'package:kadb_dart/core/adb_reader.dart';
import 'package:kadb_dart/exception/adb_stream_closed.dart';

/// ADB消息队列
/// 管理ADB消息的异步读取和分发
class AdbMessageQueue {
  final AdbReader _adbReader;
  final Random _random = Random();
  final Map<int, Map<int, Queue<AdbMessage>>> _queues = {};
  final Set<int> _openStreams = {};
  final StreamController<AdbMessage> _messageController = StreamController<AdbMessage>.broadcast();
  bool _isReading = false;
  bool _isClosed = false;

  /// 构造函数
  AdbMessageQueue(this._adbReader);

  /// 开始监听特定本地ID的消息
  void startListening(int localId) {
    if (_isClosed) {
      throw StateError('消息队列已关闭');
    }
    _openStreams.add(localId);
    _queues[localId] = {};
  }

  /// 停止监听特定本地ID的消息
  void stopListening(int localId) {
    _openStreams.remove(localId);
    _queues.remove(localId);
  }

  /// 获取特定消息
  /// [localId] 本地ID
  /// [command] 命令类型
  /// 返回Future<AdbMessage>
  Future<AdbMessage> take(int localId, int command) async {
    if (_isClosed) {
      throw StateError('消息队列已关闭');
    }

    final completer = Completer<AdbMessage>();
    var messageReceived = false;

    // 设置超时检查
    final timeout = Duration(seconds: 10);
    final timer = Timer(timeout, () {
      if (!messageReceived) {
        completer.completeError(
          TimeoutException('等待消息超时: localId=$localId, command=$command'),
        );
      }
    });

    try {
      // 首先检查队列中是否有匹配的消息
      final message = _poll(localId, command);
      if (message != null) {
        messageReceived = true;
        return message;
      }

      // 如果没有匹配的消息，开始异步读取
      if (!_isReading) {
        _startReading();
      }

      // 等待新消息
      final subscription = _messageController.stream.listen((message) {
        if (_getLocalId(message) == localId && _getCommand(message) == command) {
          if (!messageReceived) {
            messageReceived = true;
            completer.complete(message);
          }
        }
      });

      // 等待完成
      final result = await completer.future;
      await subscription.cancel();
      return result;
    } finally {
      timer.cancel();
    }
  }

  /// 从队列中取出消息
  AdbMessage? _poll(int localId, int command) {
    final streamQueues = _queues[localId];
    if (streamQueues == null) {
      throw StateError('未监听本地ID: $localId');
    }

    final message = streamQueues[command]?.removeFirst();
    if (message == null && !_openStreams.contains(localId)) {
      throw AdbStreamClosed(localId);
    }
    return message;
  }

  /// 开始异步读取消息
  void _startReading() {
    if (_isReading || _isClosed) {
      return;
    }

    _isReading = true;
    _readMessages();
  }

  /// 异步读取消息循环
  void _readMessages() async {
    while (!_isClosed && _isReading) {
      try {
        final message = await _adbReader.readMessage();
        
        if (_isCloseCommand(message)) {
          final localId = _getLocalId(message);
          _openStreams.remove(localId);
          continue;
        }

        final localId = _getLocalId(message);
        final command = _getCommand(message);

        // 如果该本地ID正在被监听，将消息加入队列
        if (_queues.containsKey(localId)) {
          final streamQueues = _queues[localId]!;
          if (!streamQueues.containsKey(command)) {
            streamQueues[command] = Queue<AdbMessage>();
          }
          streamQueues[command]!.add(message);
        }

        // 通知所有监听器
        _messageController.add(message);
      } catch (e) {
        if (!_isClosed) {
          print('读取消息错误: $e');
          // 短暂延迟后继续读取
          await Future.delayed(Duration(milliseconds: 100));
        }
      }
    }
  }

  /// 获取消息的本地ID
  int _getLocalId(AdbMessage message) {
    return message.arg1;
  }

  /// 获取消息的命令类型
  int _getCommand(AdbMessage message) {
    return message.command;
  }

  /// 检查是否为关闭命令
  bool _isCloseCommand(AdbMessage message) {
    return message.command == AdbProtocol.CMD_CLSE;
  }

  /// 确保队列为空（用于测试）
  @Deprecated('仅用于测试')
  void ensureEmpty() {
    if (_queues.isNotEmpty) {
      throw StateError('队列不为空: ${_queues.keys.map((e) => e.toRadixString(16))}');
    }
    if (_openStreams.isNotEmpty) {
      throw StateError('打开的流不为空');
    }
  }

  /// 获取下一个消息（通用方法）
  /// 返回下一个可用的ADB消息
  Future<AdbMessage> next() async {
    if (_isClosed) {
      throw StateError('消息队列已关闭');
    }

    if (!_isReading) {
      _startReading();
    }

    final completer = Completer<AdbMessage>();
    bool isCompleted = false;

    // 设置超时检查
    final timeout = Duration(seconds: 30);
    final timer = Timer(timeout, () {
      if (!isCompleted) {
        isCompleted = true;
        completer.completeError(TimeoutException('等待消息超时'));
      }
    });

    StreamSubscription<AdbMessage>? subscription;

    void completeWithMessage(AdbMessage message) {
      if (!isCompleted) {
        isCompleted = true;
        subscription?.cancel();
        timer.cancel();
        completer.complete(message);
      }
    }

    void completeWithError(Object error) {
      if (!isCompleted) {
        isCompleted = true;
        subscription?.cancel();
        timer.cancel();
        completer.completeError(error);
      }
    }

    // 监听所有消息
    subscription = _messageController.stream.listen(
      (message) {
        // 只处理第一个匹配的消息
        if (!isCompleted) {
          completeWithMessage(message);
        }
      },
      onError: completeWithError,
      onDone: () {
        if (!isCompleted) {
          completeWithError(StateError('消息流已关闭'));
        }
      },
    );

    try {
      // 同时检查队列中是否有现有消息
      for (final streamQueues in _queues.values) {
        for (final queue in streamQueues.values) {
          if (queue.isNotEmpty && !isCompleted) {
            final message = queue.removeFirst();
            completeWithMessage(message);
            break;
          }
        }
        if (isCompleted) break;
      }

      // 如果没有现有消息，等待新消息
      if (!isCompleted) {
        return await completer.future;
      } else {
        return completer.future;
      }
    } catch (e) {
      if (!isCompleted) {
        completeWithError(e);
      }
      rethrow;
    } finally {
      subscription.cancel();
      timer.cancel();
    }
  }

  /// 关闭消息队列
  void close() {
    _isClosed = true;
    _isReading = false;
    _queues.clear();
    _openStreams.clear();
    _messageController.close();
    _adbReader.close();
  }
}