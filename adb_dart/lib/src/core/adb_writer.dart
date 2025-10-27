/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:typed_data';
import '../transport/transport_channel.dart';
import 'adb_message.dart';
import 'adb_protocol.dart';

/// ADB消息写入器
class AdbWriter {
  final TransportChannel _channel;

  AdbWriter(this._channel);

  /// 写入连接消息
  Future<void> writeConnect() async {
    try {
      final payloadData = Uint8List.fromList(AdbProtocol.connectPayload.codeUnits);
      final message = AdbMessage(
        command: AdbProtocol.cmdCnxc,
        arg0: AdbProtocol.connectVersion,
        arg1: AdbProtocol.connectMaxData,
        payloadLength: payloadData.length,
        checksum: AdbProtocol.getPayloadChecksum(payloadData, 0, payloadData.length),
        magic: AdbProtocol.cmdCnxc ^ 0xFFFFFFFF,
        payload: payloadData,
      );
      
      print('发送连接消息: 版本=${message.arg0}, 最大数据=${message.arg1}, 载荷="${String.fromCharCodes(message.payload)}"');
      await _writeMessage(message);
      print('连接消息发送完成');
    } catch (e) {
      print('发送连接消息失败: $e');
      rethrow;
    }
  }

  /// 写入STLS消息
  Future<void> writeStls(int arg0) async {
    final message = AdbMessage(
      command: AdbProtocol.cmdStls,
      arg0: arg0,
      arg1: 0,
      payloadLength: 0,
      checksum: 0,
      magic: AdbProtocol.cmdStls ^ 0xFFFFFFFF,
      payload: Uint8List(0),
    );

    await _writeMessage(message);
  }

  /// 写入认证消息
  Future<void> writeAuth(int authType, List<int> data) async {
    final payload = Uint8List.fromList(data);
    final message = AdbMessage(
      command: AdbProtocol.cmdAuth,
      arg0: authType,
      arg1: 0,
      payloadLength: payload.length,
      checksum: AdbProtocol.getPayloadChecksum(payload, 0, payload.length),
      magic: AdbProtocol.cmdAuth ^ 0xFFFFFFFF,
      payload: payload,
    );

    await _writeMessage(message);
  }

  /// 写入打开流消息
  Future<void> writeOpen(int localId, String destination) async {
    final payloadData = Uint8List.fromList('$destination\x00'.codeUnits);
    final message = AdbMessage(
      command: AdbProtocol.cmdOpen,
      arg0: localId,
      arg1: 0,
      payloadLength: payloadData.length,
      checksum: AdbProtocol.getPayloadChecksum(
        payloadData,
        0,
        payloadData.length,
      ),
      magic: AdbProtocol.cmdOpen ^ 0xFFFFFFFF,
      payload: payloadData,
    );

    await _writeMessage(message);
  }

  /// 写入OKAY消息
  Future<void> writeOkay(int localId, int remoteId) async {
    final message = AdbMessage(
      command: AdbProtocol.cmdOkay,
      arg0: localId,
      arg1: remoteId,
      payloadLength: 0,
      checksum: 0,
      magic: AdbProtocol.cmdOkay ^ 0xFFFFFFFF,
      payload: Uint8List(0),
    );

    await _writeMessage(message);
  }

  /// 写入写入消息
  Future<void> writeWrite(int localId, int remoteId, List<int> data) async {
    final payload = Uint8List.fromList(data);
    final message = AdbMessage(
      command: AdbProtocol.cmdWrte,
      arg0: localId,
      arg1: remoteId,
      payloadLength: payload.length,
      checksum: AdbProtocol.getPayloadChecksum(payload, 0, payload.length),
      magic: AdbProtocol.cmdWrte ^ 0xFFFFFFFF,
      payload: payload,
    );

    await _writeMessage(message);
  }

  /// 写入关闭消息
  Future<void> writeClose(int localId, int remoteId) async {
    final message = AdbMessage(
      command: AdbProtocol.cmdClse,
      arg0: localId,
      arg1: remoteId,
      payloadLength: 0,
      checksum: 0,
      magic: AdbProtocol.cmdClse ^ 0xFFFFFFFF,
      payload: Uint8List(0),
    );

    await _writeMessage(message);
  }

  /// 写入消息到通道
  Future<void> _writeMessage(AdbMessage message) async {
    final buffer = BytesBuilder();

    // 写入消息头
    final header = ByteData(24);
    header.setUint32(0, message.command, Endian.little);
    header.setUint32(4, message.arg0, Endian.little);
    header.setUint32(8, message.arg1, Endian.little);
    header.setUint32(12, message.payloadLength, Endian.little);
    header.setUint32(16, message.checksum, Endian.little);
    header.setUint32(20, message.magic, Endian.little);

    buffer.add(header.buffer.asUint8List());

    // 写入载荷
    if (message.payloadLength > 0) {
      buffer.add(message.payload);
    }

    // 发送数据
    await _channel.write(buffer.toBytes());
    await _channel.flush();
  }

  /// 关闭写入器
  void close() {
    // Socket关闭由连接管理
  }
}
