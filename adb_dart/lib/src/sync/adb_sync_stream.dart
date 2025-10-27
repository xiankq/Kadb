/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../stream/adb_stream.dart';

/// ADB Sync协议常量
class SyncProtocol {
  static const int syncDataMax = 64 * 1024; // 64KB

  // Sync命令
  static const int cmdSend = 0x444e4553; // "SEND"
  static const int cmdRecv = 0x56434552; // "RECV"
  static const int cmdData = 0x41544144; // "DATA"
  static const int cmdDone = 0x454e4f44; // "DONE"
  static const int cmdOk = 0x594b4f4f; // "OKAY"
  static const int cmdFail = 0x4c494146; // "FAIL"
  static const int cmdList = 0x5453494c; // "LIST"
  static const int cmdDent = 0x544e4544; // "DENT"
  static const int cmdStat = 0x54415453; // "STAT"

  // 文件模式
  static const int modeMask = 0xFFF;
  static const int defaultFileMode = 0x644;
  static const int defaultDirectoryMode = 0x755;
}

/// ADB Sync流，用于文件传输
class AdbSyncStream {
  final AdbStream _stream;
  final StreamController<SyncResponse> _responseController =
      StreamController<SyncResponse>();

  AdbSyncStream(this._stream) {
    _startListening();
  }

  /// 开始监听sync响应
  void _startListening() {
    _stream.dataStream.listen(
      (data) {
        try {
          _processSyncData(data);
        } catch (e) {
          print('处理sync数据时出错：$e');
        }
      },
      onError: (error) {
        _responseController.addError(error);
      },
      onDone: () {
        _responseController.close();
      },
    );
  }

  /// 处理sync数据
  void _processSyncData(Uint8List data) {
    if (data.length < 8) return;

    final buffer = ByteData.sublistView(data);
    int offset = 0;

    while (offset + 8 <= data.length) {
      final command = buffer.getUint32(offset, Endian.little);
      final length = buffer.getUint32(offset + 4, Endian.little);
      offset += 8;

      if (offset + length > data.length) break;

      final payload = data.sublist(offset, offset + length);
      offset += length;

      _handleSyncCommand(command, payload);
    }
  }

  /// 处理sync命令
  void _handleSyncCommand(int command, Uint8List payload) {
    switch (command) {
      case SyncProtocol.cmdData:
        _responseController.add(SyncDataResponse(payload));
        break;
      case SyncProtocol.cmdDone:
        _responseController.add(SyncDoneResponse());
        break;
      case SyncProtocol.cmdOk:
        _responseController.add(SyncOkResponse());
        break;
      case SyncProtocol.cmdFail:
        final error = String.fromCharCodes(payload);
        _responseController.add(SyncFailResponse(error));
        break;
      case SyncProtocol.cmdDent:
        _handleDent(payload);
        break;
      case SyncProtocol.cmdStat:
        _handleStat(payload);
        break;
      default:
        print('未知的sync命令：${command.toRadixString(16)}');
        break;
    }
  }

  /// 处理DENT响应（目录项）
  void _handleDent(Uint8List payload) {
    if (payload.length < 16) return;

    final buffer = ByteData.sublistView(payload);
    final mode = buffer.getUint32(0, Endian.little);
    final size = buffer.getUint32(4, Endian.little);
    final time = buffer.getUint32(8, Endian.little);
    final nameLength = buffer.getUint32(12, Endian.little);

    if (payload.length < 16 + nameLength) return;

    final name = String.fromCharCodes(payload.sublist(16, 16 + nameLength));
    _responseController.add(SyncDentResponse(mode, size, time, name));
  }

  /// 处理STAT响应（文件状态）
  void _handleStat(Uint8List payload) {
    if (payload.length < 12) return;

    final buffer = ByteData.sublistView(payload);
    final mode = buffer.getUint32(0, Endian.little);
    final size = buffer.getUint32(4, Endian.little);
    final time = buffer.getUint32(8, Endian.little);

    _responseController.add(SyncStatResponse(mode, size, time));
  }

  /// 发送文件
  Future<void> send(
    File file,
    String remotePath, [
    int? mode,
    int? lastModified,
  ]) async {
    final fileMode = mode ?? SyncProtocol.defaultFileMode;
    final lastMod = lastModified ?? file.lastModifiedSync();

    // 构建SEND命令
    final sendPath = "$remotePath,$fileMode";
    final sendData = _buildSyncCommand(SyncProtocol.cmdSend, sendPath);

    await _stream.write(sendData);

    // 读取文件并发送数据
    final fileStream = file.openRead();
    await for (final chunk in fileStream) {
      final data = _buildSyncCommand(SyncProtocol.cmdData, chunk);
      await _stream.write(data);
    }

    // 发送完成标记
    final doneData = _buildSyncCommand(SyncProtocol.cmdDone, lastMod);
    await _stream.write(doneData);

    // 等待响应
    final response = await _responseController.stream.first;
    if (response is SyncFailResponse) {
      throw Exception('文件发送失败：${response.error}');
    }
  }

  /// 接收文件
  Future<void> recv(String remotePath, File localFile) async {
    // 发送RECV命令
    final recvData = _buildSyncCommand(SyncProtocol.cmdRecv, remotePath);
    await _stream.write(recvData);

    // 创建文件写入器
    final sink = localFile.openWrite();

    try {
      await for (final response in _responseController.stream) {
        if (response is SyncDataResponse) {
          sink.add(response.data);
        } else if (response is SyncDoneResponse) {
          break;
        } else if (response is SyncFailResponse) {
          throw Exception('文件接收失败：${response.error}');
        }
      }
    } finally {
      await sink.close();
    }
  }

  /// 构建sync命令
  List<int> _buildSyncCommand(int command, dynamic data) {
    final builder = _SyncDataBuilder();
    builder.addUint32(command);

    if (data is String) {
      final bytes = data.codeUnits;
      builder.addUint32(bytes.length);
      builder.addBytes(bytes);
    } else if (data is List<int>) {
      builder.addUint32(data.length);
      builder.addBytes(data);
    } else if (data is int) {
      builder.addUint32(4);
      builder.addUint32(data);
    }

    return builder.toBytes();
  }

  /// 关闭流
  Future<void> close() async {
    await _stream.close();
    await _responseController.close();
  }
}

/// Sync响应基类
abstract class SyncResponse {}

/// 数据响应
class SyncDataResponse implements SyncResponse {
  final Uint8List data;
  SyncDataResponse(this.data);
}

/// 完成响应
class SyncDoneResponse implements SyncResponse {}

/// 成功响应
class SyncOkResponse implements SyncResponse {}

/// 失败响应
class SyncFailResponse implements SyncResponse {
  final String error;
  SyncFailResponse(this.error);
}

/// 目录项响应
class SyncDentResponse implements SyncResponse {
  final int mode;
  final int size;
  final int time;
  final String name;
  SyncDentResponse(this.mode, this.size, this.time, this.name);
}

/// 文件状态响应
class SyncStatResponse implements SyncResponse {
  final int mode;
  final int size;
  final int time;
  SyncStatResponse(this.mode, this.size, this.time);
}

/// Sync数据构建器
class _SyncDataBuilder {
  final List<int> _bytes = [];

  void addUint32(int value) {
    _bytes.add(value & 0xFF);
    _bytes.add((value >> 8) & 0xFF);
    _bytes.add((value >> 16) & 0xFF);
    _bytes.add((value >> 24) & 0xFF);
  }

  void addBytes(List<int> bytes) {
    _bytes.addAll(bytes);
  }

  Uint8List toBytes() => Uint8List.fromList(_bytes);
}
