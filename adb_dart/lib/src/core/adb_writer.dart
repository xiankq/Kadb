/// ADB消息写入器
/// 向传输通道写入ADB消息
library adb_writer;

import 'dart:io';
import 'dart:typed_data';
import 'adb_message.dart' hide adbMessageHeaderSize, adbVersion, adbMaxPayload, adbMaxPayloadLegacy;
import 'adb_protocol.dart';
import '../exception/adb_exceptions.dart';

/// ADB消息写入器
class AdbWriter {
  final Socket _socket;

  AdbWriter(this._socket);

  /// 写入消息
  Future<void> writeMessage(AdbMessage message) async {
    try {
      // 发送消息头部
      final header = message.serializeHeader();
      _socket.add(header);

      // 发送数据载荷（如果有）
      if (message.payload != null && message.payload!.isNotEmpty) {
        _socket.add(message.payload!);
      }

      // 刷新数据
      await _socket.flush();
    } catch (e) {
      throw AdbConnectionException('Failed to write message: $e');
    }
  }

  /// 写入CONNECT消息
  Future<void> writeConnect() async {
    final message = AdbMessage.connect(
      adbVersion,
      adbMaxPayload,
      'host::${getDefaultDeviceName()}',
    );
    await writeMessage(message);
  }

  /// 写入STLS消息
  Future<void> writeStls(int version) async {
    final message = AdbMessage.stls(version);
    await writeMessage(message);
  }

  /// 写入AUTH消息
  Future<void> writeAuth(int type, Uint8List data) async {
    final message = AdbMessage.auth(type, data);
    await writeMessage(message);
  }

  /// 写入OPEN消息
  Future<void> writeOpen(int localId, String destination) async {
    final message = AdbMessage.open(localId, destination);
    await writeMessage(message);
  }

  /// 写入OKAY消息
  Future<void> writeOkay(int localId, int remoteId) async {
    final message = AdbMessage.okay(localId, remoteId);
    await writeMessage(message);
  }

  /// 写入CLOSE消息
  Future<void> writeClose(int localId, int remoteId) async {
    final message = AdbMessage.close(localId, remoteId);
    await writeMessage(message);
  }

  /// 写入WRITE消息
  Future<void> writeWrite(int localId, int remoteId, Uint8List data) async {
    final message = AdbMessage.write(localId, remoteId, data);
    await writeMessage(message);
  }

  /// 写入WRITE消息（带偏移量和长度）
  Future<void> writeWriteData(int localId, int remoteId, Uint8List data, int offset, int length) async {
    if (offset == 0 && length == data.length) {
      await writeWrite(localId, remoteId, data);
    } else {
      final subData = data.sublist(offset, offset + length);
      await writeWrite(localId, remoteId, subData);
    }
  }

  /// 关闭写入器
  void close() {
    // Socket关闭由外部管理
  }

  /// 获取默认设备名称
  static String getDefaultDeviceName() {
    // TODO: 实现平台相关的设备名称获取
    return 'adb_dart';
  }
}