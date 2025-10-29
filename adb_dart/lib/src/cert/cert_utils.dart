/// 证书和密钥工具类
///
/// 提供RSA密钥对生成、证书创建和密钥管理功能
library;

import 'dart:math';
import 'dart:typed_data';
import 'dart:io';

import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';

import 'adb_key_pair.dart';
import 'android_pubkey.dart';

/// 证书工具类
class CertUtils {
  /// 生成RSA密钥对
  ///
  /// [keySize] 密钥大小，通常为2048位
  /// [deviceName] 设备名称，用于公钥编码
  static Future<AdbKeyPair> generateKeyPair({
    int keySize = 2048,
    String deviceName = 'adb_dart',
  }) async {
    try {
      // 使用pointycastle生成RSA密钥对
      final keyParams =
          RSAKeyGeneratorParameters(BigInt.from(65537), keySize, 12);
      final secureRandom = FortunaRandom();
      final random = Random.secure();
      final seed =
          Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
      secureRandom.seed(KeyParameter(seed));

      final params = ParametersWithRandom(keyParams, secureRandom);
      final keyGenerator = RSAKeyGenerator();
      keyGenerator.init(params);

      final keyPair = keyGenerator.generateKeyPair();
      final publicKey = keyPair.publicKey as RSAPublicKey;
      final privateKey = keyPair.privateKey as RSAPrivateKey;

      // 编码公钥为X.509格式
      final publicKeyData = _encodeX509PublicKey(publicKey);

      // 编码私钥为PKCS#8格式
      final privateKeyData = _encodePkcs8PrivateKey(privateKey);

      // 生成自签名证书
      final certificateData =
          _generateSelfSignedCertificate(publicKey, privateKey, deviceName);

      return AdbKeyPair(
        privateKeyData: privateKeyData,
        publicKeyData: publicKeyData,
        certificateData: certificateData,
      );
    } catch (e) {
      throw StateError('生成RSA密钥对失败: $e');
    }
  }

  /// 从PEM文件加载密钥对
  static Future<AdbKeyPair> loadKeyPairFromPem({
    required String privateKeyPem,
    String? publicKeyPem,
    String? certificatePem,
  }) async {
    // 清理PEM格式
    final cleanedPrivateKey = _cleanPem(privateKeyPem, 'PRIVATE KEY');
    final cleanedPublicKey =
        publicKeyPem != null ? _cleanPem(publicKeyPem, 'PUBLIC KEY') : null;
    final cleanedCertificate = certificatePem != null
        ? _cleanPem(certificatePem, 'CERTIFICATE')
        : null;

    // Base64解码
    final privateKeyData = _base64Decode(cleanedPrivateKey);
    final publicKeyData = cleanedPublicKey != null
        ? _base64Decode(cleanedPublicKey)
        : _derivePublicKey(privateKeyData);
    final certificateData =
        cleanedCertificate != null ? _base64Decode(cleanedCertificate) : null;

    return AdbKeyPair(
      privateKeyData: privateKeyData,
      publicKeyData: publicKeyData,
      certificateData: certificateData,
    );
  }

  /// 从文件加载密钥对
  static Future<AdbKeyPair> loadKeyPairFromFiles({
    required String privateKeyFile,
    String? publicKeyFile,
    String? certificateFile,
  }) async {
    try {
      final privateKeyPem = await File(privateKeyFile).readAsString();
      final publicKeyPem = publicKeyFile != null
          ? await File(publicKeyFile).readAsString()
          : null;
      final certificatePem = certificateFile != null
          ? await File(certificateFile).readAsString()
          : null;

      return await loadKeyPairFromPem(
        privateKeyPem: privateKeyPem,
        publicKeyPem: publicKeyPem,
        certificatePem: certificatePem,
      );
    } catch (e) {
      throw StateError('从文件加载密钥对失败: $e');
    }
  }

  /// 保存密钥对到PEM格式
  static Future<void> saveKeyPairToPem({
    required AdbKeyPair keyPair,
    required String privateKeyOutput,
    String? publicKeyOutput,
    String? certificateOutput,
  }) async {
    // 编码私钥
    final privateKeyPem = _formatPem(
      _base64Encode(keyPair.privateKeyData),
      'PRIVATE KEY',
    );

    // 保存私钥
    await File(privateKeyOutput).writeAsString(privateKeyPem);

    if (publicKeyOutput != null) {
      // 编码公钥
      final publicKeyPem = _formatPem(
        _base64Encode(keyPair.publicKeyData),
        'PUBLIC KEY',
      );

      // 保存公钥
      await File(publicKeyOutput).writeAsString(publicKeyPem);
    }

    if (certificateOutput != null && keyPair.certificateData != null) {
      // 编码证书
      final certificatePem = _formatPem(
        _base64Encode(keyPair.certificateData!),
        'CERTIFICATE',
      );

      // 保存证书
      await File(certificateOutput).writeAsString(certificatePem);
    }
  }

  /// 验证密钥对的有效性
  static bool isValidKeyPair(AdbKeyPair keyPair) {
    if (keyPair.privateKeyData.isEmpty || keyPair.publicKeyData.isEmpty) {
      return false;
    }

    // 检查密钥大小
    if (keyPair.publicKeyData.length < 100) {
      return false; // 公钥数据太短
    }

    // 验证公钥格式
    return AndroidPubkey.isValidPublicKey(keyPair.publicKeyData);
  }

  /// 获取密钥对的指纹信息
  static Map<String, dynamic> getKeyPairInfo(AdbKeyPair keyPair) {
    return {
      'keySize': keyPair.keySize,
      'publicKeyFingerprint': keyPair.getPublicKeyFingerprint(),
      'hasCertificate': keyPair.certificateData != null,
      'isValid': isValidKeyPair(keyPair),
    };
  }

  /// 生成自签名证书
  static Future<Uint8List> generateSelfSignedCertificate({
    required Uint8List publicKeyData,
    required Uint8List privateKeyData,
    required String deviceName,
    Duration? validityPeriod,
  }) async {
    try {
      // 解析公钥和私钥
      final publicKey = _parseX509PublicKey(publicKeyData);
      final privateKey = _parsePkcs8PrivateKey(privateKeyData);

      // 使用已有的证书生成函数
      return _generateSelfSignedCertificate(publicKey, privateKey, deviceName);
    } catch (e) {
      throw StateError('生成自签名证书失败: $e');
    }
  }

  /// 验证证书有效性
  static bool isValidCertificate(Uint8List certificateData) {
    // 检查证书格式和长度
    if (certificateData.isEmpty || certificateData.length < 100) {
      return false;
    }

    try {
      // 尝试解析证书
      final asn1Parser = ASN1Parser(certificateData);
      final certSeq = asn1Parser.nextObject() as ASN1Sequence;

      // 检查基本的证书结构
      return certSeq.elements.length >=
          3; // tbsCertificate, signatureAlgorithm, signatureValue
    } catch (e) {
      return false;
    }
  }

  /// 清理PEM格式
  static String _cleanPem(String pem, String type) {
    return pem
        .replaceAll('-----BEGIN $type-----', '')
        .replaceAll('-----END $type-----', '')
        .replaceAll(RegExp(r'\s'), '');
  }

  /// 格式化PEM
  static String _formatPem(String base64Data, String type) {
    return '-----BEGIN $type-----\n$base64Data\n-----END $type-----';
  }

  /// Base64编码
  static Uint8List _base64Encode(Uint8List data) {
    final base64String = base64.encode(data);
    return Uint8List.fromList(base64String.codeUnits);
  }

  /// Base64解码
  static Uint8List _base64Decode(String base64String) {
    return Uint8List.fromList(base64Decode(base64String));
  }

  /// 从私钥推导公钥
  static Uint8List _derivePublicKey(Uint8List privateKeyData) {
    try {
      final privateKey = _parsePkcs8PrivateKey(privateKeyData);
      final publicKey = RSAPublicKey(
        privateKey.modulus,
        BigInt.from(65537), // 常用的RSA公钥指数
      );
      return _encodeX509PublicKey(publicKey);
    } catch (e) {
      throw StateError('从私钥推导公钥失败: $e');
    }
  }

  /// 编码X.509公钥
  static Uint8List _encodeX509PublicKey(RSAPublicKey publicKey) {
    try {
      // 创建PKCS#1格式的公钥
      final publicKeySeq = ASN1Sequence();
      publicKeySeq.add(ASN1Integer(publicKey.modulus));
      publicKeySeq.add(ASN1Integer(publicKey.exponent));

      final publicKeyBytes = publicKeySeq.encodedBytes;

      // 创建X.509格式的公钥
      final algorithmIdSeq = ASN1Sequence();
      algorithmIdSeq.add(ASN1ObjectIdentifier.fromComponentString(
          '1.2.840.113549.1.1.1')); // RSA
      algorithmIdSeq.add(ASN1Null());

      final publicKeyBitString = ASN1BitString(publicKeyBytes);

      final x509Seq = ASN1Sequence();
      x509Seq.add(algorithmIdSeq);
      x509Seq.add(publicKeyBitString);

      return x509Seq.encodedBytes;
    } catch (e) {
      throw StateError('编码X.509公钥失败: $e');
    }
  }

  /// 编码PKCS#8私钥
  static Uint8List _encodePkcs8PrivateKey(RSAPrivateKey privateKey) {
    try {
      // 创建PKCS#1格式的私钥
      final privateKeySeq = ASN1Sequence();
      privateKeySeq.add(ASN1Integer(BigInt.zero)); // version
      privateKeySeq.add(ASN1Integer(privateKey.modulus));
      privateKeySeq.add(ASN1Integer(privateKey.exponent));
      privateKeySeq.add(ASN1Integer(privateKey.privateExponent));
      privateKeySeq.add(ASN1Integer(privateKey.p ?? BigInt.zero));
      privateKeySeq.add(ASN1Integer(privateKey.q ?? BigInt.zero));
      privateKeySeq.add(ASN1Integer(BigInt.zero)); // d mod (p-1)
      privateKeySeq.add(ASN1Integer(BigInt.zero)); // d mod (q-1)
      privateKeySeq.add(ASN1Integer(BigInt.zero)); // q^(-1) mod p

      final privateKeyBytes = privateKeySeq.encodedBytes;

      // 创建PKCS#8格式的私钥
      final algorithmIdSeq = ASN1Sequence();
      algorithmIdSeq.add(ASN1ObjectIdentifier.fromComponentString(
          '1.2.840.113549.1.1.1')); // RSA
      algorithmIdSeq.add(ASN1Null());

      final privateKeyOctetString = ASN1OctetString(privateKeyBytes);

      final pkcs8Seq = ASN1Sequence();
      pkcs8Seq.add(ASN1Integer(BigInt.zero)); // version
      pkcs8Seq.add(algorithmIdSeq);
      pkcs8Seq.add(privateKeyOctetString);

      return pkcs8Seq.encodedBytes;
    } catch (e) {
      throw StateError('编码PKCS#8私钥失败: $e');
    }
  }

  /// 生成自签名证书
  static Uint8List _generateSelfSignedCertificate(
    RSAPublicKey publicKey,
    RSAPrivateKey privateKey,
    String deviceName,
  ) {
    try {
      // 证书有效期：从现在开始120天
      final notBefore = DateTime.now();
      final notAfter = notBefore.add(Duration(days: 120));

      // 创建证书序列
      final certSeq = ASN1Sequence();

      // tbsCertificate
      final tbsCertSeq = ASN1Sequence();

      // version (v3)
      final versionContext = ASN1Sequence(tag: 0xA0);
      versionContext.add(ASN1Integer(BigInt.two));
      tbsCertSeq.add(versionContext);

      // serial number
      final random = Random.secure();
      final serialNumber = BigInt.from(random.nextInt(1 << 32));
      tbsCertSeq.add(ASN1Integer(serialNumber));

      // signature algorithm
      final sigAlgSeq = ASN1Sequence();
      sigAlgSeq.add(ASN1ObjectIdentifier.fromComponentString(
          '1.2.840.113549.1.1.11')); // SHA256withRSA
      sigAlgSeq.add(ASN1Null());
      tbsCertSeq.add(sigAlgSeq);

      // issuer
      final issuerSeq = ASN1Sequence();
      issuerSeq.add(ASN1Set()
        ..add(ASN1Sequence()
          ..add(ASN1ObjectIdentifier.fromComponentString('2.5.4.3')) // CN
          ..add(ASN1PrintableString(deviceName))));
      tbsCertSeq.add(issuerSeq);

      // validity
      final validitySeq = ASN1Sequence();
      validitySeq.add(ASN1UtcTime(notBefore));
      validitySeq.add(ASN1UtcTime(notAfter));
      tbsCertSeq.add(validitySeq);

      // subject (same as issuer for self-signed)
      tbsCertSeq.add(issuerSeq);

      // subject public key info
      final subjectPublicKeyInfoSeq = ASN1Sequence();

      // algorithm
      final keyAlgSeq = ASN1Sequence();
      keyAlgSeq.add(ASN1ObjectIdentifier.fromComponentString(
          '1.2.840.113549.1.1.1')); // RSA
      keyAlgSeq.add(ASN1Null());

      // subject public key
      final publicKeySeq = ASN1Sequence();
      publicKeySeq.add(ASN1Integer(publicKey.modulus));
      publicKeySeq.add(ASN1Integer(publicKey.exponent));

      final publicKeyBitString = ASN1BitString(publicKeySeq.encodedBytes);
      subjectPublicKeyInfoSeq.add(publicKeyBitString);

      tbsCertSeq.add(subjectPublicKeyInfoSeq);

      certSeq.add(tbsCertSeq);

      // signature algorithm (same as above)
      certSeq.add(sigAlgSeq);

      // signature value
      final tbsCertBytes = tbsCertSeq.encodedBytes;
      final signature = _signData(tbsCertBytes, privateKey);
      final signatureBitString = ASN1BitString(signature);
      certSeq.add(signatureBitString);

      return certSeq.encodedBytes;
    } catch (e) {
      throw StateError('生成自签名证书失败: $e');
    }
  }

  /// 解析X.509公钥
  static RSAPublicKey _parseX509PublicKey(Uint8List publicKeyData) {
    try {
      final asn1Parser = ASN1Parser(publicKeyData);
      final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

      if (topLevelSeq.elements.length != 2) {
        throw StateError('无效的X.509公钥格式');
      }

      // 跳过算法标识符部分
      final publicKeyBitString = topLevelSeq.elements[1] as ASN1BitString;
      final publicKeyData = publicKeyBitString.stringValue;

      // 解析RSA公钥结构
      final publicKeyParser = ASN1Parser(publicKeyData);
      final publicKeySeq = publicKeyParser.nextObject() as ASN1Sequence;

      if (publicKeySeq.elements.length != 2) {
        throw StateError('无效的RSA公钥格式');
      }

      final modulus = (publicKeySeq.elements[0] as ASN1Integer).integerValue;
      final exponent = (publicKeySeq.elements[1] as ASN1Integer).integerValue;

      return RSAPublicKey(modulus, exponent);
    } catch (e) {
      throw StateError('解析X.509公钥失败: $e');
    }
  }

  /// 解析PKCS#8私钥
  static RSAPrivateKey _parsePkcs8PrivateKey(Uint8List privateKeyData) {
    try {
      final asn1Parser = ASN1Parser(privateKeyData);
      final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

      if (topLevelSeq.elements.length != 3) {
        throw StateError('无效的PKCS#8私钥格式');
      }

      // 跳过版本号
      // 跳过算法标识符
      final privateKeyOctetString = topLevelSeq.elements[2] as ASN1OctetString;
      final privateKeyData = privateKeyOctetString.valueBytes;

      // 解析PKCS#1 RSA私钥结构
      final privateKeyParser = ASN1Parser(privateKeyData);
      final privateKeySeq = privateKeyParser.nextObject() as ASN1Sequence;

      if (privateKeySeq.elements.length < 9) {
        throw StateError('无效的PKCS#1 RSA私钥格式');
      }

      final version = (privateKeySeq.elements[0] as ASN1Integer).integerValue;
      if (version != BigInt.zero) {
        throw StateError('不支持的私钥版本');
      }

      final modulus = (privateKeySeq.elements[1] as ASN1Integer).integerValue;
      final publicExponent =
          (privateKeySeq.elements[2] as ASN1Integer).integerValue;
      final privateExponent =
          (privateKeySeq.elements[3] as ASN1Integer).integerValue;
      final p = (privateKeySeq.elements[4] as ASN1Integer).integerValue;
      final q = (privateKeySeq.elements[5] as ASN1Integer).integerValue;
      final dP = (privateKeySeq.elements[6] as ASN1Integer).integerValue;
      final dQ = (privateKeySeq.elements[7] as ASN1Integer).integerValue;
      final qInv = (privateKeySeq.elements[8] as ASN1Integer).integerValue;

      return RSAPrivateKey(
        modulus,
        privateExponent,
        p,
        q,
        privateExponent,
        dP,
        dQ,
        qInv,
      );
    } catch (e) {
      throw StateError('解析PKCS#8私钥失败: $e');
    }
  }

  /// 签名数据
  static Uint8List _signData(Uint8List data, RSAPrivateKey privateKey) {
    try {
      final signer = RSASigner(SHA256Digest(), PKCS1Encoding(null));
      signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

      final signature = signer.generateSignature(data);
      return signature.bytes;
    } catch (e) {
      throw StateError('签名数据失败: $e');
    }
  }
}
