import 'dart:async';
import 'dart:typed_data';

import '../core/adb_protocol.dart';
import '../core/adb_writer.dart';
import '../queue/adb_message_queue.dart';
import '../utils/adb_stream_closed.dart';

/// ADB流数据源，提供数据读取功能
class AdbStreamSource {
  final AdbStream _stream;
  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>.broadcast();
  final Completer<void> _closeCompleter = Completer<void>();

  AdbStreamSource(this._stream) {
    _stream.dataStream.listen(
      (data) => _dataController.add(data),
      onDone: () {
        _dataController.close();
        _closeCompleter.complete();
      },
    );
  }

  Stream<List<int>> get stream => _dataController.stream.map((data) => data);

  Future<int> readByte() async {
    final bytes = await readBytes(1);
    return bytes.isNotEmpty ? bytes[0] : -1;
  }

  Future<Uint8List> readBytes(int length) async {
    if (length <= 0) return Uint8List(0);

    final completer = Completer<Uint8List>();
    final buffer = BytesBuilder(copy: false);
    var bytesRead = 0;

    StreamSubscription<Uint8List>? subscription;

    subscription = _dataController.stream.listen(
      (data) {
        if (bytesRead + data.length >= length) {
          final needed = length - bytesRead;
          if (needed < data.length) {
            final view = Uint8List.view(
              data.buffer,
              data.offsetInBytes,
              needed,
            );
            buffer.add(view);
          } else {
            buffer.add(data);
          }
          bytesRead += needed;
          subscription?.cancel();
          completer.complete(buffer.toBytes());
        } else {
          buffer.add(data);
          bytesRead += data.length;
        }
      },
      onError: (error) {
        subscription?.cancel();
        if (!completer.isCompleted) completer.completeError(error);
      },
      onDone: () {
        subscription?.cancel();
        if (!completer.isCompleted) completer.complete(buffer.toBytes());
      },
    );

    return completer.future;
  }

  Future<List<int>> take(int count) async {
    final bytes = await readBytes(count);
    return bytes.toList();
  }

  Stream<S> transform<S>(StreamTransformer<List<int>, S> transformer) {
    return stream.transform(transformer);
  }

  Future<void> close() async {
    _dataController.close();
    await _closeCompleter.future;
  }
}

/// ADB流数据接收器，提供数据写入功能
class AdbStreamSink {
  final AdbStream _stream;

  AdbStreamSink(this._stream);

  Future<void> writeByte(int byte) async {
    await writeBytes([byte]);
  }

  Future<void> writeBytes(List<int> bytes) async {
    if (bytes.isEmpty) return;

    Uint8List data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    await _stream.write(data);
  }

  Future<void> add(List<int> data) async {
    await writeBytes(data);
  }

  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      await add(data);
    }
  }

  Future<void> flush() async {}

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

  AdbStreamSource get source => AdbStreamSource(this);
  AdbStreamSink get sink => AdbStreamSink(this);

  Future<void> waitForRemoteId() => _remoteIdCompleter.future;
  int get remoteId => _remoteId;

  Future<void> write(Uint8List data) async {
    if (_isClosed) throw StateError('流已关闭');
    if (data.isEmpty) return;

    try {
      if (data.length <= _chunkSize) {
        await _writeChunk(data);
      } else {
        for (int offset = 0; offset < data.length; offset += _chunkSize) {
          final end = (offset + _chunkSize < data.length)
              ? offset + _chunkSize
              : data.length;
          final chunk = Uint8List.view(
            data.buffer,
            data.offsetInBytes + offset,
            end - offset,
          );
          await _writeChunk(chunk);
        }
      }
    } catch (e) {
      throw StateError('写入数据失败: $e');
    }
  }

  Future<void> _writeChunk(Uint8List chunk) async {
    await _adbWriter.writeWrite(_localId, _remoteId, chunk, 0, chunk.length);
  }

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
          final payloadView = Uint8List.view(
            Uint8List.fromList(message.payload).buffer,
            0,
            message.payload.length,
          );
          _dataController.add(payloadView);
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

  bool get isActive => !_isClosed && _isReading;
}
