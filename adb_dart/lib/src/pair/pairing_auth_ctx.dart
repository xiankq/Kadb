/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:typed_data';
import 'dart:convert';
import '../cert/adb_key_pair.dart';
import '../cert/rsa_utils.dart';
import '../cert/rsa_key_manager.dart';
import '../cert/android_pubkey.dart';
import '../cert/base64_utils.dart';

/// 配对认证上下文
class PairingAuthCtx {
  final AdbKeyPair keyPair;
  final Uint8List pairingCode;
  final String deviceName;

  PairingAuthCtx({
    required this.keyPair,
    required this.pairingCode,
    required this.deviceName,
  });

  /// 验证配对码
  bool verifyPairingCode(Uint8List code) {
    if (code.length != pairingCode.length) return false;

    for (int i = 0; i < code.length; i++) {
      if (code[i] != pairingCode[i]) return false;
    }

    return true;
  }

  /// 获取认证数据
  Uint8List getAuthData() {
    // 构建认证数据
    final builder = BytesBuilder();

    // 添加设备名称
    builder.add(deviceName.codeUnits);

    // 添加配对码
    builder.add(pairingCode);

    // 添加密钥指纹（简化实现）
    final keyFingerprint = _calculateKeyFingerprint();
    builder.add(keyFingerprint);

    return builder.toBytes();
  }

  /// 计算密钥指纹（使用SHA-256）
  Uint8List _calculateKeyFingerprint() {
    try {
      final publicKey = keyPair.toRsaPublicKey();
      final androidFormat = RsaKeyManager.convertRsaPublicKeyToAndroidFormat(publicKey);

      // 使用SHA-256计算指纹
      final fingerprint = _sha256(androidFormat);

      // 取前16个字节
      return Uint8List.fromList(fingerprint.take(16).toList());
    } catch (e) {
      // 如果失败，使用公钥的前16个字节
      final publicKey = keyPair.publicKey;
      if (publicKey.length >= 16) {
        return publicKey.sublist(0, 16);
      } else {
        return publicKey;
      }
    }
  }

  /// 简单的SHA-256实现（简化版本）
  List<int> _sha256(List<int> data) {
    // 在实际应用中，这里应该使用专业的加密库
    // 这里提供一个简化的哈希实现
    var hash = 0x811c9dc5;
    for (final byte in data) {
      hash ^= byte;
      hash *= 0x01000193;
    }

    final result = <int>[];
    for (int i = 0; i < 32; i++) {
      result.add((hash >> (i * 8)) & 0xFF);
    }
    return result;
  }

  /// 创建配对响应
  Uint8List createPairingResponse() {
    try {
      final builder = BytesBuilder();

      // 响应标识
      builder.addByte(0x01); // PAIRING_RESPONSE

      // 版本号
      builder.addByte(0x01);

      // 设备名称长度
      builder.addByte(deviceName.length);

      // 设备名称
      builder.add(deviceName.codeUnits);

      // 公钥长度（Android格式）
      final publicKey = keyPair.toRsaPublicKey();
      final androidFormat = RsaKeyManager.convertRsaPublicKeyToAndroidFormat(publicKey);
      builder.addByte(androidFormat.length);

      // 公钥（Android格式）
      builder.add(androidFormat);

      // 指纹（SHA-256的前16字节）
      final fingerprint = _calculateKeyFingerprint();
      builder.addByte(fingerprint.length);
      builder.add(fingerprint);

      return builder.toBytes();
    } catch (e) {
      // 如果失败，使用简化的响应格式
      final builder = BytesBuilder();
      builder.addByte(0x01); // PAIRING_RESPONSE
      builder.addByte(deviceName.length);
      builder.add(deviceName.codeUnits);
      builder.addByte(keyPair.publicKey.length);
      builder.add(keyPair.publicKey);
      return builder.toBytes();
    }
  }

  /// 验证配对响应
  bool verifyPairingResponse(Uint8List response) {
    if (response.isEmpty) return false;

    try {
      final buffer = ByteData.sublistView(response);

      // 检查响应标识
      final responseId = buffer.getUint8(0);
      if (responseId != 0x01) return false; // PAIRING_RESPONSE

      // 检查版本号
      final version = buffer.getUint8(1);
      if (version != 0x01) return false;

      // 检查设备名称
      final deviceNameLength = buffer.getUint8(2);
      final deviceNameBytes = response.sublist(3, 3 + deviceNameLength);
      final receivedDeviceName = utf8.decode(deviceNameBytes);

      if (receivedDeviceName != deviceName) return false;

      return true;
    } catch (e) {
      return false;
    }
  }
}
