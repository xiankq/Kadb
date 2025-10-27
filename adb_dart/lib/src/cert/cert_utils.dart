/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/export.dart';
import 'adb_key_pair.dart';
import 'platform/default_device_name.dart' as platform_default_device_name;
import 'android_pubkey.dart';
import 'rsa_utils.dart';
import 'rsa_key_manager.dart';
import 'base64_utils.dart';

/// 证书工具类，负责加载和管理ADB密钥对
class CertUtils {
  static const String _privateKeyFileName = 'adb_private_key.pem';
  static const String _publicKeyFileName = 'adb_public_key.pem';

  /// 加载或生成ADB密钥对
  static Future<AdbKeyPair> loadKeyPair() async {
    try {
      // 首先尝试从文件加载现有密钥对
      final privateKeyFile = File(_privateKeyFileName);
      final publicKeyFile = File(_publicKeyFileName);

      if (await privateKeyFile.exists() && await publicKeyFile.exists()) {
        // 尝试从PEM格式解析密钥
        final privateKeyPem = await privateKeyFile.readAsString();
        final publicKeyPem = await publicKeyFile.readAsString();

        return _parsePemKeyPair(privateKeyPem, publicKeyPem);
      }
    } catch (e) {
      print('从文件加载密钥对失败，将生成新的密钥对：$e');
    }

    // 如果文件不存在或加载失败，生成新的密钥对
    final keyPair = await _generateKeyPair();

    // 保存密钥对到文件
    await saveKeyPair(keyPair);

    return keyPair;
  }

  /// 生成新的RSA密钥对
  static Future<AdbKeyPair> _generateKeyPair() async {
    try {
      print('正在生成新的RSA密钥对...');
      
      // 使用改进的RSA密钥管理器生成密钥对
      final keyPair = await RsaKeyManager.generateKeyPair();
      
      print('RSA密钥对生成成功');
      
      // 转换为AdbKeyPair
      return _createAdbKeyPair(keyPair.privateKey, keyPair.publicKey);
    } catch (e) {
      throw Exception('生成RSA密钥对失败：$e');
    }
  }

  /// 创建AdbKeyPair实例
  static AdbKeyPair _createAdbKeyPair(
    RSAPrivateKey privateKey,
    RSAPublicKey publicKey,
  ) {
    // 将密钥转换为字节数组（简化格式）
    final privateKeyBytes = _encodePrivateKey(privateKey);
    final publicKeyBytes = _encodePublicKey(publicKey);

    return AdbKeyPair(privateKey: privateKeyBytes, publicKey: publicKeyBytes);
  }

  /// 编码私钥
  static Uint8List _encodePrivateKey(RSAPrivateKey privateKey) {
    final buffer = _SimpleBytesBuilder();
    final modulusBytes = _bigIntToBytes(privateKey.n!);
    final privateExponentBytes = _bigIntToBytes(privateKey.privateExponent!);

    buffer.addUint32(modulusBytes.length);
    buffer.addBytes(modulusBytes);
    buffer.addUint32(privateExponentBytes.length);
    buffer.addBytes(privateExponentBytes);

    return buffer.toBytes();
  }

  /// 编码公钥
  static Uint8List _encodePublicKey(RSAPublicKey publicKey) {
    final buffer = _SimpleBytesBuilder();
    final modulusBytes = _bigIntToBytes(publicKey.modulus!);
    final exponentBytes = _bigIntToBytes(publicKey.exponent!);

    buffer.addUint32(modulusBytes.length);
    buffer.addBytes(modulusBytes);
    buffer.addUint32(exponentBytes.length);
    buffer.addBytes(exponentBytes);

    return buffer.toBytes();
  }

  /// 大整数转字节数组
  static List<int> _bigIntToBytes(BigInt bigInt) {
    var hex = bigInt.toRadixString(16);
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }

    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }

    return bytes;
  }

  /// 生成随机字节
  static Uint8List _generateRandomBytes(int length) {
    final random = Random();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  /// 保存密钥对到文件
  static Future<void> saveKeyPair(AdbKeyPair keyPair) async {
    try {
      final privateKeyFile = File(_privateKeyFileName);
      final publicKeyFile = File(_publicKeyFileName);

      // 将密钥对保存为PEM格式
      final privateKeyPem = _encodePrivateKeyPem(keyPair.privateKey);
      final publicKeyPem = _encodePublicKeyPem(keyPair.publicKey);

      await privateKeyFile.writeAsString(privateKeyPem);
      await publicKeyFile.writeAsString(publicKeyPem);

      print('密钥对已保存到文件');
    } catch (e) {
      throw Exception('保存密钥对失败：$e');
    }
  }

  /// 获取默认设备名称
  static String getDefaultDeviceName() {
    // 使用平台特定的设备名称
    return platform_default_device_name.defaultDeviceName();
  }

  /// 解析PEM格式的密钥对
  static Future<AdbKeyPair> _parsePemKeyPair(
    String privateKeyPem,
    String publicKeyPem,
  ) async {
    try {
      // 提取PEM内容
      final privateKeyContent = _extractPemContent(
        privateKeyPem,
        'RSA PRIVATE KEY',
      );
      final publicKeyContent = _extractPemContent(publicKeyPem, 'PUBLIC KEY');

      // 使用专业的Base64解码
      final privateKeyBytes = Base64Utils.decode(privateKeyContent);
      final publicKeyBytes = Base64Utils.decode(publicKeyContent);

      return AdbKeyPair(privateKey: privateKeyBytes, publicKey: publicKeyBytes);
    } catch (e) {
      throw Exception('解析PEM密钥失败：$e');
    }
  }

  /// 提取PEM内容
  static String _extractPemContent(String pem, String type) {
    final beginMarker = '-----BEGIN $type-----';
    final endMarker = '-----END $type-----';

    final beginIndex = pem.indexOf(beginMarker);
    final endIndex = pem.indexOf(endMarker);

    if (beginIndex == -1 || endIndex == -1) {
      throw ArgumentError('Invalid PEM format');
    }

    return pem
        .substring(beginIndex + beginMarker.length, endIndex)
        .replaceAll(RegExp(r'\s'), '');
  }

  /// 编码私钥为PEM格式
  static String _encodePrivateKeyPem(Uint8List privateKey) {
    final base64Content = Base64Utils.encode(privateKey);
    final formattedContent = _formatPemContent(base64Content);

    return '-----BEGIN RSA PRIVATE KEY-----\n'
        '$formattedContent'
        '-----END RSA PRIVATE KEY-----\n';
  }

  /// 编码公钥为PEM格式
  static String _encodePublicKeyPem(Uint8List publicKey) {
    final base64Content = Base64Utils.encode(publicKey);
    final formattedContent = _formatPemContent(base64Content);

    return '-----BEGIN PUBLIC KEY-----\n'
        '$formattedContent'
        '-----END PUBLIC KEY-----\n';
  }

  /// 格式化PEM内容
  static String _formatPemContent(String base64Content) {
    final buffer = StringBuffer();
    for (int i = 0; i < base64Content.length; i += 64) {
      final endIndex = (i + 64 < base64Content.length)
          ? i + 64
          : base64Content.length;
      buffer.writeln(base64Content.substring(i, endIndex));
    }
    return buffer.toString();
  }
}

/// 简单的字节构建器
class _SimpleBytesBuilder {
  final List<int> _bytes = [];

  void addUint32(int value) {
    _bytes.add((value >> 24) & 0xFF);
    _bytes.add((value >> 16) & 0xFF);
    _bytes.add((value >> 8) & 0xFF);
    _bytes.add(value & 0xFF);
  }

  void addBytes(List<int> bytes) {
    _bytes.addAll(bytes);
  }

  Uint8List toBytes() => Uint8List.fromList(_bytes);
}
