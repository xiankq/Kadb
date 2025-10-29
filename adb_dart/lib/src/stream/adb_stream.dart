/// ADB流管理
/// 处理ADB数据流的读写操作
library adb_stream;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import '../core/adb_protocol.dart';
import '../core/adb_writer.dart';
import '../queue/adb_message_queue.dart';
import '../exception/adb_exceptions.dart';

/// ADB流实现
class AdbStream {
  final AdbMessageQueue messageQueue;
  final AdbWriter writer;
  final int maxPayloadSize;
  final int localId;
  final int remoteId;

  bool _isClosed = false;
  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>();

  AdbStream({
    required this.messageQueue,
    required this.writer,
    required this.maxPayloadSize,
    required this.localId,
    required this.remoteId,
  }) {
    _startDataListening();
  }

  /// 获取数据流
  Stream<Uint8List> get dataStream => _dataController.stream;

  /// 是否已关闭
  bool get isClosed => _isClosed;

  /// 写入数据
  Future<void> write(Uint8List data) async {
    if (_isClosed) {
      throw AdbStreamClosed();
    }

    // 如果数据较小，直接发送
    if (data.length <= maxPayloadSize) {
      await writer.writeWrite(localId, remoteId, data);
      return;
    }

    // 大数据分块发送
    int offset = 0;
    while (offset < data.length) {
      final chunkSize = math.min(maxPayloadSize, data.length - offset);
      final chunk = data.sublist(offset, offset + chunkSize);
      await writer.writeWrite(localId, remoteId, chunk);
      offset += chunkSize;

      // 等待确认
      await _waitForOkay();
    }
  }

  /// 写入字符串
  Future<void> writeString(String text, [String encoding = 'utf-8']) async {
    final data = Uint8List.fromList(text.codeUnits);
    await write(data);
  }

  /// 读取数据
  Future<Uint8List> read() async {
    if (_isClosed) {
      throw AdbStreamClosed();
    }

    final buffer = BytesBuilder();
    bool dataReceived = false;
    final completer = Completer<Uint8List>();

    // 创建临时监听器收集数据
    StreamSubscription<Uint8List>? subscription;

    subscription = dataStream.listen(
      (data) {
        buffer.add(data);
        dataReceived = true;
      },
      onError: (error) {
        if (!_isClosed && !completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          if (buffer.length == 0) {
            completer.completeError(AdbStreamException('No data received'));
          } else {
            completer.complete(buffer.toBytes());
          }
        }
      },
    );

    try {
      // 等待数据到达或超时
      final result = await completer.future.timeout(
        Duration(seconds: 5),
        onTimeout: () {
          if (!dataReceived) {
            throw TimeoutException('等待数据超时');
          }
          return buffer.toBytes();
        },
      );

      return result;
    } finally {
      await subscription.cancel();
    }
  }

  /// 读取字符串
  Future<String> readString([String encoding = 'utf-8']) async {
    final data = await read();
    return String.fromCharCodes(data);
  }

  /// 读取指定长度的数据
  Future<Uint8List> readExact(int length) async {
    final buffer = BytesBuilder();
    int totalRead = 0;

    // 使用单个监听器读取指定长度的数据
    final subscription = dataStream.listen(
      (data) {
        if (totalRead < length) {
          final remaining = length - totalRead;
          final toAdd = data.length <= remaining ? data : data.sublist(0, remaining);
          buffer.add(toAdd);
          totalRead += toAdd.length;
        }
      },
      onError: (error) {
        if (!_isClosed) {
          throw error;
        }
      },
    );

    try {
      // 等待直到读取到足够的数据或超时
      final startTime = DateTime.now();
      const timeout = Duration(seconds: 30);

      while (totalRead < length) {
        if (DateTime.now().difference(startTime) > timeout) {
          throw AdbStreamException('Timeout waiting for data');
        }

        await Future.delayed(Duration(milliseconds: 10));

        if (_isClosed) {
          throw AdbStreamClosed();
        }
      }

      await subscription.cancel();

      final result = buffer.toBytes();
      if (result.length < length) {
        throw AdbStreamException(
            'Insufficient data: expected $length, got ${result.length}');
      }

      return result.sublist(0, length);
    } catch (e) {
      await subscription.cancel();
      if (e is AdbStreamException || e is AdbStreamClosed) {
        rethrow;
      }
      throw AdbStreamException('Failed to read exact data: $e');
    }
  }

  /// 读取指定长度的数据到预分配缓冲区
  Future<void> readExactBuffer(Uint8List buffer, int length) async {
    if (buffer.length < length) {
      throw ArgumentError('Buffer too small: ${buffer.length} < $length');
    }

    final data = await readExact(length);
    buffer.setAll(0, data);
  }

  /// 读取直到遇到结束符
  Future<Uint8List> readUntil(int endByte) async {
    final buffer = BytesBuilder();
    bool foundEndByte = false;

    // 使用单个监听器读取直到遇到结束符
    final subscription = dataStream.listen(
      (data) {
        if (!foundEndByte) {
          for (int i = 0; i < data.length; i++) {
            if (data[i] == endByte) {
              // 找到结束符，添加数据（包含结束符）
              if (i > 0) {
                buffer.add(data.sublist(0, i + 1));
              } else {
                buffer.addByte(endByte);
              }
              foundEndByte = true;
              break;
            }
          }

          // 如果没有找到结束符，添加整个数据块
          if (!foundEndByte) {
            buffer.add(data);
          }
        }
      },
      onError: (error) {
        if (!_isClosed) {
          throw error;
        }
      },
    );

    try {
      // 等待直到找到结束符或超时
      final startTime = DateTime.now();
      const timeout = Duration(seconds: 30);

      while (!foundEndByte) {
        if (DateTime.now().difference(startTime) > timeout) {
          throw AdbStreamException(
              'Timeout waiting for end byte $endByte');
        }

        await Future.delayed(Duration(milliseconds: 10));

        if (_isClosed) {
          throw AdbStreamClosed();
        }
      }

      await subscription.cancel();
      return buffer.toBytes();
    } catch (e) {
      await subscription.cancel();
      if (e is AdbStreamException || e is AdbStreamClosed) {
        rethrow;
      }
      throw AdbStreamException('Failed to read until end byte: $e');
    }
  }

  /// 关闭流
  Future<void> close() async {
    if (_isClosed) return;

    _isClosed = true;

    try {
      // 发送CLOSE消息
      await writer.writeClose(localId, remoteId);
    } catch (e) {
      // 忽略关闭时的错误
    }

    // 停止消息监听
    messageQueue.stopListening(localId);

    // 关闭数据流
    await _dataController.close();
  }

  /// 开始数据监听
  void _startDataListening() {
    messageQueue.startListening(localId);

    // 启动异步数据接收循环
    _receiveDataLoop();
  }

  /// 数据接收循环
  void _receiveDataLoop() async {
    while (!_isClosed) {
      try {
        // 等待数据消息，使用较短超时避免阻塞
        final message = await messageQueue.take(localId, AdbProtocol.cmdWrte)
            .timeout(Duration(milliseconds: 100));

        if (message.payload != null && !_dataController.isClosed) {
          _dataController.add(message.payload!);
        }
      } catch (e) {
        // 超时是正常的，继续循环
        if (e is TimeoutException) {
          continue;
        }

        // 其他错误需要处理
        if (!_isClosed && !_dataController.isClosed) {
          _dataController.addError(e);
        }
        break;
      }
    }
  }

  /// 等待OKAY确认
  Future<void> _waitForOkay() async {
    await messageQueue.take(localId, AdbProtocol.cmdOkay);
  }
}
