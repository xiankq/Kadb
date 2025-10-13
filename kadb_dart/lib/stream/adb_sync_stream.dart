import 'dart:async';
import 'package:kadb_dart/stream/adb_stream.dart';
import 'package:kadb_dart/core/adb_connection.dart';

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

  static const Set<String> syncIds = {list, recv, send, stat, data, done, okay, quit, fail};
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
  Future<void> send(Stream<List<int>> source, String remotePath, int mode, int lastModifiedMs) async {
    final remote = "$remotePath,$mode";
    final length = remote.length;
    await _writePacket(AdbSyncStreamConstants.send, length);

    // 写入远程路径
    final remoteBytes = remote.codeUnits;
    await _stream.sink.add(remoteBytes);
    await _stream.sink.flush();

    _buffer.clear();

    // 发送文件数据
    await for (final chunk in source) {
      _buffer.addAll(chunk);
      await _writePacket(AdbSyncStreamConstants.data, chunk.length);
      await _stream.sink.writeBytes(chunk);
    }

    // 发送完成标记
    final lastModifiedSec = (lastModifiedMs / 1000).round();
    await _writePacket(AdbSyncStreamConstants.done, lastModifiedSec);
    await _stream.sink.flush();

    // 读取响应
    final packet = await _readPacket();
    switch (packet.id) {
      case AdbSyncStreamConstants.okay:
        return;
      case AdbSyncStreamConstants.fail:
        final messageBytes = await _stream.source.take(packet.arg);
        final message = String.fromCharCodes(messageBytes);
        throw Exception("同步失败: $message");
      default:
        throw Exception("意外的同步数据包ID: ${packet.id}");
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
      (arg >> 24) & 0xFF
    ];
    await _stream.sink.writeBytes(argBytes);
    await _stream.sink.flush();
  }

  /// 读取数据包
  Future<SyncPacket> _readPacket() async {
    final idBytes = await _stream.source.take(4);
    final id = String.fromCharCodes(idBytes);
    
    final argBytes = await _stream.source.take(4);
    final arg = argBytes[0] | (argBytes[1] << 8) | (argBytes[2] << 16) | (argBytes[3] << 24);
    
    return SyncPacket(id, arg);
  }

  /// 关闭同步流
  Future<void> close() async {
    await _writePacket(AdbSyncStreamConstants.quit, 0);
    await _stream.close();
  }
}