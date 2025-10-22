import 'dart:async';
import 'dart:collection';

import '../core/adb_message.dart';
import '../core/adb_protocol.dart';
import '../core/adb_reader.dart';
import '../utils/adb_stream_closed.dart';

/// ADB消息队列，负责管理ADB协议的消息队列和流操作
class AdbMessageQueue {
  static const int _defaultTimeoutSeconds = 10;
  static const int _nextTimeoutSeconds = 45;
  static const int _maxQueueSize = 1000;

  final AdbReader _adbReader;
  final Map<int, Map<int, Queue<AdbMessage>>> _queues = {};
  final Set<int> _openStreams = {};
  final StreamController<AdbMessage> _messageController =
      StreamController<AdbMessage>.broadcast();

  bool _isReading = false;
  bool _isClosed = false;

  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 5;

  AdbMessageQueue(this._adbReader);

  /// 开始监听指定本地ID的消息
  void startListening(int localId) {
    if (_isClosed) throw StateError('消息队列已关闭');
    _openStreams.add(localId);
    _queues[localId] = {};
  }

  /// 停止监听指定本地ID的消息
  void stopListening(int localId) {
    _openStreams.remove(localId);
    _queues.remove(localId);
  }

  /// 获取指定本地ID和命令的消息
  Future<AdbMessage> take(int localId, int command) async {
    if (_isClosed) throw StateError('消息队列已关闭');
    if (!_openStreams.contains(localId)) throw AdbStreamClosed(localId);

    // WRTE命令使用无超时版本
    if (command == AdbProtocol.cmdWrte) {
      return _takeWithoutTimeout(localId, command);
    }

    final completer = Completer<AdbMessage>();
    var messageReceived = false;

    final timer = Timer(Duration(seconds: _defaultTimeoutSeconds), () {
      if (!messageReceived) {
        completer.completeError(
          TimeoutException('等待消息超时: localId=$localId, command=$command'),
        );
      }
    });

    try {
      final message = _poll(localId, command);
      if (message != null) {
        messageReceived = true;
        return message;
      }

      if (!_isReading) _startReading();

      final subscription = _messageController.stream.listen((message) {
        if (_getLocalId(message) == localId &&
            _getCommand(message) == command) {
          if (!messageReceived && !completer.isCompleted) {
            messageReceived = true;
            completer.complete(message);
          }
        }
      });

      final result = await completer.future;
      await subscription.cancel();
      return result;
    } finally {
      timer.cancel();
    }
  }

  /// 获取指定本地ID和命令的消息（无超时）
  Future<AdbMessage> _takeWithoutTimeout(int localId, int command) async {
    if (_isClosed) throw StateError('消息队列已关闭');
    if (!_openStreams.contains(localId)) throw AdbStreamClosed(localId);

    final completer = Completer<AdbMessage>();
    var messageReceived = false;

    try {
      final message = _poll(localId, command);
      if (message != null) return message;

      if (!_isReading) _startReading();

      final subscription = _messageController.stream.listen((message) {
        if (_getLocalId(message) == localId &&
            _getCommand(message) == command) {
          if (!messageReceived && !completer.isCompleted) {
            messageReceived = true;
            completer.complete(message);
          }
        }
      });

      final result = await completer.future;
      await subscription.cancel();
      return result;
    } catch (e) {
      if (!completer.isCompleted) completer.completeError(e);
      rethrow;
    }
  }

  /// 轮询指定本地ID和命令的消息
  AdbMessage? _poll(int localId, int command) {
    final streamQueues = _queues[localId];
    if (streamQueues == null) throw StateError('未监听本地ID: $localId');

    final commandQueue = streamQueues[command];
    if (commandQueue == null || commandQueue.isEmpty) {
      if (!_openStreams.contains(localId)) throw AdbStreamClosed(localId);
      return null;
    }

    try {
      return commandQueue.removeFirst();
    } catch (e) {
      if (e is StateError && e.message.contains('No element')) return null;
      rethrow;
    }
  }

  /// 开始读取消息
  void _startReading() {
    if (_isReading || _isClosed) return;
    _isReading = true;
    _readMessages();
  }

  /// 读取消息循环
  Future<void> _readMessages() async {
    while (!_isClosed && _isReading) {
      try {
        final message = await _adbReader.readMessage();
        _consecutiveErrors = 0;
        await _processMessage(message);
      } catch (e) {
        _consecutiveErrors++;

        if (_consecutiveErrors >= _maxConsecutiveErrors) {
          break;
        }

        await Future.delayed(Duration(milliseconds: 100));
      }
    }

    _isReading = false;
  }

  /// 处理消息
  Future<void> _processMessage(AdbMessage message) async {
    final localId = _getLocalId(message);
    final command = _getCommand(message);

    if (_isCloseCommand(message)) {
      _openStreams.remove(localId);
      _queues.remove(localId);

      _messageController.add(
        AdbMessage(
          command: 0xFFFFFFFF,
          arg0: 0,
          arg1: localId,
          payloadLength: 0,
          checksum: 0,
          magic: 0,
          payload: [],
        ),
      );
      return;
    }

    if (_queues.containsKey(localId)) {
      final streamQueues = _queues[localId]!;
      if (!streamQueues.containsKey(command)) {
        streamQueues[command] = Queue<AdbMessage>();
      }

      if (streamQueues[command]!.length >= _maxQueueSize) {
        streamQueues[command]!.removeFirst();
      }

      streamQueues[command]!.add(message);
    }

    _messageController.add(message);
  }

  int _getLocalId(AdbMessage message) => message.arg1;
  int _getCommand(AdbMessage message) => message.command;
  bool _isCloseCommand(AdbMessage message) =>
      message.command == AdbProtocol.cmdClse;

  /// 获取下一个消息
  Future<AdbMessage> next() async {
    if (_isClosed) throw StateError('消息队列已关闭');
    if (!_isReading) _startReading();

    final completer = Completer<AdbMessage>();
    bool isCompleted = false;

    final timer = Timer(Duration(seconds: _nextTimeoutSeconds), () {
      if (!isCompleted) {
        isCompleted = true;
        completer.completeError(TimeoutException('认证流程等待消息超时'));
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

    subscription = _messageController.stream.listen(
      (message) => !isCompleted ? completeWithMessage(message) : null,
      onError: completeWithError,
      onDone: () =>
          !isCompleted ? completeWithError(StateError('消息流已关闭')) : null,
      cancelOnError: false,
    );

    try {
      for (final streamQueues in _queues.values) {
        for (final queue in streamQueues.values) {
          if (queue.isNotEmpty && !isCompleted) {
            completeWithMessage(queue.removeFirst());
            break;
          }
        }
        if (isCompleted) break;
      }

      if (!isCompleted) {
        return await completer.future;
      } else {
        return completer.future;
      }
    } catch (e) {
      if (!isCompleted) completeWithError(e);
      rethrow;
    } finally {
      if (!isCompleted) subscription.cancel();
      timer.cancel();
    }
  }

  /// 带超时的获取特定消息
  Future<AdbMessage> takeWithTimeout(
    int localId,
    int command, {
    required Duration timeout,
  }) async {
    if (_isClosed) throw StateError('消息队列已关闭');
    if (!_openStreams.contains(localId)) throw AdbStreamClosed(localId);

    final completer = Completer<AdbMessage>();
    var messageReceived = false;

    final message = _poll(localId, command);
    if (message != null) {
      return message;
    }

    if (!_isReading) _startReading();

    final timer = Timer(timeout, () {
      if (!messageReceived) {
        completer.completeError(
          TimeoutException('等待消息超时: localId=$localId, command=$command'),
        );
      }
    });

    final subscription = _messageController.stream.listen((message) {
      if (_getLocalId(message) == localId && _getCommand(message) == command) {
        if (!messageReceived && !completer.isCompleted) {
          messageReceived = true;
          completer.complete(message);
        }
      }
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  /// 关闭消息队列
  void close() {
    if (!_isClosed) {
      _isClosed = true;
      _isReading = false;
      _queues.clear();
      _openStreams.clear();
      _messageController.close();
      _adbReader.close();
    }
  }

  bool get isClosed => _isClosed;
  bool get isReading => _isReading;
}
