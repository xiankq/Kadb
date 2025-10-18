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
  final AdbMessageQueue _messageQueue;
  final AdbWriter _adbWriter;
  final int _maxPayloadSize;
  final int _localId;
  int
  _remoteId; // Make this mutable so it can be updated when the remote ID is assigned
  final Completer<void> _remoteIdCompleter = Completer<void>();

  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>.broadcast();
  final StreamController<void> _closeController =
      StreamController<void>.broadcast();

  bool _isClosed = false;
  bool _isReading = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  AdbStream({
    required int localId,
    required int remoteId,
    required String destination,
    required AdbMessageQueue messageQueue,
    required AdbWriter writer,
    bool debug = false,
  }) : _localId = localId,
       _remoteId =
           remoteId, // Initial remote ID is 0, will be updated after open
       _messageQueue = messageQueue,
       _adbWriter = writer,
       _maxPayloadSize = 1024 * 1024 {
    // 默认最大负载大小
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

    final chunks = _splitData(data);

    for (int i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      try {
        await _adbWriter.writeWrite(
          _localId,
          _remoteId,
          chunk,
          0,
          chunk.length,
        );
      } catch (e) {
        rethrow;
      }
    }
  }

  /// 关闭流
  Future<void> close() async {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    _isReading = false;

    // 发送关闭命令
    try {
      await _adbWriter.writeClose(_localId, _remoteId);
    } catch (e) {
      print('⚠️ 发送关闭命令时出错: $e');
    }

    // 停止监听本地ID
    try {
      _messageQueue.stopListening(_localId);
    } catch (e) {
      print('⚠️ 停止监听本地ID时出错: $e');
    }

    // 关闭数据流
    try {
      await _dataController.close();
    } catch (e) {
      print('⚠️ 关闭数据流时出错: $e');
    }

    // 关闭关闭流
    try {
      await _closeController.close();
    } catch (e) {
      print('⚠️ 关闭关闭流时出错: $e');
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

  /// 读取循环
  Future<void> _readLoop() async {
    // First, wait for the OKAY message that assigns the remote ID
    try {
      await _waitForRemoteIdAssignment();
    } catch (e) {
      print('❌ 等待远程ID分配失败: $e');
      await _close();
      return;
    }

    while (!_isClosed) {
      try {
        // 使用消息队列读取WRTE消息
        final message = await _messageQueue.take(
          _localId,
          AdbProtocol.CMD_WRTE,
        );

        // 重置重试计数器
        _retryCount = 0;

        // 接收到数据
        if (message.payload.isNotEmpty) {
          _dataController.add(Uint8List.fromList(message.payload));
        }

        // 发送确认
        await _adbWriter.writeOkay(_localId, _remoteId);
      } catch (e) {
        if (!_isClosed) {
          // 改进错误处理逻辑，提供更好的错误恢复机制
          if (e is AdbStreamClosed ||
              e.toString().contains('AdbStreamClosed')) {
            // ADB流关闭，正常结束
            print('🔚 ADB流正常关闭');
            await _close();
            break;
          } else if (e.toString().contains('CLSE')) {
            // 设备主动关闭流，正常结束
            print('🔚 设备主动关闭ADB流');
            await _close();
            break;
          } else if (e.toString().contains('TimeoutException')) {
            // 超时异常，实现指数退避重试
            _retryCount++;
            if (_retryCount <= _maxRetries) {
              final delay = Duration(milliseconds: 500 * _retryCount);
              print(
                '⚠️ ADB流读取超时，重试 $_retryCount/$_maxRetries，等待 ${delay.inMilliseconds}ms',
              );
              await Future.delayed(delay);
              continue;
            } else {
              print('❌ ADB流读取超时，达到最大重试次数');
              await _close();
              break;
            }
          } else if (e.toString().contains('StateError') &&
              e.toString().contains('消息队列已关闭')) {
            // 消息队列关闭，连接已断开
            print('❌ 消息队列已关闭，ADB流终止');
            await _close();
            break;
          } else {
            // 其他异常，记录但继续尝试，增加延迟避免快速重试
            _retryCount++;
            if (_retryCount <= _maxRetries) {
              print('⚠️ ADB流读取异常 (重试 $_retryCount/$_maxRetries): $e');
              await Future.delayed(Duration(milliseconds: 200 * _retryCount));
              continue;
            } else {
              print('❌ ADB流读取异常，达到最大重试次数: $e');
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
    int attempts = 0;
    const maxAttempts = 3;

    while (attempts < maxAttempts && !_isClosed) {
      attempts++;
      try {
        // 等待OKAY消息，它包含分配给此流的远程ID
        final okayMessage = await _messageQueue.takeWithTimeout(
          _localId,
          AdbProtocol.CMD_OKAY,
          timeout: Duration(seconds: 5),
        );
        _remoteId = okayMessage.arg0; // arg0 contains the remote ID

        print(
          '✅ 本地ID 0x${_localId.toRadixString(16)} 成功分配远程ID 0x${_remoteId.toRadixString(16)}',
        );

        // 完成远程ID等待
        if (!_remoteIdCompleter.isCompleted) {
          _remoteIdCompleter.complete();
        }
        return;
      } catch (e) {
        print('⚠️ 等待远程ID分配失败 (尝试 $attempts/$maxAttempts): $e');

        if (attempts >= maxAttempts || _isClosed) {
          // 如果达到最大重试次数或流已关闭，完成Completer
          if (!_remoteIdCompleter.isCompleted) {
            _remoteIdCompleter.completeError(e);
          }
          rethrow;
        }

        // 等待一段时间后重试
        if (!_isClosed) {
          await Future.delayed(Duration(milliseconds: 1000));
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
        print('⚠️ 停止监听本地ID时出错: $e');
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
        print('⚠️ 关闭数据流时出错: $e');
      }

      // 关闭关闭流
      try {
        await _closeController.close();
      } catch (e) {
        print('⚠️ 关闭关闭流时出错: $e');
      }
    }
  }

  /// 分割数据为适合传输的块
  List<Uint8List> _splitData(Uint8List data) {
    final chunks = <Uint8List>[];
    var offset = 0;

    // 优化：增大块大小到128KB，提升视频流传输性能
    const int chunkSize = 128 * 1024; // 128KB

    while (offset < data.length) {
      final remainingBytes = data.length - offset;
      final actualChunkSize = remainingBytes > chunkSize
          ? chunkSize
          : remainingBytes;
      chunks.add(data.sublist(offset, offset + actualChunkSize));
      offset += actualChunkSize;
    }

    return chunks;
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
