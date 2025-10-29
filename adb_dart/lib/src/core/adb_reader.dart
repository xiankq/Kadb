/// ADB消息读取器
///
/// 负责从底层传输通道读取ADB消息
/// 支持同步和异步读取，以及超时控制
library;

import 'dart:async';
import 'dart:typed_data';
import 'adb_protocol.dart';
import 'adb_message.dart';

/// ADB消息读取器接口
abstract class AdbReader {
  /// 读取下一条ADB消息
  Future<AdbMessage> readMessage();

  /// 关闭读取器
  Future<void> close();
}

/// 标准ADB消息读取器实现
class StandardAdbReader implements AdbReader {
  final Stream<Uint8List> _stream;
  final StreamController<Uint8List> _bufferController;
  final Completer<void> _closeCompleter;
  Uint8List _buffer = Uint8List(0);
  bool _isClosed = false;

  StandardAdbReader(this._stream)
      : _bufferController = StreamController<Uint8List>(),
        _closeCompleter = Completer<void>() {
    _setupStreamListening();
  }

  void _setupStreamListening() {
    _stream.listen(
      (data) {
        _bufferController.add(data);
      },
      onError: (error) {
        _bufferController.addError(error);
      },
      onDone: () {
        _bufferController.close();
        if (!_closeCompleter.isCompleted) {
          _closeCompleter.complete();
        }
      },
    );

    _bufferController.stream.listen((data) {
      _buffer = Uint8List.fromList([..._buffer, ...data]);
    });
  }

  @override
  Future<AdbMessage> readMessage() async {
    if (_isClosed) {
      throw StateError('读取器已关闭');
    }

    // 等待足够的数据到达
    while (_buffer.length < AdbProtocol.adbHeaderLength) {
      if (_bufferController.isClosed) {
        throw StateError('流已关闭，无法读取完整消息');
      }

      // 等待新数据到达
      await Future.delayed(Duration(milliseconds: 1));
    }

    // 解析消息头部
    final headerData = _buffer.sublist(0, AdbProtocol.adbHeaderLength);
    AdbMessage message;

    try {
      message = AdbMessage.fromBytes(headerData);
    } catch (e) {
      throw StateError('解析消息头部失败: $e');
    }

    // 如果有载荷数据，等待足够的数据到达
    if (message.payloadLength > 0) {
      final totalLength = AdbProtocol.adbHeaderLength + message.payloadLength;

      while (_buffer.length < totalLength) {
        if (_bufferController.isClosed) {
          throw StateError('流已关闭，无法读取完整载荷数据');
        }

        // 等待新数据到达
        await Future.delayed(Duration(milliseconds: 1));
      }

      // 重新解析完整消息（包含载荷）
      final fullData = _buffer.sublist(0, totalLength);
      try {
        message = AdbMessage.fromBytes(fullData);
      } catch (e) {
        throw StateError('解析完整消息失败: $e');
      }

      // 从缓冲区中移除已读取的数据
      _buffer = _buffer.sublist(totalLength);
    } else {
      // 没有载荷数据，只移除头部
      _buffer = _buffer.sublist(AdbProtocol.adbHeaderLength);
    }

    return message;
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;

    _isClosed = true;
    await _bufferController.close();

    // 等待流完全关闭
    if (!_closeCompleter.isCompleted) {
      await _closeCompleter.future;
    }
  }
}

/// 带超时的ADB消息读取器包装器
class TimeoutAdbReader implements AdbReader {
  final AdbReader _reader;
  final Duration _timeout;

  TimeoutAdbReader(this._reader, this._timeout);

  @override
  Future<AdbMessage> readMessage() async {
    try {
      return await _reader.readMessage().timeout(_timeout);
    } on TimeoutException {
      throw StateError('读取消息超时（超时时间: $_timeout）');
    }
  }

  @override
  Future<void> close() async {
    return _reader.close();
  }
}
