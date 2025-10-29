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
  final StreamController<Uint8List> _dataController = StreamController<Uint8List>();

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

    Uint8List? result;

    final subscription = dataStream.listen((data) {
      if (result == null) {
        result = data;
      } else {
        // 合并数据
        final newResult = Uint8List(result!.length + data.length);
        newResult.setAll(0, result!);
        newResult.setAll(result!.length, data);
        result = newResult;
      }
    });

    // 等待一段时间或直到流关闭
    await Future.any([
      Future.delayed(const Duration(milliseconds: 100)),
      Future(() async {
        await for (final _ in dataStream) {
          // 等待数据到达
        }
      }),
    ]);

    await subscription.cancel();

    if (result == null) {
      throw AdbStreamException('No data received');
    }

    return result!;
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

    await for (final data in dataStream) {
      buffer.add(data);
      totalRead += data.length;

      if (totalRead >= length) {
        break;
      }
    }

    final result = buffer.toBytes();
    if (result.length < length) {
      throw AdbStreamException('Insufficient data: expected $length, got ${result.length}');
    }

    return result.sublist(0, length);
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

    await for (final data in dataStream) {
      for (int i = 0; i < data.length; i++) {
        if (data[i] == endByte) {
          // 找到结束符，返回数据（包含结束符）
          if (i > 0) {
            buffer.add(data.sublist(0, i + 1));
          } else {
            buffer.addByte(endByte);
          }
          return buffer.toBytes();
        }
      }
      // 当前数据块中没有结束符，继续读取
      buffer.add(data);
    }

    throw AdbStreamException('Stream closed before end byte $endByte was found');
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

    // 设置消息监听器
    // 注意：这里需要修改AdbMessageQueue以支持监听器模式
    // 暂时通过轮询方式处理
    Timer.periodic(const Duration(milliseconds: 10), (timer) async {
      if (_isClosed) {
        timer.cancel();
        return;
      }

      try {
        final message = await messageQueue.take(localId, AdbProtocol.cmdWrte);
        if (message.payload != null) {
          _dataController.add(message.payload!);
        }
      } catch (e) {
        // 没有数据或发生错误
        if (e is! TimeoutException) {
          // 非超时错误，可能是流关闭
          if (!_dataController.isClosed) {
            _dataController.addError(e);
          }
          timer.cancel();
        }
      }
    });
  }

  /// 等待OKAY确认
  Future<void> _waitForOkay() async {
    await messageQueue.take(localId, AdbProtocol.cmdOkay);
  }
}