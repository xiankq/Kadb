import 'dart:async';
import 'dart:typed_data';

import '../core/adb_protocol.dart';
import '../core/adb_writer.dart';
import '../queue/adb_message_queue.dart';
import '../exception/adb_stream_closed.dart';

/// ADB流数据源接口
abstract class AdbStreamSource {
  /// 获取数据流
  Stream<List<int>> get stream;

  /// 读取一个字节
  Future<int> readByte();

  /// 读取指定长度的字节
  Future<Uint8List> readBytes(int length);

  /// 从流中读取指定数量的字节
  Future<List<int>> take(int count);

  /// 转换流数据
  Stream<S> transform<S>(StreamTransformer<List<int>, S> transformer);

  /// 关闭数据源
  Future<void> close();
}

/// ADB流数据接收器接口
abstract class AdbStreamSink {
  /// 写入一个字节
  Future<void> writeByte(int byte);

  /// 写入字节数据
  Future<void> writeBytes(List<int> bytes);

  /// 向流中写入数据
  Future<void> add(List<int> data);

  /// 添加流数据
  Future<void> addStream(Stream<List<int>> stream);

  /// 刷新缓冲区
  Future<void> flush();

  /// 关闭接收器
  Future<void> close();
}

/// ADB流类
/// 管理ADB协议的数据流传输
class AdbStream {
  // 常量定义
  static const int _maxRetries = 3;
  static const int _defaultMaxPayloadSize = 1024 * 1024;
  static const int _chunkSize = 128 * 1024; // 标准：128KB，平衡性能和兼容性
  static const int _remoteIdAssignmentTimeoutSeconds = 5; // 标准：5秒远程ID分配超时
  static const int _remoteIdAssignmentMaxAttempts = 3; // 标准：3次重试
  static const int _retryBaseDelayMs = 500; // 标准：500ms基础延迟
  static const int _errorBaseDelayMs = 200; // 标准：200ms错误延迟

  final AdbMessageQueue _messageQueue;
  final AdbWriter _adbWriter;
  final int _maxPayloadSize;
  final int _localId;
  int _remoteId; // 远程ID，会在连接后分配
  final Completer<void> _remoteIdCompleter = Completer<void>();

  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>.broadcast(); // 标准：支持多订阅者
  final StreamController<void> _closeController =
      StreamController<void>.broadcast();

  bool _isClosed = false;
  bool _isReading = false;
  int _retryCount = 0;

  AdbStream({
    required int localId,
    required int remoteId,
    required String destination,
    required AdbMessageQueue messageQueue,
    required AdbWriter writer,
    int? maxPayloadSize,
    bool debug = false,
  }) : _localId = localId,
       _remoteId = remoteId, // 初始远程ID为0，连接后会更新
       _messageQueue = messageQueue,
       _adbWriter = writer,
       _maxPayloadSize = maxPayloadSize ?? _defaultMaxPayloadSize {
    // 注册本地ID到消息队列
    _messageQueue.startListening(_localId);
    _startReading();
  }

  /// 获取数据流
  Stream<Uint8List> get dataStream => _dataController.stream;

  /// 获取关闭流
  Stream<void> get closeStream => _closeController.stream;

  /// 获取数据源
  AdbStreamSource get source => AdbStreamSourceImpl(this);

  /// 获取数据接收器
  AdbStreamSink get sink => AdbStreamSinkImpl(this);

  /// 等待远程ID分配
  /// 当打开流后，设备会响应一个OKAY消息，其中包含远程ID
  Future<void> waitForRemoteId() {
    return _remoteIdCompleter.future;
  }

  /// 获取当前远程ID
  int get remoteId => _remoteId;

  /// 写入数据到流
  /// [data] 要写入的数据
  Future<void> write(Uint8List data) async {
    if (_isClosed) {
      throw StateError('流已关闭');
    }

    try {
      final chunks = _splitData(data);
      for (final chunk in chunks) {
        await _adbWriter.writeWrite(
          _localId,
          _remoteId,
          chunk,
          0,
          chunk.length,
        );
      }
    } catch (e) {
      throw StateError('写入数据失败: $e');
    }
  }

  /// 关闭流
  Future<void> close() async {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    _isReading = false;
    
    // 安全关闭所有资源
    await _safeExecute(() async => await _adbWriter.writeClose(_localId, _remoteId),
                         '发送关闭命令');
    _safeExecuteSync(() => _messageQueue.stopListening(_localId),
                      '停止监听本地ID');
    await _safeExecute(() async => await _dataController.close(),
                         '关闭数据流');
    await _safeExecute(() async => await _closeController.close(),
                         '关闭关闭流');
  }

  /// 安全执行异步操作，捕获并记录异常
  Future<void> _safeExecute(Future<void> Function() operation, String operationName) async {
    try {
      await operation();
    } catch (e) {
      print('ADB Stream: error during $operationName: $e');
    }
  }

  /// 安全执行同步操作，捕获并记录异常
  void _safeExecuteSync(void Function() operation, String operationName) {
    try {
      operation();
    } catch (e) {
      print('ADB Stream: error during $operationName: $e');
    }
  }

  /// 开始读取数据
  void _startReading() {
    if (_isReading) return;
    _isReading = true;
    _readLoop().catchError((error) {
      if (!_isClosed) {
        _dataController.addError(error);
        _close();
      }
    });
  }

  /// 读取循环 - 实时数据流优化版本
  Future<void> _readLoop() async {
    // First, wait for the OKAY message that assigns the remote ID
    try {
      await _waitForRemoteIdAssignment();
    } catch (e) {
      print('ADB Stream: failed to wait for remote ID assignment: $e');
      await _close();
      return;
    }

    while (!_isClosed) {
      try {
        // 使用无超时的take方法，实现实时数据读取
        final message = await _messageQueue.take(_localId, AdbProtocol.CMD_WRTE);

        // 重置重试计数器
        _retryCount = 0;

        // 接收到数据 - 零拷贝优化
        if (message.payload.isNotEmpty) {
          // 避免不必要的拷贝 - 直接传递数据
          final payloadUint8 = Uint8List.fromList(message.payload);
          _dataController.add(payloadUint8);
        }

        // 发送确认
        await _adbWriter.writeOkay(_localId, _remoteId);
      } catch (e) {
        if (!_isClosed) {
          // 改进错误处理逻辑，提供更好的错误恢复机制
          final errorString = e.toString();
          
          if (e is AdbStreamClosed || errorString.contains('AdbStreamClosed')) {
            print('ADB Stream: stream closed normally');
            await _close();
            break;
          } else if (errorString.contains('CLSE')) {
            print('ADB Stream: device closed stream');
            await _close();
            break;
          } else if (errorString.contains('TimeoutException')) {
            // For real-time data streams, timeout might be normal as device may not send data temporarily
            // Add log level check to avoid excessive warning output
            if (_retryCount % 10 == 0) { // Only warn every 10 retries
              print('ADB Stream: read timeout, retry $_retryCount/$_maxRetries');
            }
            
            if (await _handleRetryWithBackoff('timeout', _retryBaseDelayMs)) {
              continue;
            } else {
              print('ADB Stream: read timeout, reached maximum retries');
              await _close();
              break;
            }
          } else if (errorString.contains('StateError') && errorString.contains('消息队列已关闭')) {
            print('ADB Stream: message queue closed, stream terminated');
            await _close();
            break;
          } else {
            if (await _handleRetryWithBackoff('error', _errorBaseDelayMs)) {
              continue;
            } else {
              print('ADB Stream: read error, reached maximum retries: $e');
              await _close();
              break;
            }
          }
        }
      }
    }

    _isReading = false;
  }

  /// 等待远程ID分配
  /// 当打开流后，设备会响应一个OKAY消息，其中包含远程ID
  Future<void> _waitForRemoteIdAssignment() async {
    for (int attempts = 1; attempts <= _remoteIdAssignmentMaxAttempts && !_isClosed; attempts++) {
      try {
        // 等待OKAY消息，它包含分配给此流的远程ID
        final okayMessage = await _messageQueue.takeWithTimeout(
          _localId,
          AdbProtocol.CMD_OKAY,
          timeout: Duration(seconds: _remoteIdAssignmentTimeoutSeconds),
        );
        _remoteId = okayMessage.arg0; // arg0 contains the remote ID

        print('ADB Stream: local ID 0x${_localId.toRadixString(16)} assigned remote ID 0x${_remoteId.toRadixString(16)}');

        // 完成远程ID等待
        if (!_remoteIdCompleter.isCompleted) {
          _remoteIdCompleter.complete();
        }
        return;
      } catch (e) {
        print('ADB Stream: failed to wait for remote ID assignment (attempt $attempts/$_remoteIdAssignmentMaxAttempts): $e');

        if (attempts >= _remoteIdAssignmentMaxAttempts || _isClosed) {
          // 如果达到最大重试次数或流已关闭，完成Completer
          if (!_remoteIdCompleter.isCompleted) {
            _remoteIdCompleter.completeError(e);
          }
          rethrow;
        }

        // 等待一段时间后重试
        if (!_isClosed) {
          await Future.delayed(Duration(seconds: 1));
        }
      }
    }
  }

  /// 内部关闭方法
  Future<void> _close() async {
    if (!_isClosed) {
      _isClosed = true;
      _isReading = false;

      // 停止监听本地ID
      try {
        _messageQueue.stopListening(_localId);
      } catch (e) {
        print('ADB Stream: error stopping local ID listener: $e');
      }

      // 发送关闭通知
      try {
        _closeController.add(null);
      } catch (e) {
        // 忽略控制器已关闭的异常
      }

      // 关闭数据流
      try {
        await _dataController.close();
      } catch (e) {
        print('ADB Stream: error closing data stream: $e');
      }

      // 关闭关闭流
      try {
        await _closeController.close();
      } catch (e) {
        print('ADB Stream: error closing close stream: $e');
      }
    }
  }

  /// 分割数据为适合传输的块
  List<Uint8List> _splitData(Uint8List data) {
    if (data.length <= _chunkSize) {
      return [data];
    }

    final chunks = <Uint8List>[];
    for (int offset = 0; offset < data.length; offset += _chunkSize) {
      final end = offset + _chunkSize;
      final actualChunkSize = end > data.length ? data.length - offset : _chunkSize;
      chunks.add(data.sublist(offset, offset + actualChunkSize));
    }

    return chunks;
  }

  /// 处理带指数退避的重试
  /// 返回true表示应该继续重试，false表示达到最大重试次数
  Future<bool> _handleRetryWithBackoff(String errorType, int baseDelayMs) async {
    _retryCount++;
    if (_retryCount <= _maxRetries) {
      final delay = Duration(milliseconds: baseDelayMs * _retryCount);
      // 减少警告输出频率，只在特定重试次数时输出
      if (_retryCount == 1 || _retryCount == _maxRetries) {
        print('ADB Stream: read $errorType, retry $_retryCount/$_maxRetries, waiting ${delay.inMilliseconds}ms');
      }
      await Future.delayed(delay);
      return true;
    }
    return false;
  }
}

/// ADB流数据源实现
class AdbStreamSourceImpl implements AdbStreamSource {
  final AdbStream _stream;
  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>();
  final Completer<void> _closeCompleter = Completer<void>();

  AdbStreamSourceImpl(this._stream) {
    _stream.dataStream.listen(
      (data) {
        _dataController.add(data);
      },
      onDone: () {
        _dataController.close();
        _closeCompleter.complete();
      },
    );
  }

  @override
  Stream<List<int>> get stream => _dataController.stream.map((data) => data);

  @override
  Future<int> readByte() async {
    final bytes = await readBytes(1);
    return bytes.isNotEmpty ? bytes[0] : -1;
  }

  @override
  Future<Uint8List> readBytes(int length) async {
    final completer = Completer<Uint8List>();
    final buffer = <int>[];

    StreamSubscription<Uint8List>? subscription;
    subscription = _dataController.stream.listen((data) {
      buffer.addAll(data);
      if (buffer.length >= length) {
        subscription?.cancel();
        completer.complete(Uint8List.fromList(buffer.sublist(0, length)));
      }
    });

    return completer.future;
  }

  @override
  Future<List<int>> take(int count) async {
    final bytes = await readBytes(count);
    return bytes.toList();
  }

  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> transformer) {
    return stream.transform(transformer);
  }

  @override
  Future<void> close() async {
    _dataController.close();
    await _closeCompleter.future;
  }
}

/// ADB流数据接收器实现
class AdbStreamSinkImpl implements AdbStreamSink {
  final AdbStream _stream;

  AdbStreamSinkImpl(this._stream);

  @override
  Future<void> writeByte(int byte) async {
    await writeBytes([byte]);
  }

  @override
  Future<void> writeBytes(List<int> bytes) async {
    // 优化：避免不必要的类型转换拷贝
    if (bytes.isEmpty) return;

    // 直接转换为Uint8List写入socket
    await _stream.write(Uint8List.fromList(bytes));
  }

  @override
  Future<void> add(List<int> data) async {
    await writeBytes(data);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      await add(data);
    }
  }

  @override
  Future<void> flush() async {
    // ADB流写入是同步的，无需特殊刷新操作
  }

  @override
  Future<void> close() async {
    await _stream.close();
  }
}
