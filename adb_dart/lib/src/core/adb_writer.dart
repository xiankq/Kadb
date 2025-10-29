/// ADB消息写入器
///
/// 负责将ADB消息写入底层传输通道
/// 支持各种ADB命令的便捷写入方法
library;

import 'dart:typed_data';
import 'adb_protocol.dart';
import 'adb_message.dart';

/// ADB消息写入器接口
abstract class AdbWriter {
  /// 写入连接消息（CNXN）
  Future<void> writeConnect();

  /// 写入认证消息（AUTH）
  Future<void> writeAuth(int authType, Uint8List authPayload);

  /// 写入STLS消息
  Future<void> writeStls(int version);

  /// 写入打开流消息（OPEN）
  Future<void> writeOpen(int localId, String destination);

  /// 写入写入数据消息（WRTE）
  Future<void> writeWrite(int localId, int remoteId, Uint8List payload,
      [int offset = 0, int? length]);

  /// 写入关闭流消息（CLSE）
  Future<void> writeClose(int localId, int remoteId);

  /// 写入确认消息（OKAY）
  Future<void> writeOkay(int localId, int remoteId);

  /// 写入原始消息
  Future<void> writeMessage(AdbMessage message);

  /// 关闭写入器
  Future<void> close();
}

/// 标准ADB消息写入器实现
class StandardAdbWriter implements AdbWriter {
  final Sink<Uint8List> _sink;
  bool _isClosed = false;

  StandardAdbWriter(this._sink);

  @override
  Future<void> writeConnect() async {
    final payload = Uint8List.fromList(AdbProtocol.connectPayload);
    final message = AdbMessage(
      command: AdbProtocol.aCnxn,
      arg0: AdbProtocol.connectVersion,
      arg1: AdbProtocol.connectMaxData,
      payloadLength: payload.length,
      checksum: AdbProtocol.calculateChecksum(payload),
      magic: AdbProtocol.aCnxn ^ 0xffffffff,
      payload: payload,
    );

    await writeMessage(message);
  }

  @override
  Future<void> writeAuth(int authType, Uint8List authPayload) async {
    final message = AdbMessage(
      command: AdbProtocol.aAuth,
      arg0: authType,
      arg1: 0,
      payloadLength: authPayload.length,
      checksum: AdbProtocol.calculateChecksum(authPayload),
      magic: AdbProtocol.aAuth ^ 0xffffffff,
      payload: authPayload,
    );

    await writeMessage(message);
  }

  @override
  Future<void> writeStls(int version) async {
    final message = AdbMessage(
      command: AdbProtocol.aStls,
      arg0: version,
      arg1: 0,
      payloadLength: 0,
      checksum: 0,
      magic: AdbProtocol.aStls ^ 0xffffffff,
      payload: null,
    );

    await writeMessage(message);
  }

  @override
  Future<void> writeOpen(int localId, String destination) async {
    // 添加null终止符
    final destinationBytes = Uint8List.fromList('$destination\x00'.codeUnits);
    final message = AdbMessage(
      command: AdbProtocol.aOpen,
      arg0: localId,
      arg1: 0,
      payloadLength: destinationBytes.length,
      checksum: AdbProtocol.calculateChecksum(destinationBytes),
      magic: AdbProtocol.aOpen ^ 0xffffffff,
      payload: destinationBytes,
    );

    await writeMessage(message);
  }

  @override
  Future<void> writeWrite(int localId, int remoteId, Uint8List payload,
      [int offset = 0, int? length]) async {
    final actualLength = length ?? (payload.length - offset);
    final actualPayload =
        Uint8List.sublistView(payload, offset, offset + actualLength);

    final message = AdbMessage(
      command: AdbProtocol.aWrte,
      arg0: localId,
      arg1: remoteId,
      payloadLength: actualLength,
      checksum: AdbProtocol.calculateChecksum(actualPayload),
      magic: AdbProtocol.aWrte ^ 0xffffffff,
      payload: actualPayload,
    );

    await writeMessage(message);
  }

  @override
  Future<void> writeClose(int localId, int remoteId) async {
    final message = AdbMessage(
      command: AdbProtocol.aClse,
      arg0: localId,
      arg1: remoteId,
      payloadLength: 0,
      checksum: 0,
      magic: AdbProtocol.aClse ^ 0xffffffff,
      payload: null,
    );

    await writeMessage(message);
  }

  @override
  Future<void> writeOkay(int localId, int remoteId) async {
    final message = AdbMessage(
      command: AdbProtocol.aOkay,
      arg0: localId,
      arg1: remoteId,
      payloadLength: 0,
      checksum: 0,
      magic: AdbProtocol.aOkay ^ 0xffffffff,
      payload: null,
    );

    await writeMessage(message);
  }

  @override
  Future<void> writeMessage(AdbMessage message) async {
    if (_isClosed) {
      throw StateError('写入器已关闭');
    }

    try {
      final bytes = message.toBytes();
      _sink.add(bytes);
      await _sink.flush();
    } catch (e) {
      throw StateError('写入消息失败: $e');
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;

    _isClosed = true;
    try {
      await _sink.close();
    } catch (e) {
      // 忽略关闭错误
    }
  }
}
