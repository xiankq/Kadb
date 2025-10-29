/// 文件同步协议实现
/// 实现ADB的SYNC协议用于文件传输
library sync_stream;

import 'dart:io';
import 'dart:typed_data';
import '../stream/adb_stream.dart';
import '../exception/adb_exceptions.dart';

/// 文件信息
class FileInfo {
  final int mode;
  final int size;
  final DateTime lastModified;

  FileInfo({
    required this.mode,
    required this.size,
    required this.lastModified,
  });

  @override
  String toString() => 'FileInfo(mode: 0${mode.toRadixString(8)}, size: $size, lastModified: $lastModified)';
}

/// 目录条目
class DirectoryEntry {
  final String name;
  final int mode;
  final int size;
  final DateTime lastModified;

  DirectoryEntry({
    required this.name,
    required this.mode,
    required this.size,
    required this.lastModified,
  });

  bool get isDirectory => (mode & 0x4000) != 0;
  bool get isFile => (mode & 0x8000) != 0;

  @override
  String toString() => 'DirectoryEntry(name: $name, mode: 0${mode.toRadixString(8)}, size: $size, lastModified: $lastModified)';
}

/// 文件同步协议常量
class SyncProtocol {
  /// LIST - 列出目录内容
  static const String list = 'LIST';

  /// RECV - 接收文件
  static const String recv = 'RECV';

  /// SEND - 发送文件
  static const String send = 'SEND';

  /// STAT - 获取文件状态
  static const String stat = 'STAT';

  /// DATA - 数据块
  static const String data = 'DATA';

  /// DONE - 传输完成
  static const String done = 'DONE';

  /// OKAY - 确认
  static const String okay = 'OKAY';

  /// QUIT - 退出
  static const String quit = 'QUIT';

  /// FAIL - 失败
  static const String fail = 'FAIL';

  /// DENT - 目录条目
  static const String dent = 'DENT';

  /// 所有有效的SYNC命令ID
  static const Set<String> validIds = {
    list, recv, send, stat, data, done, okay, quit, fail, dent
  };
}

/// 文件同步流
class AdbSyncStream {
  final AdbStream _stream;

  AdbSyncStream(this._stream);

  /// 发送文件到设备
  Future<void> send(File localFile, String remotePath, {
    int mode = 0x1A4, // 0o644 in hex
    DateTime? lastModified,
  }) async {
    if (!localFile.existsSync()) {
      throw AdbFileException('本地文件不存在: ${localFile.path}');
    }

    final lastModifiedMs = (lastModified ?? localFile.lastModifiedSync()).millisecondsSinceEpoch;

    // 发送SEND命令和文件信息
    final fileInfo = '$remotePath,$mode';
    await _writePacket(SyncProtocol.send, fileInfo.length);
    await _writeString(fileInfo);

    // 打开文件并分块发送
    final fileStream = localFile.openRead();
    await for (final chunk in fileStream) {
      final chunkData = Uint8List.fromList(chunk);
      await _writePacket(SyncProtocol.data, chunkData.length);
      await _writeBytes(chunkData);
    }

    // 发送DONE命令和最后修改时间
    await _writePacket(SyncProtocol.done, (lastModifiedMs ~/ 1000).toInt());

    // 等待设备响应
    final response = await _readPacket();
    if (response.id != SyncProtocol.okay) {
      if (response.id == SyncProtocol.fail) {
        final errorMessage = await _readString(response.length);
        throw AdbFileException('文件发送失败: $errorMessage');
      } else {
        throw AdbFileException('意外的响应: ${response.id}');
      }
    }
  }

  /// 从设备接收文件
  Future<void> recv(String remotePath, File localFile) async {
    // 确保父目录存在
    localFile.parent.createSync(recursive: true);

    // 发送RECV命令和远程路径
    await _writePacket(SyncProtocol.recv, remotePath.length);
    await _writeString(remotePath);

    // 打开本地文件用于写入
    final sink = localFile.openWrite();

    try {
      while (true) {
        final packet = await _readPacket();

        switch (packet.id) {
          case SyncProtocol.data:
            // 读取数据块
            final chunk = await _readBytes(packet.length);
            sink.add(chunk);
            break;

          case SyncProtocol.done:
            // 传输完成
            return;

          case SyncProtocol.fail:
            // 传输失败
            final errorMessage = await _readString(packet.length);
            throw AdbFileException('文件接收失败: $errorMessage');

          default:
            throw AdbFileException('意外的数据包类型: ${packet.id}');
        }
      }
    } finally {
      await sink.close();
    }
  }

  /// 获取文件状态
  Future<Map<String, dynamic>> stat(String remotePath) async {
    // 发送STAT命令
    await _writePacket(SyncProtocol.stat, remotePath.length);
    await _writeString(remotePath);

    // 读取响应
    final response = await _readPacket();

    if (response.id == SyncProtocol.fail) {
      final errorMessage = await _readString(response.length);
      throw AdbFileException('无法获取文件状态: $errorMessage');
    }

    if (response.id != SyncProtocol.stat) {
      throw AdbFileException('意外的响应类型: ${response.id}');
    }

    // 读取文件状态信息（12字节）
    final statData = await _readBytes(12);
    final buffer = ByteData.view(statData.buffer);

    return {
      'mode': buffer.getUint32(0, Endian.little),
      'size': buffer.getUint32(4, Endian.little),
      'time': buffer.getUint32(8, Endian.little),
    };
  }

  /// 列出目录内容
  Future<List<DirectoryEntry>> list(String remotePath) async {
    final result = <DirectoryEntry>[];

    // 发送LIST命令
    await _writePacket(SyncProtocol.list, remotePath.length);
    await _writeString(remotePath);

    while (true) {
      final packet = await _readPacket();

      switch (packet.id) {
        case SyncProtocol.dent:
          // 读取目录条目
          final dentData = await _readBytes(packet.length);
          final entry = _parseDirectoryEntry(dentData);
          result.add(entry);
          break;

        case SyncProtocol.done:
          // 列表完成
          return result;

        case SyncProtocol.fail:
          // 列表失败
          final errorMessage = await _readString(packet.length);
          throw AdbFileException('无法列出目录: $errorMessage');

        default:
          throw AdbFileException('意外的响应类型: ${packet.id}');
      }
    }
  }

  /// 关闭流
  Future<void> close() async {
    try {
      await _writePacket(SyncProtocol.quit, 0);
    } finally {
      await _stream.close();
    }
  }

  /// 写入数据包
  Future<void> _writePacket(String id, int length) async {
    if (!SyncProtocol.validIds.contains(id)) {
      throw AdbFileException('无效的SYNC命令: $id');
    }

    final packet = Uint8List(8);
    final buffer = ByteData.view(packet.buffer);

    // 命令ID (4字节)
    final idBytes = Uint8List.fromList(id.codeUnits);
    packet.setAll(0, idBytes);

    // 长度 (4字节，小端序)
    buffer.setUint32(4, length, Endian.little);

    await _stream.write(packet);
  }

  /// 写入字符串
  Future<void> _writeString(String text) async {
    final bytes = Uint8List.fromList(text.codeUnits);
    await _stream.write(bytes);
  }

  /// 写入字节数据
  Future<void> _writeBytes(Uint8List data) async {
    await _stream.write(data);
  }

  /// 读取数据包
  Future<_SyncPacket> _readPacket() async {
    final packetData = await _stream.readExact(8);
    final packet = Uint8List(8);
    packet.setAll(0, packetData);

    final buffer = ByteData.view(packet.buffer);
    final id = String.fromCharCodes(packet.sublist(0, 4));
    final length = buffer.getUint32(4, Endian.little);

    return _SyncPacket(id, length);
  }

  /// 读取字符串
  Future<String> _readString(int length) async {
    final data = await _stream.readExact(length);
    return String.fromCharCodes(data);
  }

  /// 读取字节数据
  Future<Uint8List> _readBytes(int length) async {
    return await _stream.readExact(length);
  }

  /// 解析目录条目
  DirectoryEntry _parseDirectoryEntry(Uint8List data) {
    if (data.length < 16) {
      throw AdbFileException('无效的目录条目数据');
    }

    final buffer = ByteData.view(data.buffer);
    final mode = buffer.getUint32(0, Endian.little);
    final size = buffer.getUint32(4, Endian.little);
    final time = buffer.getUint32(8, Endian.little);
    final nameLength = buffer.getUint32(12, Endian.little);

    if (data.length < 16 + nameLength) {
      throw AdbFileException('目录条目数据长度不匹配');
    }

    final name = String.fromCharCodes(data.sublist(16, 16 + nameLength));

    return DirectoryEntry(
      name: name,
      mode: mode,
      size: size,
      lastModified: DateTime.fromMillisecondsSinceEpoch(time * 1000),
    );
  }
}

/// 同步数据包
class _SyncPacket {
  final String id;
  final int length;

  _SyncPacket(this.id, this.length);

  @override
  String toString() => '_SyncPacket(id: $id, length: $length)';
}