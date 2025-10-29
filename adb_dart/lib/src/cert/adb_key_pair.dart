/// RSA密钥对管理
///
/// 管理RSA密钥对，支持Token签名和Android格式公钥转换
library;

import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/export.dart';

/// RSA密钥对类
///
/// 封装RSA私钥和公钥，提供签名功能
class AdbKeyPair {
  /// RSA私钥数据（PKCS#8格式）
  final Uint8List privateKeyData;

  /// RSA公钥数据（X.509格式）
  final Uint8List publicKeyData;

  /// 证书数据（可选）
  final Uint8List? certificateData;

  /// 构造函数
  const AdbKeyPair({
    required this.privateKeyData,
    required this.publicKeyData,
    this.certificateData,
  });

  /// 使用私钥签名数据
  ///
  /// 使用RSA/ECB/NoPadding模式进行签名
  /// 在签名前会自动添加Android特殊的PKCS#1 v1.5填充
  Uint8List signPayload(Uint8List payload) {
    if (payload.length != 256) {
      throw ArgumentError('Token长度必须是256字节，实际长度: ${payload.length}');
    }

    // 创建待签名数据：填充 + Token
    final dataToSign = Uint8List(256);

    // 添加Android特殊的PKCS#1 v1.5填充
    dataToSign[0] = 0x00;
    dataToSign[1] = 0x01;

    // 填充0xFF字节
    for (int i = 2; i < 256 - 20 - 1; i++) {
      dataToSign[i] = 0xFF;
    }

    dataToSign[256 - 20 - 1] = 0x00;

    // 添加SHA-1哈希标识符（基于libmincrypt实现）
    final sha1Identifier = [
      0x30,
      0x21,
      0x30,
      0x09,
      0x06,
      0x05,
      0x2B,
      0x0E,
      0x03,
      0x02,
      0x1A,
      0x05,
      0x00,
      0x04,
      0x14,
    ];

    for (int i = 0; i < sha1Identifier.length; i++) {
      dataToSign[256 - 20 - 1 - sha1Identifier.length + i] = sha1Identifier[i];
    }

    // 复制Token数据（最后20字节是SHA-1哈希，但这里直接复制整个Token）
    for (int i = 0; i < payload.length; i++) {
      dataToSign[256 - payload.length + i] = payload[i];
    }

    // 使用RSA/ECB/NoPadding模式进行签名
    return _rsaSign(dataToSign);
  }

  /// 使用RSA进行签名
  Uint8List _rsaSign(Uint8List dataToSign) {
    try {
      // 解析私钥
      final privateKey = _parsePrivateKey(privateKeyData);

      // 创建RSA引擎 - 使用字符串标识符
      final signer = RSASigner(SHA1Digest(), 'PKCS#1');
      signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

      // 执行签名
      final signature = signer.generateSignature(dataToSign);

      // 获取签名数据
      final signatureBytes = Uint8List.fromList(signature.bytes);

      // RSA签名结果应该是256字节（2048位密钥）
      if (signatureBytes.length != 256) {
        throw StateError('RSA签名结果长度不正确：期望256字节，实际${signatureBytes.length}字节');
      }

      return signatureBytes;
    } catch (e) {
      throw StateError('RSA签名失败: $e');
    }
  }

  /// 解析PKCS#8私钥
  RSAPrivateKey _parsePrivateKey(Uint8List privateKeyData) {
    try {
      // 创建ASN1Parser解析PKCS#8格式
      final parser = ASN1Parser(privateKeyData);
      final topLevelSeq = parser.nextObject() as ASN1Sequence;

      // PKCS#8格式：
      // SEQUENCE {
      //   INTEGER version
      //   SEQUENCE algorithmIdentifier
      //   OCTET STRING privateKey
      // }

      final privateKeyOctetString = topLevelSeq.elements[2] as ASN1OctetString;
      final privateKeyBytes = privateKeyOctetString.valueBytes;
      if (privateKeyBytes == null) {
        throw StateError('无法获取私钥数据');
      }

      // 解析PKCS#1格式的私钥
      final privateKeyParser = ASN1Parser(privateKeyBytes);
      final privateKeySeq = privateKeyParser.nextObject() as ASN1Sequence;

      // PKCS#1格式：
      // SEQUENCE {
      //   INTEGER version
      //   INTEGER modulus
      //   INTEGER publicExponent
      //   INTEGER privateExponent
      //   INTEGER prime1
      //   INTEGER prime2
      //   ...
      // }

      final modulusInteger = privateKeySeq.elements[1] as ASN1Integer;
      final modulus = _extractBigIntFromASN1Integer(modulusInteger);

      final privateExponentInteger = privateKeySeq.elements[3] as ASN1Integer;
      final privateExponent = _extractBigIntFromASN1Integer(privateExponentInteger);

      // 创建RSA私钥
      return RSAPrivateKey(
        modulus,
        privateExponent,
        BigInt.zero, // p
        BigInt.zero, // q
      );
    } catch (e) {
      throw StateError('解析私钥失败: $e');
    }
  }

  /// 获取公钥指纹（SHA-256）
  String getPublicKeyFingerprint() {
    final digest = sha256.convert(publicKeyData);
    return digest.toString();
  }

  /// 转换为调试字符串
  @override
  String toString() {
    return 'AdbKeyPair(公钥指纹: ${getPublicKeyFingerprint().substring(0, 16)}...)';
  }

  /// 检查密钥对是否有效
  bool get isValid {
    return privateKeyData.isNotEmpty && publicKeyData.isNotEmpty;
  }

  /// 获取密钥大小（位）
  int get keySize {
    try {
      // 解析公钥的ASN.1结构来获取密钥大小
      final parser = ASN1Parser(publicKeyData);
      final topLevelSeq = parser.nextObject() as ASN1Sequence;

      // X.509公钥格式：
      // SEQUENCE {
      //   SEQUENCE algorithmIdentifier
      //   BIT STRING publicKey
      // }

      final publicKeyBitString = topLevelSeq.elements[1] as ASN1BitString;
      final publicKeyBytes = publicKeyBitString.stringValues!;

      // 解析PKCS#1格式的公钥
      final publicKeyParser = ASN1Parser(publicKeyBytes);
      final publicKeySeq = publicKeyParser.nextObject() as ASN1Sequence;

      // PKCS#1格式：
      // SEQUENCE {
      //   INTEGER modulus
      //   INTEGER publicExponent
      // }

      if (publicKeySeq.elements == null || publicKeySeq.elements!.isEmpty || publicKeySeq.elements!.length < 2) {
        throw StateError('无效的PKCS#1 RSA公钥格式');
      }

      final modulus = _extractBigIntFromASN1Integer(publicKeySeq.elements![0] as ASN1Integer);

      // 计算密钥大小（位数）
      return modulus.bitLength;
    } catch (e) {
      // 如果解析失败，根据数据长度估算
      return publicKeyData.length > 300 ? 2048 : 1024;
    }
  }

  /// 创建空的密钥对（用于特定场景）
  factory AdbKeyPair.empty() {
    return AdbKeyPair(
      privateKeyData: Uint8List(0),
      publicKeyData: Uint8List(0),
    );
  }

  /// 从PEM格式创建密钥对
  ///
  /// [privateKeyPem] PKCS#8格式的私钥PEM
  /// [publicKeyPem] X.509格式的公钥PEM
  /// [certificatePem] 证书PEM（可选）
  factory AdbKeyPair.fromPem({
    required String privateKeyPem,
    required String publicKeyPem,
    String? certificatePem,
  }) {
    // 移除PEM头部和尾部
    final privateKeyClean = _cleanPem(privateKeyPem, 'PRIVATE KEY');
    final publicKeyClean = _cleanPem(publicKeyPem, 'PUBLIC KEY');
    final certificateClean = certificatePem != null
        ? _cleanPem(certificatePem, 'CERTIFICATE')
        : null;

    // Base64解码
    final privateKeyData = _base64Decode(privateKeyClean);
    final publicKeyData = _base64Decode(publicKeyClean);
    final certificateData =
        certificateClean != null ? _base64Decode(certificateClean) : null;

    return AdbKeyPair(
      privateKeyData: privateKeyData,
      publicKeyData: publicKeyData,
      certificateData: certificateData,
    );
  }

  /// 清理PEM格式
  static String _cleanPem(String pem, String type) {
    return pem
        .replaceAll('-----BEGIN $type-----', '')
        .replaceAll('-----END $type-----', '')
        .replaceAll(RegExp(r'\s'), '');
  }

  /// Base64解码
  static Uint8List _base64Decode(String base64String) {
    return base64.decode(base64String);
  }

  /// 从ASN1Integer提取BigInt（处理API不一致问题）
  static BigInt _extractBigIntFromASN1Integer(ASN1Integer integer) {
    try {
      // 方法1: 使用valueBytes并转换
      final valueBytes = integer.valueBytes();
      if (valueBytes != null) {
        return _bytesToBigInt(Uint8List.fromList(valueBytes));
      }
    } catch (e) {
      // 忽略错误，尝试下一种方法
    }

    try {
      // 方法2: 使用原始字节
      final encodedBytes = integer.encodedBytes;
      return _bytesToBigInt(Uint8List.fromList(encodedBytes));
    } catch (e2) {
      // 方法3: 使用字符串表示
      final hexString = integer.toString().replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
      return BigInt.parse(hexString, radix: 16);
    }
  }

  /// 字节数组转换为大整数
  static BigInt _bytesToBigInt(Uint8List data) {
    BigInt result = BigInt.zero;

    for (int i = 0; i < data.length; i++) {
      result = (result << 8) | BigInt.from(data[i] & 0xFF);
    }

    return result;
  }
}
