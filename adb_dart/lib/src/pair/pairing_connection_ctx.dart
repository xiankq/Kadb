/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../cert/adb_key_pair.dart';
import '../cert/rsa_utils.dart';
import '../cert/rsa_key_manager.dart';
import '../cert/android_pubkey.dart';
import '../cert/base64_utils.dart';
import '../core/adb_connection.dart';
import 'pairing_auth_ctx.dart';
import 'ssl_utils.dart';
import '../exception/adb_exceptions.dart';

/// 配对连接上下文
class PairingConnectionCtx {
  final String host;
  final int port;
  final Uint8List pairingCode;
  final AdbKeyPair keyPair;
  final String deviceName;

  PairingConnectionCtx({
    required this.host,
    required this.port,
    required this.pairingCode,
    required this.keyPair,
    required this.deviceName,
  });

  /// 开始配对过程
  Future<void> start() async {
    print('开始设备配对过程...');
    print('主机: $host:$port');
    print('设备名称: $deviceName');

    try {
      // 建立TLS连接
      final tlsSocket = await _establishTlsConnection();

      // 执行配对认证
      await _performPairingAuth(tlsSocket);

      // 验证配对结果
      await _verifyPairingResult(tlsSocket);

      print('设备配对成功！');

      // 发送公钥给设备
      await _sendPublicKeyToDevice(tlsSocket);
    } catch (e) {
      print('设备配对失败: $e');
      if (e is AdbPairAuthException) rethrow;
      throw AdbPairAuthException('设备配对失败', e);
    }
  }

  /// 建立TLS连接
  Future<SecureSocket> _establishTlsConnection() async {
    print('建立TLS连接...');

    try {
      final sslContext = SslUtils.getSslContext(keyPair);
      final secureSocket = await SslUtils.createTlsClient(host, port, keyPair);

      // 执行TLS握手
      await SslUtils.handshake(secureSocket, const Duration(seconds: 30));

      print('TLS连接建立成功');
      return secureSocket;
    } catch (e) {
      throw Exception('建立TLS连接失败: $e');
    }
  }

  /// 执行配对认证
  Future<void> _performPairingAuth(SecureSocket socket) async {
    print('执行配对认证...');

    final authCtx = PairingAuthCtx(
      keyPair: keyPair,
      pairingCode: pairingCode,
      deviceName: deviceName,
    );

    try {
      // 发送配对请求
      final requestData = _createPairingRequest();
      socket.add(requestData);
      await socket.flush();

      print('配对请求已发送');

      // 等待配对响应
      final response = await _readPairingResponse(socket);

      // 验证响应
      if (!authCtx.verifyPairingCode(response)) {
        throw Exception('配对码验证失败');
      }

      print('配对认证成功');
    } catch (e) {
      throw Exception('配对认证失败: $e');
    }
  }

  /// 验证配对结果
  Future<void> _verifyPairingResult(SecureSocket socket) async {
    print('验证配对结果...');

    try {
      // 发送配对确认
      final authData = _createPairingConfirmation();
      socket.add(authData);
      await socket.flush();

      // 等待确认响应
      final confirmation = await _readConfirmationResponse(socket);

      if (!_isValidConfirmation(confirmation)) {
        throw Exception('配对确认验证失败');
      }

      print('配对结果验证成功');
    } catch (e) {
      throw Exception('验证配对结果失败: $e');
    }
  }

  /// 创建配对请求
  Uint8List _createPairingRequest() {
    final builder = BytesBuilder();

    // 请求标识 (PAIRING_REQUEST)
    builder.addByte(0x00);

    // 版本号
    builder.addByte(0x01);

    // 配对码长度
    builder.addByte(pairingCode.length);

    // 配对码
    builder.add(pairingCode);

    // 设备名称长度
    builder.addByte(deviceName.length);

    // 设备名称
    builder.add(deviceName.codeUnits);

    // 添加公钥指纹（简化实现）
    final publicKey = keyPair.toRsaPublicKey();
    final androidFormat = RsaKeyManager.convertRsaPublicKeyToAndroidFormat(publicKey);
    final fingerprint = _calculateFingerprint(androidFormat);

    builder.addByte(fingerprint.length);
    builder.add(fingerprint);

    return builder.toBytes();
  }

  /// 计算公钥指纹
  List<int> _calculateFingerprint(Uint8List publicKey) {
    // 简化实现：取前16个字节作为指纹
    return publicKey.take(16).toList();
  }

  /// 发送公钥给设备
  Future<void> _sendPublicKeyToDevice(SecureSocket socket) async {
    print('发送公钥给设备...');

    try {
      final publicKey = keyPair.toRsaPublicKey();
      final androidFormat = RsaKeyManager.convertRsaPublicKeyToAndroidFormat(publicKey);

      // Base64编码
      final base64Encoded = Base64Utils.encode(androidFormat);

      // 添加设备名称
      final deviceInfo = '$base64Encoded $deviceName}';

      // 发送公钥数据
      final deviceInfoBytes = Uint8List.fromList(deviceInfo.codeUnits);
      socket.add(deviceInfoBytes);
      await socket.flush();

      print('公钥发送成功');
    } catch (e) {
      throw AdbPairAuthException('发送公钥失败', e);
    }
  }

  /// 读取配对响应
  Future<Uint8List> _readPairingResponse(SecureSocket socket) async {
    // 简化实现：读取固定长度的响应
    final response = await socket.first;
    return response;
  }

  /// 创建配对确认
  Uint8List _createPairingConfirmation() {
    final authCtx = PairingAuthCtx(
      keyPair: keyPair,
      pairingCode: pairingCode,
      deviceName: deviceName,
    );

    return authCtx.createPairingResponse();
  }

  /// 读取确认响应
  Future<Uint8List> _readConfirmationResponse(SecureSocket socket) async {
    // 简化实现：读取确认响应
    final response = await socket.first;
    return response;
  }

  /// 验证确认响应
  bool _isValidConfirmation(Uint8List confirmation) {
    // 简化实现：检查响应标识
    if (confirmation.isEmpty) return false;

    return confirmation[0] == 0x01; // PAIRING_SUCCESS
  }

  /// 关闭连接
  Future<void> close() async {
    print('关闭配对连接...');
    // 清理资源将在调用方处理
  }
}
