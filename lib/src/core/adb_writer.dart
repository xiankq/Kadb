import 'dart:async';
import 'dart:convert';

import 'adb_message.dart';
import 'adb_protocol.dart';
import '../utils/logging.dart';

/// ADB消息写入器，负责向数据目标写入ADB协议消息
class AdbWriter {
  final Future<void> Function(List<int>) _writeBytes;
  final bool _debug;

  AdbWriter(this._writeBytes, {bool debug = false}) : _debug = debug;

  /// 写入连接消息
  Future<void> writeConnect({
    required int version,
    required int maxData,
    required String systemIdentityString,
  }) {
    final payload = utf8.encode(systemIdentityString);
    return write(
      AdbProtocol.cmdCnxn,
      version,
      maxData,
      payload,
      0,
      payload.length,
    );
  }

  /// 写入认证消息
  Future<void> writeAuth(int authType, List<int> authPayload) {
    return write(
      AdbProtocol.cmdAuth,
      authType,
      0,
      authPayload,
      0,
      authPayload.length,
    );
  }

  /// 写入STLS消息
  Future<void> writeStls(int version) {
    return write(AdbProtocol.cmdStls, version, 0, null, 0, 0);
  }

  /// 写入打开流消息
  Future<void> writeOpen(int localId, String destination) {
    final destinationBytes = utf8.encode(destination);
    final payload = List<int>.from(destinationBytes)..add(0);
    return write(AdbProtocol.cmdOpen, localId, 0, payload, 0, payload.length);
  }

  /// 写入数据消息
  Future<void> writeWrite(
    int localId,
    int remoteId,
    List<int> payload,
    int offset,
    int length,
  ) {
    return write(
      AdbProtocol.cmdWrte,
      localId,
      remoteId,
      payload,
      offset,
      length,
    );
  }

  /// 写入关闭流消息
  Future<void> writeClose(int localId, int remoteId) {
    return write(AdbProtocol.cmdClse, localId, remoteId, null, 0, 0);
  }

  /// 写入确认消息
  Future<void> writeOkay(int localId, int remoteId) {
    return write(AdbProtocol.cmdOkay, localId, remoteId, null, 0, 0);
  }

  /// 写入通用ADB消息
  Future<void> write(
    int command,
    int arg0,
    int arg1,
    List<int>? payload,
    int offset,
    int length,
  ) async {
    try {
      // 计算校验和
      final checksum = payload != null
          ? _payloadChecksum(payload.sublist(offset, offset + length))
          : 0;

      final message = AdbMessage(
        command: command,
        arg0: arg0,
        arg1: arg1,
        payloadLength: length,
        checksum: checksum,
        magic: command ^ 0xFFFFFFFF, // 正确的魔数计算
        payload: payload ?? <int>[],
      );
      // 只在详细模式下显示消息写入，避免过度打印
      if (_debug) {
        Logging.verbose('(${DateTime.now()}) > $message');
      }

      final messageBytes = AdbProtocol.generateMessageWithOffset(
        command,
        arg0,
        arg1,
        payload,
        offset,
        length,
      );

      await _writeBytes(messageBytes);
    } catch (e) {
      // 对于连接关闭的异常，静默处理而不是抛出
      if (e.toString().contains('通道未连接') ||
          e.toString().contains('Connection closed') ||
          e.toString().contains('Socket closed')) {
        // 这是正常的关闭过程，不需要抛出异常
        return;
      }
      // 其他异常仍然抛出
      rethrow;
    }
  }

  /// 计算负载数据的校验和
  int _payloadChecksum(List<int> payload) {
    return AdbProtocol.getPayloadChecksum(payload, 0, payload.length);
  }

  /// 关闭写入器
  void close() {
    // Dart中不需要显式关闭，由GC处理
  }
}
