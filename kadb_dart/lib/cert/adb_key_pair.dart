/// ADB密钥对类
/// 专注于核心的密钥操作：生成、签名、验证
library;

import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:kadb_dart/core/adb_message.dart';
import 'package:kadb_dart/cert/android_pubkey.dart';

/// ADB密钥对类
///
/// 职责：
/// - 密钥对的生成
/// - 数据签名和验证
/// - 密钥对的内部状态管理
class AdbKeyPair {
  final RSAPrivateKey _privateKey;
  final RSAPublicKey _publicKey;

  /// 创建新的ADB密钥对
  AdbKeyPair(this._privateKey, this._publicKey);

  /// 获取私钥
  RSAPrivateKey get privateKey => _privateKey;

  /// 获取公钥
  RSAPublicKey get publicKey => _publicKey;

  /// 生成新的RSA密钥对
  static Future<AdbKeyPair> generate() async {
    final keyGen = RSAKeyGenerator();
    final random = FortunaRandom();

    // 初始化随机数生成器
    final seedSource = Random.secure();
    final seeds = <int>[];
    for (int i = 0; i < 32; i++) {
      seeds.add(seedSource.nextInt(256));
    }
    random.seed(KeyParameter(Uint8List.fromList(seeds)));

    // 生成RSA密钥参数（与Kotlin版本完全一致）
    final params = RSAKeyGeneratorParameters(
      BigInt.from(65537),
      2048,
      5, // 使用较小的certainty值，与Kotlin版本保持一致
    );

    keyGen.init(ParametersWithRandom(params, random));

    // 生成密钥对
    final keyPair = keyGen.generateKeyPair();
    final publicKey = keyPair.publicKey;
    final privateKey = keyPair.privateKey;

    return AdbKeyPair(privateKey, publicKey);
  }

  
  /// 使用私钥对ADB消息payload进行签名（与Kotlin版本的signPayload方法完全一致）
  /// 这个方法专门用于ADB认证流程中的token签名
  /// [payload] 要签名的负载数据（List<int>类型，在方法内部会转换为Uint8List）
  Uint8List signAdbMessagePayload(List<int> payload) {
    // 将List<int>转换为Uint8List以便处理
    final payloadBytes = Uint8List.fromList(payload);

    if (payloadBytes.length > 20) {
      throw ArgumentError('消息负载长度($payloadBytes.length)超过RSA签名限制(20字节)');
    }

    // 关键修复：使用PointyCastle的RSA签名器，确保与Java Cipher行为一致
    // 1. 创建签名填充（模拟Java Cipher.update()）
    final signaturePadding = AndroidPubkey.signaturePadding;
    final buffer = BytesBuilder();
    buffer.add(signaturePadding);

    // 2. 添加payload（模拟Java Cipher.doFinal()）
    buffer.add(payloadBytes);
    final dataToSign = buffer.toBytes();

    // 3. 执行RSA签名（修复字节序问题）
    final modulus = _privateKey.modulus ?? BigInt.zero;
    final privateExponent = _privateKey.privateExponent ?? BigInt.one;
    final keyLength = modulus.bitLength ~/ 8;

    // 关键修复：使用正确的大端序字节处理
    final dataToSignBigInt = _bytesToBigInt(dataToSign);
    final signatureBigInt = dataToSignBigInt.modPow(privateExponent, modulus);

    // 确保返回256字节
    return _bigIntToBytes(signatureBigInt, keyLength);
  }

  /// 使用私钥对ADB消息进行签名（与Kotlin版本完全一致，使用RSA/ECB/NoPadding模式）
  Uint8List signAdbMessage(AdbMessage message) {
    final modulus = _privateKey.modulus ?? BigInt.zero;
    final privateExponent = _privateKey.privateExponent ?? BigInt.one;
    final keyLength = modulus.bitLength ~/ 8;
    final payloadLength = message.payloadLength;

    if (payloadLength > 20) {
      throw ArgumentError('消息负载长度($payloadLength)超过RSA签名限制(20字节)');
    }

    // 关键修复：使用与Kotlin版本完全相同的签名填充（236字节）
    final signaturePadding = AndroidPubkey.signaturePadding;
    final paddingLength = signaturePadding.length;

    // 签名填充(236字节) + 消息负载(20字节) = 256字节，正好是RSA密钥长度
    final combinedBytes = Uint8List(keyLength);

    // 直接复制整个签名填充（236字节）
    for (int i = 0; i < paddingLength; i++) {
      combinedBytes[i] = signaturePadding[i];
    }

    // 复制消息负载
    combinedBytes.setRange(
      paddingLength,
      paddingLength + payloadLength,
      message.payload.sublist(0, payloadLength),
    );

    // 复制消息负载
    combinedBytes.setRange(
      paddingLength,
      paddingLength + payloadLength,
      message.payload.sublist(0, payloadLength),
    );

    // 关键修复：使用私钥指数进行RSA加密（签名），使用NoPadding模式
    final combinedBigInt = _bytesToBigInt(combinedBytes);
    final encrypted = combinedBigInt.modPow(privateExponent, modulus);

    return _bigIntToBytes(encrypted, keyLength);
  }

  /// 验证签名（与Kotlin版本一致，使用RSA无填充模式）
  bool verify(Uint8List data, Uint8List signature) {
    try {
      // 手动实现RSA解密：c^e mod n
      final modulus = _publicKey.modulus ?? BigInt.zero;
      final exponent = _publicKey.exponent ?? BigInt.from(65537);

      final c = _bytesToBigInt(signature);
      final decrypted = c.modPow(exponent, modulus);

      // 将解密后的大整数转换为字节数组
      final keyLength = modulus.bitLength ~/ 8;
      final decryptedBytes = _bigIntToBytes(decrypted, keyLength);

      // ADB签名验证的特殊逻辑：检查解密后的数据是否包含原始数据
      final padding = AndroidPubkey.signaturePadding;
      final payloadStart = padding.length; // 关键修复：使用实际的填充长度

      // 检查解密后的数据是否以填充开头
      if (decryptedBytes.length < payloadStart + data.length) {
        return false;
      }

      // 检查填充部分是否匹配
      for (int i = 0; i < padding.length; i++) {
        if (decryptedBytes[i] != padding[i]) {
          return false;
        }
      }

      // 检查数据部分是否匹配
      for (int i = 0; i < data.length; i++) {
        if (decryptedBytes[payloadStart + i] != data[i]) {
          return false;
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  
  /// 将字节数组转换为大整数
  BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (var i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  /// 将大整数转换为指定长度的字节数组
  Uint8List _bigIntToBytes(BigInt value, int length) {
    var hex = value.toRadixString(16);
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }

    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }

    // 填充到指定长度（从左侧填充0）
    while (bytes.length < length) {
      bytes.insert(0, 0);
    }

    // 如果超过指定长度，截断左侧（保留右侧）
    if (bytes.length > length) {
      return Uint8List.fromList(bytes.sublist(bytes.length - length));
    }

    return Uint8List.fromList(bytes);
  }
}

