import 'dart:async';
import 'dart:typed_data';

import '../core/adb_protocol.dart';
import '../core/adb_writer.dart';
import '../queue/adb_message_queue.dart';
import '../exception/adb_stream_closed.dart';

/// ADB流数据源，提供流数据的基本操作
class AdbStreamSource {
  final AdbStream _stream;
  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>();
  final Completer<void> _closeCompleter = Completer<void>();

  AdbStreamSource(this._stream) {
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

  /// 获取数据流
  Stream<List<int>> get stream => _dataController.stream.map((data) => data);

  /// 读取一个字节
  Future<int> readByte() async {
    final bytes = await readBytes(1);
    return bytes.isNotEmpty ? bytes[0] : -1;
  }

  /// 读取指定长度的字节
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

  /// 从流中读取指定数量的字节
  Future<List<int>> take(int count) async {
    final bytes = await readBytes(count);
    return bytes.toList();
  }

  /// 转换流数据
  Stream<S> transform<S>(StreamTransformer<List<int>, S> transformer) {
    return stream.transform(transformer);
  }

  /// 关闭数据源
  Future<void> close() async {
    _dataController.close();
    await _closeCompleter.future;
  }
}

/// ADB流数据接收器，提供流数据的写入操作
class AdbStreamSink {
  final AdbStream _stream;

  AdbStreamSink(this._stream);

  /// 写入一个字节
  Future<void> writeByte(int byte) async {
    await writeBytes([byte]);
  }

  /// 写入字节数据
  Future<void> writeBytes(List<int> bytes) async {
    if (bytes.isEmpty) return;
    await _stream.write(Uint8List.fromList(bytes));
  }

  /// 向流中写入数据
  Future<void> add(List<int> data) async {
    await writeBytes(data);
  }

  /// 添加流数据
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      await add(data);
    }
  }

  /// 刷新缓冲区
  Future<void> flush() async {
    // ADB流写入是同步的，无需特殊刷新操作
  }

  /// 关闭接收器
  Future<void> close() async {
    await _stream.close();
  }
}

/// ADB流类，负责ADB协议的流管理和数据传输
class AdbStream {
  static const int _chunkSize = 128 * 1024;
  static const int _remoteIdAssignmentTimeoutSeconds = 5;

  final AdbMessageQueue _messageQueue;
  final AdbWriter _adbWriter;
  final int _localId;
  int _remoteId;
  final Completer<void> _remoteIdCompleter = Completer<void>();

  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>.broadcast();
  final StreamController<void> _closeController =
      StreamController<void>.broadcast();

  bool _isClosed = false;
  bool _isReading = false;

  AdbStream({
    required int localId,
    required int remoteId,
    required String destination,
    required AdbMessageQueue messageQueue,
    required AdbWriter writer,
    bool debug = false,
  }) : _localId = localId,
       _remoteId = remoteId,
       _messageQueue = messageQueue,
       _adbWriter = writer {
    _messageQueue.startListening(_localId);
    _startReading();
  }

  Stream<Uint8List> get dataStream => _dataController.stream;
  Stream<void> get closeStream => _closeController.stream;

  /// 获取数据源
  AdbStreamSource get source => AdbStreamSource(this);

  /// 获取数据接收器
  AdbStreamSink get sink => AdbStreamSink(this);

  Future<void> waitForRemoteId() => _remoteIdCompleter.future;
  int get remoteId => _remoteId;

  /// 写入数据到ADB流
  Future<void> write(Uint8List data) async {
    if (_isClosed) throw StateError('流已关闭');

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

  /// 关闭ADB流
  Future<void> close() async {
    if (_isClosed) return;

    _isClosed = true;
    _isReading = false;

    try {
      await _adbWriter.writeClose(_localId, _remoteId);
    } catch (e) {
      // 忽略关闭时的异常
    }

    try {
      _messageQueue.stopListening(_localId);
    } catch (e) {
      // 忽略关闭时的异常
    }

    await _dataController.close();
    await _closeController.close();
  }

  /// 开始读取ADB流数据
  void _startReading() {
    if (_isReading) return;
    _isReading = true;
    _readLoop().catchError((error) {
      if (!_isClosed) {
        _dataController.addError(error);
        close();
      }
    });
  }

  /// 读取ADB流数据循环
  Future<void> _readLoop() async {
    try {
      await _waitForRemoteIdAssignment();
    } catch (e) {
      await close();
      return;
    }

    while (!_isClosed) {
      try {
        final message = await _messageQueue.take(_localId, AdbProtocol.cmdWrte);

        if (message.payload.isNotEmpty) {
          final payloadUint8 = Uint8List.fromList(message.payload);
          _dataController.add(payloadUint8);
        }

        await _adbWriter.writeOkay(_localId, _remoteId);
      } catch (e) {
        if (!_isClosed) {
          if (e is AdbStreamClosed ||
              e.toString().contains('AdbStreamClosed') ||
              e.toString().contains('CLSE') ||
              e.toString().contains('消息队列已关闭')) {
            await close();
            break;
          }
        }
      }
    }

    _isReading = false;
  }

  /// 等待远程ID分配
  Future<void> _waitForRemoteIdAssignment() async {
    for (int attempts = 1; attempts <= 3 && !_isClosed; attempts++) {
      try {
        final okayMessage = await _messageQueue.takeWithTimeout(
          _localId,
          AdbProtocol.cmdOkay,
          timeout: Duration(seconds: _remoteIdAssignmentTimeoutSeconds),
        );
        _remoteId = okayMessage.arg0;

        if (!_remoteIdCompleter.isCompleted) {
          _remoteIdCompleter.complete();
        }
        return;
      } catch (e) {
        if (attempts >= 3 || _isClosed) {
          if (!_remoteIdCompleter.isCompleted) {
            _remoteIdCompleter.completeError(e);
          }
          rethrow;
        }
        await Future.delayed(Duration(seconds: 1));
      }
    }
  }

  /// 分割数据为块
  List<Uint8List> _splitData(Uint8List data) {
    if (data.length <= _chunkSize) return [data];

    final chunks = <Uint8List>[];
    for (int offset = 0; offset < data.length; offset += _chunkSize) {
      final end = offset + _chunkSize;
      final actualChunkSize = end > data.length
          ? data.length - offset
          : _chunkSize;
      chunks.add(data.sublist(offset, offset + actualChunkSize));
    }
    return chunks;
  }
}
