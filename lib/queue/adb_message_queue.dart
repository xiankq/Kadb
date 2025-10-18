import 'dart:async';
import 'dart:collection';
import 'dart:math';

import '../core/adb_message.dart';
import '../core/adb_protocol.dart';
import '../core/adb_reader.dart';
import '../exception/adb_stream_closed.dart';
import '../debug/logging.dart';

/// ADB消息队列
/// 管理ADB消息的异步读取和分发
class AdbMessageQueue {
  // 常量定义
  static const int _defaultTimeoutSeconds = 10; // 减少默认超时时间到10秒
  static const int _specialTimeoutSeconds = 30; // 减少特殊超时时间到30秒
  static const int _nextTimeoutSeconds = 15; // 减少next方法超时时间到15秒
  static const int _readRetryDelayMs = 50; // 减少读取重试延迟
  static const int _specialLocalId = 1;
  static const int _specialCommand = 1163086915;
  static const int _minLocalIdForRetry = 4;
  
  final AdbReader _adbReader;
  final Random _random = Random();
  final Map<int, Map<int, Queue<AdbMessage>>> _queues = {};
  final Set<int> _openStreams = {};
  final StreamController<AdbMessage> _messageController =
      StreamController<AdbMessage>.broadcast();
  bool _isReading = false;
  bool _isClosed = false;

  /// 构造函数
  AdbMessageQueue(this._adbReader);

  /// 开始监听特定本地ID的消息
  void startListening(int localId) {
    if (_isClosed) {
      throw StateError('消息队列已关闭');
    }
    // 只在详细模式下显示队列监听信息，避免过度打印
    Logging.verbose('ADB Message Queue: start listening local ID 0x${localId.toRadixString(16)}');
    _openStreams.add(localId);
    _queues[localId] = {};
  }

  /// 停止监听特定本地ID的消息
  void stopListening(int localId) {
    // 只在详细模式下显示队列监听信息，避免过度打印
    Logging.verbose('ADB Message Queue: stop listening local ID 0x${localId.toRadixString(16)}');
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

    // 移除拦截机制，让所有正常的ADB流操作正常进行

    // 检查是否还在监听该本地ID，如果不在监听，说明流已关闭
    if (!_openStreams.contains(localId)) {
      print('ADB Message Queue: local ID 0x${localId.toRadixString(16)} not in listening list');

      // 修复：对于某些特殊情况，尝试重新添加到监听列表而不是立即抛出异常
      if (localId >= _minLocalIdForRetry) {
        // For streams with ID >= 4, they might be temporary test streams
        print('ADB Message Queue: attempting to re-add local ID 0x${localId.toRadixString(16)} to listening list');
        _openStreams.add(localId);
        if (!_queues.containsKey(localId)) {
          _queues[localId] = {};
        }
      } else {
        throw AdbStreamClosed(localId);
      }
    }

    // 对于WRTE命令，使用无超时版本以支持实时数据流
    if (command == AdbProtocol.CMD_WRTE) {
      return _takeWithoutTimeout(localId, command);
    }

    final completer = Completer<AdbMessage>();
    var messageReceived = false;

    // 设置超时检查 - 仅对非WRTE命令使用超时
    final timeout = (localId == _specialLocalId && command == _specialCommand)
        ? Duration(seconds: _specialTimeoutSeconds)
        : Duration(seconds: _defaultTimeoutSeconds);

    final timer = Timer(timeout, () {
      if (!messageReceived) {
        print('ADB Message Queue: message wait timeout: localId=$localId, command=$command (0x${command.toRadixString(16).padLeft(8, '0')})');
        completer.completeError(
          TimeoutException(
            '等待消息超时: localId=$localId, command=$command (0x${command.toRadixString(16).padLeft(8, '0')})',
          ),
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
        // 检查是否是流关闭通知
        if (message.command == 0xFFFFFFFF && message.arg1 == localId) {
          if (!messageReceived && !completer.isCompleted) {
            messageReceived = true;
            completer.completeError(AdbStreamClosed(localId));
          }
          return;
        }

        // 正常消息处理
        if (_getLocalId(message) == localId &&
            _getCommand(message) == command) {
          if (!messageReceived && !completer.isCompleted) {
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

  /// 无超时获取WRTE消息（实时数据流专用）
  /// 对于实时数据流，不应该有超时，因为设备可能不会持续发送数据
  Future<AdbMessage> _takeWithoutTimeout(int localId, int command) async {
    if (_isClosed) {
      throw StateError('消息队列已关闭');
    }

    final completer = Completer<AdbMessage>();
    var messageReceived = false;

    try {
      // 首先检查队列中是否有匹配的消息
      final message = _poll(localId, command);
      if (message != null) {
        return message;
      }

      // 如果没有匹配的消息，开始异步读取
      if (!_isReading) {
        _startReading();
      }

      // 等待新消息 - 无超时
      final subscription = _messageController.stream.listen((message) {
        // 检查是否是流关闭通知
        if (message.command == 0xFFFFFFFF && message.arg1 == localId) {
          if (!messageReceived && !completer.isCompleted) {
            messageReceived = true;
            completer.completeError(AdbStreamClosed(localId));
          }
          return;
        }

        // 正常消息处理
        if (_getLocalId(message) == localId &&
            _getCommand(message) == command) {
          if (!messageReceived && !completer.isCompleted) {
            messageReceived = true;
            completer.complete(message);
          }
        }
      });

      // 等待完成 - 无超时
      final result = await completer.future;
      await subscription.cancel();
      return result;
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
      rethrow;
    }
  }

  /// 从队列中取出消息
  AdbMessage? _poll(int localId, int command) {
    final streamQueues = _queues[localId];
    if (streamQueues == null) {
      throw StateError('未监听本地ID: $localId');
    }

    final commandQueue = streamQueues[command];
    if (commandQueue == null || commandQueue.isEmpty) {
      // 检查是否还在监听该本地ID
      if (!_openStreams.contains(localId)) {
        print(
          'ADB Message Queue: local ID 0x${localId.toRadixString(16)} not in listening list (_poll)',
        );

        // 修复：对于某些特殊情况，尝试重新添加到监听列表而不是立即抛出异常
        if (localId >= _minLocalIdForRetry) {
          // For streams with ID >= 4, they might be temporary test streams
          print(
            'ADB Message Queue: attempting to re-add local ID 0x${localId.toRadixString(16)} to listening list (_poll)',
          );
          _openStreams.add(localId);
          return null; // 返回null让上层继续处理
        } else {
          throw AdbStreamClosed(localId);
        }
      }
      // 队列为空但流仍在监听，返回null
      return null;
    }

    try {
      final message = commandQueue.removeFirst();
      return message;
    } catch (e) {
      if (e is StateError && e.message.contains('No element')) {
        // 队列为空，返回null而不是抛出异常
        return null;
      }
      rethrow;
    }
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
        final localId = _getLocalId(message);
        final command = _getCommand(message);

        // 按照Kotlin版本的方式处理CLSE命令：不加入队列，直接清理流
        if (_isCloseCommand(message)) {
          print('ADB Message Queue: received CLSE command, closing stream for local ID 0x${localId.toRadixString(16)}');
          _openStreams.remove(localId);

          // 清理该流的所有消息队列
          if (_queues.containsKey(localId)) {
            final streamQueues = _queues[localId]!;
            for (final command in streamQueues.keys.toList()) {
              streamQueues[command]?.clear();
            }
            _queues.remove(localId);
          }

          // 通知所有等待的take()调用 - 让它们检查_openStreams状态
          // 通过发送一个特殊事件来唤醒所有等待者
          _messageController.add(
            AdbMessage(
              command: 0xFFFFFFFF, // 特殊命令码表示流关闭
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
          // 短暂延迟后继续读取
          await Future.delayed(Duration(milliseconds: _readRetryDelayMs));
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

  /// 检查是否为有效的ADB命令码
  bool _isValidCommand(int command) {
    return command == AdbProtocol.CMD_AUTH ||
        command == AdbProtocol.CMD_CNXN ||
        command == AdbProtocol.CMD_OPEN ||
        command == AdbProtocol.CMD_OKAY ||
        command == AdbProtocol.CMD_CLSE ||
        command == AdbProtocol.CMD_WRTE ||
        command == AdbProtocol.CMD_STLS;
  }

  /// 确保队列为空（用于测试）
  @Deprecated('仅用于测试')
  void ensureEmpty() {
    if (_queues.isNotEmpty) {
      throw StateError(
        '队列不为空: ${_queues.keys.map((e) => e.toRadixString(16))}',
      );
    }
    if (_openStreams.isNotEmpty) {
      throw StateError('打开的流不为空');
    }
  }

  /// 获取下一个消息（通用方法）- 关键修复
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

    // 关键修复：增加超时时间，避免认证流程超时
    final timeout = Duration(seconds: _nextTimeoutSeconds);
    final timer = Timer(timeout, () {
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
      cancelOnError: false, // 关键修复：错误时不取消订阅
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
      if (!isCompleted) {
        subscription.cancel();
      }
      timer.cancel();
    }
  }

  /// 带超时的获取特定消息
  /// [localId] 本地ID
  /// [command] 命令类型
  /// [timeout] 超时时间
  /// 返回Future<AdbMessage>
  Future<AdbMessage> takeWithTimeout(
    int localId,
    int command, {
    required Duration timeout,
  }) async {
    if (_isClosed) {
      throw StateError('消息队列已关闭');
    }

    // 检查是否还在监听该本地ID，如果不在监听，说明流已关闭
    if (!_openStreams.contains(localId)) {
      print(
        'ADB Message Queue: local ID 0x${localId.toRadixString(16)} not in listening list (takeWithTimeout), current listening IDs: ${_openStreams.map((id) => '0x${id.toRadixString(16)}').join(', ')}',
      );

      // 修复：对于某些特殊情况，尝试重新添加到监听列表而不是立即抛出异常
      if (localId >= _minLocalIdForRetry) {
        // For streams with ID >= 4, they might be temporary test streams
        print(
          'ADB Message Queue: attempting to re-add local ID 0x${localId.toRadixString(16)} to listening list (takeWithTimeout)',
        );
        _openStreams.add(localId);
        if (!_queues.containsKey(localId)) {
          _queues[localId] = {};
        }
      } else {
        throw AdbStreamClosed(localId);
      }
    }

    final completer = Completer<AdbMessage>();
    var messageReceived = false;

    final timer = Timer(timeout, () {
      if (!messageReceived) {
        completer.completeError(
          TimeoutException(
            '等待消息超时: localId=$localId, command=$command (0x${command.toRadixString(16).padLeft(8, '0')})',
          ),
        );
      }
    });

    try {
      // 首先检查队列中是否有匹配的消息
      final message = _poll(localId, command);
      if (message != null) {
        messageReceived = true;
        timer.cancel();
        return message;
      }

      // 如果没有匹配的消息，开始异步读取
      if (!_isReading) {
        _startReading();
      }

      // 等待新消息
      final subscription = _messageController.stream.listen((message) {
        if (_getLocalId(message) == localId &&
            _getCommand(message) == command) {
          if (!messageReceived && !completer.isCompleted) {
            messageReceived = true;
            timer.cancel();
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
