/// ADB基础流管理
///
/// 提供双向数据传输功能，支持OPEN/WRTE/OKAY/CLSE消息协议
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../core/adb_protocol.dart';
import '../core/adb_message.dart';
import '../core/adb_writer.dart';
import '../exception/adb_exceptions.dart';
import '../queue/adb_message_queue.dart';

/// ADB数据流
///
/// 表示一个双向的ADB数据流，用于在客户端和服务器之间传输数据
class AdbStream {
  final AdbMessageQueue _messageQueue;
  final AdbWriter _writer;
  final int _maxPayloadSize;
  final int _localId;
  final int _remoteId;

  bool _isClosed = false;
  bool _isInputShutdown = false;
  bool _isOutputShutdown = false;

  /// 输入数据队列
  final Queue<Uint8List> _inputQueue = Queue<Uint8List>();

  /// 输入流控制器
  final StreamController<Uint8List> _inputController =
      StreamController<Uint8List>();

  /// 输出流控制器
  final StreamController<Uint8List> _outputController =
      StreamController<Uint8List>();

  /// 消息监听订阅
  StreamSubscription<AdbMessage>? _messageSubscription;

  /// 构造函数
  AdbStream({
    required AdbMessageQueue messageQueue,
    required AdbWriter writer,
    required int maxPayloadSize,
    required int localId,
    required int remoteId,
  })  : _messageQueue = messageQueue,
        _writer = writer,
        _maxPayloadSize = maxPayloadSize,
        _localId = localId,
        _remoteId = remoteId {
    _setupMessageHandling();
    _setupOutputHandling();
  }

  /// 获取本地流ID
  int get localId => _localId;

  /// 获取远程流ID
  int get remoteId => _remoteId;

  /// 获取最大载荷大小
  int get maxPayloadSize => _maxPayloadSize;

  /// 检查流是否已关闭
  bool get isClosed => _isClosed;

  /// 检查输入是否已关闭
  bool get isInputShutdown => _isInputShutdown;

  /// 检查输出是否已关闭
  bool get isOutputShutdown => _isOutputShutdown;

  /// 输入数据流
  Stream<Uint8List> get inputStream => _inputController.stream;

  /// 输出数据接收器
  StreamSink<Uint8List> get outputSink => _outputController.sink;

  /// 设置消息处理
  void _setupMessageHandling() {
    // 启动消息队列监听
    _messageQueue.startListening(_localId);

    // 创建异步消息处理循环
    _messageSubscription = _createMessageStream().listen(
      (message) {
        _handleMessage(message);
      },
      onError: (error) {
        _handleError(error);
      },
      onDone: () {
        _handleStreamClosed();
      },
    );
  }

  /// 创建消息流
  Stream<AdbMessage> _createMessageStream() async* {
    while (!_isClosed) {
      try {
        // 从消息队列接收消息
        final message = await _messageQueue.take(_localId, AdbProtocol.aWrte);
        yield message;
      } catch (e) {
        if (!_isClosed) {
          yield* Stream.error(e);
        }
        break;
      }
    }
  }

  /// 设置输出处理
  void _setupOutputHandling() {
    _outputController.stream.listen(
      (data) {
        if (_isClosed || _isOutputShutdown) {
          throw AdbStreamException('流输出已关闭',
              localId: _localId, remoteId: _remoteId);
        }

        _writeData(data);
      },
      onError: (error) {
        _handleError(error);
      },
      onDone: () {
        shutdownOutput();
      },
    );
  }

  /// 处理接收到的消息
  void _handleMessage(AdbMessage message) {
    // 只处理与当前流相关的消息
    if (message.arg1 != _localId && message.arg0 != _localId) {
      return; // 忽略其他流的消息
    }

    switch (message.command) {
      case AdbProtocol.aOkay:
        // 确认消息，可以继续发送数据
        _handleOkay(message);
        break;

      case AdbProtocol.aWrte:
        // 数据写入消息
        _handleWrite(message);
        break;

      case AdbProtocol.aClse:
        // 关闭流消息
        _handleClose(message);
        break;

      default:
        // 忽略其他类型的消息
        break;
    }
  }

  /// 处理OKAY消息
  void _handleOkay(AdbMessage message) {
    // OKAY消息表示对端已准备好接收更多数据
    // 在实际实现中，这里可以用于流量控制
  }

  /// 处理WRTE消息
  void _handleWrite(AdbMessage message) {
    if (message.payload == null || message.payload!.isEmpty) {
      return;
    }

    // 将数据添加到输入队列
    _inputQueue.add(message.payload!);

    // 通知输入流有新数据
    if (!_inputController.isClosed) {
      _inputController.add(message.payload!);
    }

    // 发送确认消息
    _writer.writeOkay(_localId, _remoteId);
  }

  /// 处理CLSE消息
  void _handleClose(AdbMessage message) {
    close();
  }

  /// 处理错误
  void _handleError(Object error) {
    if (!_inputController.isClosed) {
      _inputController.addError(error);
    }
    if (!_outputController.isClosed) {
      _outputController.addError(error);
    }

    // 关闭流
    close();
  }

  /// 处理流关闭
  void _handleStreamClosed() {
    close();
  }

  /// 写入数据
  Future<void> _writeData(Uint8List data) async {
    if (_isClosed || _isOutputShutdown) {
      throw AdbStreamException('流输出已关闭',
          localId: _localId, remoteId: _remoteId);
    }

    try {
      // 如果数据太大，需要分块发送
      if (data.length > _maxPayloadSize) {
        for (int offset = 0; offset < data.length; offset += _maxPayloadSize) {
          final chunkSize = data.length - offset < _maxPayloadSize
              ? data.length - offset
              : _maxPayloadSize;
          final chunk = Uint8List.sublistView(data, offset, offset + chunkSize);
          await _writer.writeWrite(_localId, _remoteId, chunk);
        }
      } else {
        await _writer.writeWrite(_localId, _remoteId, data);
      }
    } catch (e) {
      throw AdbStreamException('写入数据失败',
          localId: _localId, remoteId: _remoteId, cause: e);
    }
  }

  /// 写入数据（公共接口）
  Future<void> write(Uint8List data) async {
    await _writeData(data);
  }

  /// 读取数据
  Future<Uint8List?> read() async {
    if (_isClosed || _isInputShutdown) {
      return null;
    }

    if (_inputQueue.isEmpty) {
      // 等待数据到达
      try {
        final data = await inputStream.first;
        return data;
      } catch (e) {
        if (_isClosed) {
          return null;
        }
        rethrow;
      }
    } else {
      return _inputQueue.removeFirst();
    }
  }

  /// 读取指定长度的数据
  Future<Uint8List> readFully(int length) async {
    if (_isClosed || _isInputShutdown) {
      throw AdbStreamException('流输入已关闭',
          localId: _localId, remoteId: _remoteId);
    }

    final buffer = BytesBuilder();
    int totalRead = 0;

    while (totalRead < length) {
      final data = await read();
      if (data == null) {
        throw AdbStreamException('连接关闭，无法读取完整数据',
            localId: _localId, remoteId: _remoteId);
      }

      buffer.add(data);
      totalRead += data.length;
    }

    return buffer.toBytes();
  }

  /// 关闭输入流
  Future<void> shutdownInput() async {
    if (_isInputShutdown) return;

    _isInputShutdown = true;

    if (!_inputController.isClosed) {
      await _inputController.close();
    }
  }

  /// 关闭输出流
  Future<void> shutdownOutput() async {
    if (_isOutputShutdown) return;

    _isOutputShutdown = true;

    if (!_outputController.isClosed) {
      await _outputController.close();
    }
  }

  /// 关闭流
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    try {
      // 发送关闭消息
      await _writer.writeClose(_localId, _remoteId);
    } catch (e) {
      // 忽略关闭错误
    }

    // 关闭控制器
    if (!_inputController.isClosed) {
      await _inputController.close();
    }
    if (!_outputController.isClosed) {
      await _outputController.close();
    }

    // 取消消息订阅
    await _messageSubscription?.cancel();

    // 停止消息队列监听
    _messageQueue.stopListening(_localId);
  }

  /// 获取待读取的数据量
  int get available {
    return _inputQueue.fold(0, (sum, data) => sum + data.length);
  }

  /// 检查是否有可用数据
  bool get hasAvailableData => _inputQueue.isNotEmpty;

  /// 清空输入缓冲区
  void clearInputBuffer() {
    _inputQueue.clear();
  }
}

/// ADB流读取器
///
/// 提供便捷的数据读取功能
class AdbStreamReader {
  final AdbStream _stream;
  final Queue<Uint8List> _buffer = Queue<Uint8List>();

  AdbStreamReader(this._stream);

  /// 读取一行数据（以换行符结束）
  Future<String?> readLine() async {
    final lineBuffer = StringBuffer();

    while (true) {
      if (_buffer.isEmpty) {
        final data = await _stream.read();
        if (data == null) {
          // 流已关闭
          final result = lineBuffer.toString();
          return result.isEmpty ? null : result;
        }
        _buffer.add(data);
      }

      final data = _buffer.removeFirst();
      final text = String.fromCharCodes(data);
      lineBuffer.write(text);

      final fullText = lineBuffer.toString();
      final newlineIndex = fullText.indexOf('\n');
      if (newlineIndex != -1) {
        final line = fullText.substring(0, newlineIndex);
        final remaining = fullText.substring(newlineIndex + 1);

        if (remaining.isNotEmpty) {
          _buffer.addFirst(Uint8List.fromList(remaining.codeUnits));
        }

        return line.trimRight(); // 移除末尾的\r（如果有）
      }
    }
  }

  /// 读取所有剩余数据
  Future<String> readAll() async {
    final buffer = StringBuffer();

    while (true) {
      final data = await _stream.read();
      if (data == null) break;

      buffer.write(String.fromCharCodes(data));
    }

    return buffer.toString();
  }

  /// 读取指定长度的数据
  Future<Uint8List> readBytes(int length) async {
    return await _stream.readFully(length);
  }

  /// 关闭读取器
  Future<void> close() async {
    await _stream.shutdownInput();
  }
}

/// ADB流写入器
///
/// 提供便捷的数据写入功能
class AdbStreamWriter {
  final AdbStream _stream;

  AdbStreamWriter(this._stream);

  /// 写入字符串
  Future<void> write(String text) async {
    await _stream.write(Uint8List.fromList(text.codeUnits));
  }

  /// 写入一行（自动添加换行符）
  Future<void> writeLine(String text) async {
    await write('$text\n');
  }

  /// 写入字节数据
  Future<void> writeBytes(Uint8List data) async {
    await _stream.write(data);
  }

  /// 刷新输出（ADB会自动在每次WRTE消息后确认）
  Future<void> flush() async {
    // ADB协议中，flush是隐式的，每次WRTE都会等待OKAY
  }

  /// 关闭写入器
  Future<void> close() async {
    await _stream.shutdownOutput();
  }
}
