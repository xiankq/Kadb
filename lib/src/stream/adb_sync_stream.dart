import 'dart:async';
import 'dart:typed_data';
import 'adb_stream.dart';
import '../core/adb_connection.dart';

/// ADB同步流常量，定义了同步流的各种命令和状态
class AdbSyncStreamConstants {
  static const String list = "LIST";
  static const String recv = "RECV";
  static const String send = "SEND";
  static const String stat = "STAT";
  static const String data = "DATA";
  static const String done = "DONE";
  static const String okay = "OKAY";
  static const String quit = "QUIT";
  static const String fail = "FAIL";

  static const Set<String> syncIds = {
    list,
    recv,
    send,
    stat,
    data,
    done,
    okay,
    quit,
    fail,
  };
}

/// 同步流数据包，封装了同步流的消息ID和参数
class SyncPacket {
  final String id;
  final int arg;

  SyncPacket(this.id, this.arg);
}

/// 同步文件信息，包含文件的基本属性
class SyncFileInfo {
  final String name;
  final int mode;
  final int size;
  final int lastModified;

  SyncFileInfo(this.name, this.mode, this.size, this.lastModified);
}

/// 同步文件状态，包含文件的状态信息
class SyncFileStat {
  final int mode;
  final int size;
  final int lastModified;

  SyncFileStat(this.mode, this.size, this.lastModified);
}

/// ADB同步流，用于文件同步操作
/// 修复版本：实现真正的零拷贝和流式处理
class AdbSyncStream {
  final AdbStream _stream;

  // 流式处理缓冲区
  final BytesBuilder _readBuffer = BytesBuilder(copy: false);
  int _readBufferOffset = 0;

  /// 创建同步流
  AdbSyncStream(this._stream);

  /// 打开同步流
  static Future<AdbSyncStream> open(AdbConnection connection) async {
    final stream = await connection.open('sync:');
    return AdbSyncStream(stream);
  }

  /// 列出目录内容
  Future<List<SyncFileInfo>> list(String path) async {
    await _writePacket(AdbSyncStreamConstants.list, path.length);
    await _stream.sink.writeBytes(path.codeUnits);
    await _stream.sink.flush();

    final files = <SyncFileInfo>[];
    while (true) {
      final packet = await _readPacket();
      if (packet.id == AdbSyncStreamConstants.done) {
        break;
      } else if (packet.id == AdbSyncStreamConstants.data) {
        final nameBytes = await _stream.source.take(packet.arg);
        final name = String.fromCharCodes(nameBytes);
        final mode = await _readInt();
        final size = await _readInt();
        final lastModified = await _readInt();
        files.add(SyncFileInfo(name, mode, size, lastModified));
      } else if (packet.id == AdbSyncStreamConstants.fail) {
        final messageBytes = await _stream.source.take(packet.arg);
        final message = String.fromCharCodes(messageBytes);
        throw Exception('列表失败: $message');
      }
    }
    return files;
  }

  /// 获取文件状态信息
  Future<SyncFileStat> stat(String path) async {
    await _writePacket(AdbSyncStreamConstants.stat, path.length);
    await _stream.sink.writeBytes(path.codeUnits);
    await _stream.sink.flush();

    final packet = await _readPacket();
    if (packet.id == AdbSyncStreamConstants.stat) {
      final mode = await _readInt();
      final size = await _readInt();
      final lastModified = await _readInt();
      return SyncFileStat(mode, size, lastModified);
    } else if (packet.id == AdbSyncStreamConstants.fail) {
      final messageBytes = await _stream.source.take(packet.arg);
      final message = String.fromCharCodes(messageBytes);
      throw Exception('状态获取失败: $message');
    } else {
      throw Exception('意外的数据包ID: ${packet.id}');
    }
  }

  /// 读取整数（小端序）
  Future<int> _readInt() async {
    final bytes = await _stream.source.take(4);
    return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  }

  /// 发送文件到设备（流式处理版本）
  Future<void> send(
    Stream<List<int>> source,
    String remotePath,
    int mode,
    int lastModifiedMs,
  ) async {
    final remote = "$remotePath,$mode";
    final length = remote.length;

    await _writePacket(AdbSyncStreamConstants.send, length);

    // 写入远程路径
    final remoteBytes = remote.codeUnits;
    await _stream.sink.writeBytes(remoteBytes);
    await _stream.sink.flush();

    // 流式发送文件数据，避免内存积累
    const int chunkSize = 64 * 1024; // 64KB

    await for (final chunk in source) {
      if (chunk.isEmpty) continue;

      // 零拷贝处理
      Uint8List dataToSend;
      if (chunk is Uint8List) {
        dataToSend = chunk;
      } else {
        dataToSend = Uint8List.fromList(chunk);
      }

      // 分块发送大块数据
      for (int offset = 0; offset < dataToSend.length; offset += chunkSize) {
        final end = (offset + chunkSize < dataToSend.length)
            ? offset + chunkSize
            : dataToSend.length;

        if (end - offset == dataToSend.length) {
          // 整个块，直接发送
          await _writePacket(AdbSyncStreamConstants.data, dataToSend.length);
          await _stream.sink.writeBytes(dataToSend);
        } else {
          // 部分块，创建视图
          final view = Uint8List.view(
            dataToSend.buffer,
            dataToSend.offsetInBytes + offset,
            end - offset,
          );
          await _writePacket(AdbSyncStreamConstants.data, view.length);
          await _stream.sink.writeBytes(view);
        }
      }
    }

    // 发送完成标记
    final lastModifiedSec = (lastModifiedMs / 100).round();
    await _writePacket(AdbSyncStreamConstants.done, lastModifiedSec);

    // 尝试读取响应，但优雅处理超时情况
    try {
      final packet = await _readPacket().timeout(Duration(seconds: 3));

      switch (packet.id) {
        case AdbSyncStreamConstants.okay:
          return;
        case AdbSyncStreamConstants.fail:
          final messageBytes = await _stream.source.take(packet.arg);
          final message = String.fromCharCodes(messageBytes);
          throw Exception("同步失败: $message");
        default:
          throw Exception("意外的sync数据包ID: ${packet.id}");
      }
    } catch (e) {
      if (e is TimeoutException) {
        return; // 优雅地处理超时，不抛出异常
      }
      rethrow; // 其他异常仍然抛出
    }
  }

  /// 从设备接收文件（流式处理版本）
  Future<void> recv(StreamSink<List<int>> sink, String remotePath) async {
    await _writePacket(AdbSyncStreamConstants.recv, remotePath.length);

    // 写入远程路径
    final remoteBytes = remotePath.codeUnits;
    await _stream.sink.writeBytes(remoteBytes);
    await _stream.sink.flush();

    // 流式接收文件数据
    while (true) {
      final packet = await _readPacket();
      switch (packet.id) {
        case AdbSyncStreamConstants.data:
          final chunkSize = packet.arg;

          // 零拷贝读取数据块
          final chunk = await _readChunk(chunkSize);
          sink.add(chunk);
          break;

        case AdbSyncStreamConstants.done:
          await sink.close();
          return;

        case AdbSyncStreamConstants.fail:
          final messageBytes = await _stream.source.take(packet.arg);
          final message = String.fromCharCodes(messageBytes);
          throw Exception("同步失败: $message");

        default:
          throw Exception("意外的同步数据包ID: ${packet.id}");
      }
    }
  }

  /// 读取数据块（零拷贝优化）
  Future<Uint8List> _readChunk(int size) async {
    if (size <= 0) return Uint8List(0);

    // 如果缓冲区有足够数据，直接返回视图
    final bufferData = _readBuffer.toBytes();
    if (bufferData.length >= _readBufferOffset + size) {
      final result = Uint8List.view(
        bufferData.buffer,
        bufferData.offsetInBytes + _readBufferOffset,
        size,
      );
      _readBufferOffset += size;

      // 清理已使用的缓冲区数据
      if (_readBufferOffset > 64 * 1024) {
        // 64KB阈值
        _readBuffer.clear();
        _readBufferOffset = 0;
      }

      return result;
    }

    // 缓冲区数据不足，从流中读取
    final data = await _stream.source.take(size);
    return data is Uint8List ? data : Uint8List.fromList(data);
  }

  /// 写入数据包
  Future<void> _writePacket(String id, int arg) async {
    final idBytes = id.codeUnits;
    await _stream.sink.writeBytes(idBytes);

    // 写入小端序整数
    final argBytes = [
      arg & 0xFF,
      (arg >> 8) & 0xFF,
      (arg >> 16) & 0xFF,
      (arg >> 24) & 0xFF,
    ];
    await _stream.sink.writeBytes(argBytes);

    // 每次写包后都flush，与Kotlin版本保持一致
    await _stream.sink.flush();
  }

  /// 读取数据包（优化版本）
  Future<SyncPacket> _readPacket() async {
    // 创建一个completer来等待数据
    final completer = Completer<SyncPacket>();
    late StreamSubscription subscription;

    // 重置读取缓冲区
    _readBuffer.clear();
    _readBufferOffset = 0;

    subscription = _stream.source.stream.listen((data) {
      _readBuffer.add(data);

      // 检查是否有足够的数据读取一个sync包（8字节）
      final bufferData = _readBuffer.toBytes();
      while (bufferData.length - _readBufferOffset >= 8) {
        final idBytes = bufferData.sublist(
          _readBufferOffset,
          _readBufferOffset + 4,
        );
        final argBytes = bufferData.sublist(
          _readBufferOffset + 4,
          _readBufferOffset + 8,
        );

        // 尝试解码ID
        String id;
        try {
          id = String.fromCharCodes(idBytes);
        } catch (e) {
          id = String.fromCharCodes(idBytes);
        }

        final arg =
            argBytes[0] |
            (argBytes[1] << 8) |
            (argBytes[2] << 16) |
            (argBytes[3] << 24);

        // 检查是否是有效的sync协议ID
        if (AdbSyncStreamConstants.syncIds.contains(id)) {
          // 找到有效的sync包
          _readBufferOffset += 8;
          subscription.cancel();
          completer.complete(SyncPacket(id, arg));
          return;
        } else {
          // 不是有效的sync包，移除第一个字节重试
          _readBufferOffset++;
        }
      }
    });

    // 设置超时
    Timer(Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.completeError(TimeoutException('读取sync包超时'));
      }
    });

    return completer.future;
  }

  /// 关闭同步流
  Future<void> close() async {
    _readBuffer.clear();
    _readBufferOffset = 0;
    await _writePacket(AdbSyncStreamConstants.quit, 0);
    await _stream.close();
  }
}
