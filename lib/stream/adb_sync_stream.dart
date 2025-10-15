import 'dart:async';
import 'dart:convert';
import 'adb_stream.dart';
import '../core/adb_connection.dart';

/// ADB同步流常量
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

/// 同步流数据包
class SyncPacket {
  final String id;
  final int arg;

  SyncPacket(this.id, this.arg);
}

/// 同步文件信息
class SyncFileInfo {
  final String name;
  final int mode;
  final int size;
  final int lastModified;

  SyncFileInfo(this.name, this.mode, this.size, this.lastModified);
}

/// 同步文件状态
class SyncFileStat {
  final int mode;
  final int size;
  final int lastModified;

  SyncFileStat(this.mode, this.size, this.lastModified);
}

/// ADB同步流
/// 用于文件同步操作
class AdbSyncStream {
  final AdbStream _stream;
  final List<int> _buffer = [];

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

  /// 发送文件到设备
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

    _buffer.clear();

    // 发送文件数据（使用64KB分块，与Kotlin版本一致）
    const int chunkSize = 64 * 1024; // 64KB
    final allData = <int>[];

    // 收集所有数据
    await for (final chunk in source) {
      allData.addAll(chunk);
    }

    // 分块发送数据
    int chunkCount = 0;
    for (int i = 0; i < allData.length; i += chunkSize) {
      final end = (i + chunkSize < allData.length)
          ? i + chunkSize
          : allData.length;
      final chunk = allData.sublist(i, end);
      chunkCount++;

      await _writePacket(AdbSyncStreamConstants.data, chunk.length);
      await _stream.sink.writeBytes(chunk);
      // 注意：这里不flush，让数据积累后再一次性flush
    }

    // 发送完成标记
    final lastModifiedSec = (lastModifiedMs / 1000).round();

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

  /// 从设备接收文件
  Future<void> recv(StreamSink<List<int>> sink, String remotePath) async {
    await _writePacket(AdbSyncStreamConstants.recv, remotePath.length);

    // 写入远程路径
    final remoteBytes = remotePath.codeUnits;
    await _stream.sink.writeBytes(remoteBytes);
    await _stream.sink.flush();

    _buffer.clear();

    // 接收文件数据
    while (true) {
      final packet = await _readPacket();
      switch (packet.id) {
        case AdbSyncStreamConstants.data:
          final chunkSize = packet.arg;
          final chunk = await _stream.source.take(chunkSize);
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

  /// 读取数据包
  Future<SyncPacket> _readPacket() async {
    // 创建一个completer来等待数据
    final completer = Completer<SyncPacket>();
    late StreamSubscription subscription;
    var buffer = <int>[];

    subscription = _stream.source.stream.listen((data) {
      buffer.addAll(data);

      // 检查是否有足够的数据读取一个sync包（8字节）
      while (buffer.length >= 8) {
        final idBytes = buffer.sublist(0, 4);
        final argBytes = buffer.sublist(4, 8);

        // 尝试解码ID
        String id;
        try {
          id = utf8.decode(idBytes, allowMalformed: true);
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
          buffer.removeRange(0, 8); // 移除已处理的数据
          subscription.cancel();
          completer.complete(SyncPacket(id, arg));
          return;
        } else {
          // 不是有效的sync包，移除第一个字节重试
          buffer.removeAt(0);
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
    await _writePacket(AdbSyncStreamConstants.quit, 0);
    await _stream.close();
  }
}
