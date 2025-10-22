import 'dart:async';
import 'dart:collection';

import '../core/adb_message.dart';
import '../core/adb_protocol.dart';
import '../core/adb_reader.dart';
import '../exception/adb_stream_closed.dart';

/// ADB消息队列
class AdbMessageQueue {
  static const int _defaultTimeoutSeconds = 10;
  static const int _nextTimeoutSeconds = 45;

  final AdbReader _adbReader;
  final Map<int, Map<int, Queue<AdbMessage>>> _queues = {};
  final Set<int> _openStreams = {};
  final StreamController<AdbMessage> _messageController =
      StreamController<AdbMessage>.broadcast();
  bool _isReading = false;
  bool _isClosed = false;

  AdbMessageQueue(this._adbReader);

  void startListening(int localId) {
    if (_isClosed) throw StateError('消息队列已关闭');
    _openStreams.add(localId);
    _queues[localId] = {};
  }

  void stopListening(int localId) {
    _openStreams.remove(localId);
    _queues.remove(localId);
  }

  Future<AdbMessage> take(int localId, int command) async {
    if (_isClosed) throw StateError('消息队列已关闭');

    if (!_openStreams.contains(localId)) {
      throw AdbStreamClosed(localId);
    }

    // 对于WRTE命令，使用无超时版本
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
        if (message.command == 0xFFFFFFFF && message.arg1 == localId) {
          if (!messageReceived && !completer.isCompleted) {
            messageReceived = true;
            completer.completeError(AdbStreamClosed(localId));
          }
          return;
        }

        if (_getLocalId(message) == localId && _getCommand(message) == command) {
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

  Future<AdbMessage> _takeWithoutTimeout(int localId, int command) async {
    if (_isClosed) throw StateError('消息队列已关闭');

    final completer = Completer<AdbMessage>();
    var messageReceived = false;

    try {
      final message = _poll(localId, command);
      if (message != null) return message;

      if (!_isReading) _startReading();

      final subscription = _messageController.stream.listen((message) {
        if (message.command == 0xFFFFFFFF && message.arg1 == localId) {
          if (!messageReceived && !completer.isCompleted) {
            messageReceived = true;
            completer.completeError(AdbStreamClosed(localId));
          }
          return;
        }

        if (_getLocalId(message) == localId && _getCommand(message) == command) {
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

  void _startReading() {
    if (_isReading || _isClosed) return;
    _isReading = true;
    _readMessages();
  }

  void _readMessages() async {
    while (!_isClosed && _isReading) {
      try {
        final message = await _adbReader.readMessage();
        final localId = _getLocalId(message);
        final command = _getCommand(message);

        if (_isCloseCommand(message)) {
          _openStreams.remove(localId);
          if (_queues.containsKey(localId)) {
            _queues.remove(localId);
          }

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
          continue;
        }

        if (_queues.containsKey(localId)) {
          final streamQueues = _queues[localId]!;
          if (!streamQueues.containsKey(command)) {
            streamQueues[command] = Queue<AdbMessage>();
          }
          streamQueues[command]!.add(message);
        }

        _messageController.add(message);
      } catch (e) {
        if (!_isClosed) {
          await Future.delayed(Duration(milliseconds: 50));
        }
      }
    }
  }

  int _getLocalId(AdbMessage message) => message.arg1;
  int _getCommand(AdbMessage message) => message.command;
  bool _isCloseCommand(AdbMessage message) => message.command == AdbProtocol.cmdClse;

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
      (message) {
        if (!isCompleted) completeWithMessage(message);
      },
      onError: completeWithError,
      onDone: () {
        if (!isCompleted) completeWithError(StateError('消息流已关闭'));
      },
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

    final timer = Timer(timeout, () {
      if (!messageReceived) {
        completer.completeError(TimeoutException('等待消息超时: localId=$localId, command=$command'));
      }
    });

    try {
      final message = _poll(localId, command);
      if (message != null) {
        messageReceived = true;
        timer.cancel();
        return message;
      }

      if (!_isReading) _startReading();

      final subscription = _messageController.stream.listen((message) {
        if (_getLocalId(message) == localId && _getCommand(message) == command) {
          if (!messageReceived && !completer.isCompleted) {
            messageReceived = true;
            timer.cancel();
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

  void close() {
    _isClosed = true;
    _isReading = false;
    _queues.clear();
    _openStreams.clear();
    _messageController.close();
    _adbReader.close();
  }
}
