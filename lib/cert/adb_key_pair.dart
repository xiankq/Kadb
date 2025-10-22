import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import '../core/adb_message.dart';
import 'android_pubkey.dart';

/// ADB密钥对类，负责ADB协议的密钥管理和签名操作
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

    final seedSource = Random.secure();
    final seeds = Uint8List(32);
    for (int i = 0; i < seeds.length; i++) {
      seeds[i] = seedSource.nextInt(256);
    }
    random.seed(KeyParameter(seeds));

    final params = RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 12);

    keyGen.init(ParametersWithRandom(params, random));

    final keyPair = keyGen.generateKeyPair();
    final publicKey = keyPair.publicKey;
    final privateKey = keyPair.privateKey;

    if (!_validateGeneratedKeyPair(privateKey, publicKey)) {
      throw StateError('RSA密钥对质量验证失败');
    }

    return AdbKeyPair(privateKey, publicKey);
  }

  /// 验证生成的RSA密钥对质量
  static bool _validateGeneratedKeyPair(
    RSAPrivateKey privateKey,
    RSAPublicKey publicKey,
  ) {
    try {
      if (privateKey.modulus == null ||
          privateKey.privateExponent == null ||
          publicKey.modulus == null ||
          publicKey.exponent == null) {
        return false;
      }

      final keyLength = privateKey.modulus!.bitLength;
      if (keyLength != 2048) {
        return false;
      }

      if (privateKey.modulus != publicKey.modulus) {
        return false;
      }

      if (publicKey.exponent != BigInt.from(65537)) {
        return false;
      }

      final privateExponent = privateKey.privateExponent!;
      if (privateExponent <= BigInt.one ||
          privateExponent == publicKey.exponent) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 使用私钥对ADB消息payload进行签名
  Uint8List signAdbMessagePayload(List<int> payload) {
    final payloadBytes = Uint8List.fromList(payload);

    if (payloadBytes.length > 20) {
      throw ArgumentError('消息负载长度($payloadBytes.length)超过RSA签名限制(20字节)');
    }

    final modulus = _privateKey.modulus;
    final privateExponent = _privateKey.privateExponent;

    if (modulus == null || privateExponent == null) {
      throw StateError('RSA私钥参数不完整，密钥可能已损坏或退化');
    }

    final keyLength = modulus.bitLength ~/ 8;
    if (keyLength != 256) {
      throw StateError('RSA密钥长度异常: 期望256字节，实际$keyLength字节');
    }

    final signaturePadding = AndroidPubkey.signaturePadding;
    final buffer = BytesBuilder();
    buffer.add(signaturePadding);
    buffer.add(payloadBytes);
    final dataToSign = buffer.toBytes();

    final dataToSignBigInt = _bytesToBigInt(dataToSign);
    final signatureBigInt = dataToSignBigInt.modPow(privateExponent, modulus);

    return _bigIntToBytes(signatureBigInt, keyLength);
  }

  /// 使用私钥对ADB消息进行签名
  Uint8List signAdbMessage(AdbMessage message) {
    final modulus = _privateKey.modulus;
    final privateExponent = _privateKey.privateExponent;
    final payloadLength = message.payloadLength;

    if (payloadLength > 20) {
      throw ArgumentError('消息负载长度($payloadLength)超过RSA签名限制(20字节)');
    }

    if (modulus == null || privateExponent == null) {
      throw StateError('RSA私钥参数不完整，密钥可能已损坏或退化');
    }

    final keyLength = modulus.bitLength ~/ 8;
    if (keyLength != 256) {
      throw StateError('RSA密钥长度异常: 期望256字节，实际$keyLength字节');
    }

    final signaturePadding = AndroidPubkey.signaturePadding;
    final paddingLength = signaturePadding.length;
    final combinedBytes = Uint8List(keyLength);

    for (int i = 0; i < paddingLength; i++) {
      combinedBytes[i] = signaturePadding[i];
    }

    combinedBytes.setRange(
      paddingLength,
      paddingLength + payloadLength,
      message.payload.sublist(0, payloadLength),
    );

    final combinedBigInt = _bytesToBigInt(combinedBytes);
    final encrypted = combinedBigInt.modPow(privateExponent, modulus);

    return _bigIntToBytes(encrypted, keyLength);
  }

  /// 验证签名
  bool verify(Uint8List data, Uint8List signature) {
    try {
      final modulus = _publicKey.modulus;
      final exponent = _publicKey.exponent;

      if (modulus == null || exponent == null) {
        return false;
      }

      final keyLength = modulus.bitLength ~/ 8;
      if (keyLength != 256) {
        return false;
      }

      final c = _bytesToBigInt(signature);
      final decrypted = c.modPow(exponent, modulus);
      final decryptedBytes = _bigIntToBytes(decrypted, keyLength);

      final padding = AndroidPubkey.signaturePadding;
      final payloadStart = padding.length;

      if (decryptedBytes.length < payloadStart + data.length) {
        return false;
      }

      for (int i = 0; i < padding.length; i++) {
        if (decryptedBytes[i] != padding[i]) {
          return false;
        }
      }

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
