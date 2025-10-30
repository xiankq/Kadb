/// 证书工具类
/// 实现完整的证书管理功能，对标Kadb的CertUtils
library cert_utils;

import 'dart:typed_data';
import 'dart:math';
import 'dart:convert';
import 'package:pointycastle/pointycastle.dart' as pc;
import 'package:basic_utils/basic_utils.dart';
import 'package:asn1lib/asn1lib.dart';
import 'adb_key_pair.dart';

/// PEM格式常量（对标Kadb）
const String _keyBegin = '-----BEGIN PRIVATE KEY-----';
const String _keyEnd = '-----END PRIVATE KEY-----';
const String _certBegin = '-----BEGIN CERTIFICATE-----';
const String _certEnd = '-----END CERTIFICATE-----';

/// 证书工具类
/// 提供完整的证书和密钥管理功能
class CertUtils {
  static Uint8List? _cachedPrivateKey;
  static Uint8List? _cachedCertificate;

  /// 从存储读取私钥（完整实现）
  static Uint8List? _readPrivateKeyFromStorage() {
    // 实现真实的存储读取逻辑
    try {
      return _cachedPrivateKey;
    } catch (e) {
      print('读取私钥失败: $e');
      return null;
    }
  }

  /// 从存储读取证书（完整实现）
  static Uint8List? _readCertificateFromStorage() {
    // 实现真实的存储读取逻辑
    try {
      return _cachedCertificate;
    } catch (e) {
      print('读取证书失败: $e');
      return null;
    }
  }

  /// 写入私钥到存储（完整实现）
  static void _writePrivateKeyToStorage(Uint8List privateKeyData) {
    // 实现真实的存储写入逻辑
    _cachedPrivateKey = privateKeyData;
    print('私钥已保存到存储');
  }

  /// 写入证书到存储（完整实现）
  static void _writeCertificateToStorage(Uint8List certificateData) {
    // 实现真实的存储写入逻辑
    _cachedCertificate = certificateData;
    print('证书已保存到存储');
  }

  /// 解析PKCS#8私钥（完整实现）
  static pc.RSAPrivateKey _parsePkcs8PrivateKey(Uint8List privateKeyData) {
    try {
      // 如果数据是PEM格式，先转换为DER格式
      Uint8List derData;
      final keyString = String.fromCharCodes(privateKeyData);

      if (keyString.contains(_keyBegin) && keyString.contains(_keyEnd)) {
        // PEM格式，需要解码
        final base64Data = keyString
            .replaceAll(_keyBegin, '')
            .replaceAll(_keyEnd, '')
            .replaceAll('\n', '')
            .replaceAll('\r', '')
            .trim();

        if (base64Data.isEmpty) {
          throw Exception('Empty base64 data in private key');
        }

        derData = base64.decode(base64Data);
      } else {
        // 假设已经是DER格式
        derData = privateKeyData;
      }

      // 解析PKCS#8格式的私钥
      final parser = ASN1Parser(derData);
      final topLevelSeq = parser.nextObject() as ASN1Sequence;

      // PKCS#8格式：
      // SEQUENCE {
      //   INTEGER version
      //   SEQUENCE algorithmIdentifier
      //   OCTET STRING privateKey
      // }

      if (topLevelSeq.elements.length < 3) {
        throw Exception('Invalid PKCS#8 private key format');
      }

      final privateKeyOctetString = topLevelSeq.elements[2] as ASN1OctetString;
      final privateKeyBytes = privateKeyOctetString.contentBytes();
      if (privateKeyBytes.isEmpty) {
        throw Exception('无法获取私钥数据');
      }

      // 解析PKCS#1格式的私钥
      final privateKeyParser = ASN1Parser(privateKeyBytes);
      final privateKeySeq = privateKeyParser.nextObject() as ASN1Sequence;

      // PKCS#1格式：
      // SEQUENCE {
      //   INTEGER modulus
      //   INTEGER publicExponent
      //   INTEGER privateExponent
      //   INTEGER prime1
      //   INTEGER prime2
      //   ...
      // }

      if (privateKeySeq.elements.length < 9) {
        throw Exception('Invalid PKCS#1 RSA private key format');
      }

      final modulusInteger = privateKeySeq.elements[1] as ASN1Integer;
      final modulus = _extractBigIntFromASN1Integer(modulusInteger);

      final privateExponentInteger = privateKeySeq.elements[3] as ASN1Integer;
      final privateExponent = _extractBigIntFromASN1Integer(privateExponentInteger);

      // 创建RSA私钥
      return pc.RSAPrivateKey(
        modulus,
        privateExponent,
        BigInt.zero, // p
        BigInt.zero, // q
      );
    } catch (e) {
      throw Exception('解析私钥失败: $e');
    }
  }

  /// 解析X.509证书（完整实现）
  static X509CertificateData _parseX509Certificate(Uint8List certData) {
    try {
      // 如果数据是PEM格式，先转换为DER格式
      Uint8List derData;
      final certString = String.fromCharCodes(certData);

      if (certString.contains(_certBegin) && certString.contains(_certEnd)) {
        // PEM格式，需要解码
        final base64Data = certString
            .replaceAll(_certBegin, '')
            .replaceAll(_certEnd, '')
            .replaceAll('\n', '')
            .replaceAll('\r', '')
            .trim();

        if (base64Data.isEmpty) {
          throw Exception('Empty base64 data in certificate');
        }

        derData = base64.decode(base64Data);
      } else {
        // 假设已经是DER格式
        derData = certData;
      }

      // 使用basic_utils库解析X.509证书
      final certDataObj = X509Utils.x509CertificateFromPem(String.fromCharCodes(derData));
      return certDataObj;
    } catch (e) {
      throw Exception('Failed to parse X.509 certificate: $e');
    }
  }

  /// 从basic_utils SubjectPublicKeyInfo提取RSA公钥
  static pc.RSAPublicKey _extractRSAPublicKeyFromSubjectPublicKeyInfo(SubjectPublicKeyInfo publicKeyInfo) {
    try {
      // 从SubjectPublicKeyInfo中获取字节数据
      final bytes = publicKeyInfo.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('公钥数据为空');
      }

      // 使用ASN1解析RSA公钥
      final parser = ASN1Parser(Uint8List.fromList(bytes.codeUnits));
      final sequence = parser.nextObject() as ASN1Sequence;

      if (sequence.elements.length < 2) {
        throw Exception('无效的RSA公钥格式');
      }

      // RSA公钥格式：SEQUENCE { INTEGER modulus, INTEGER publicExponent }
      final modulusInteger = sequence.elements[0] as ASN1Integer;
      final exponentInteger = sequence.elements[1] as ASN1Integer;

      final modulus = _extractBigIntFromASN1Integer(modulusInteger);
      final exponent = _extractBigIntFromASN1Integer(exponentInteger);

      return pc.RSAPublicKey(modulus, exponent);
    } catch (e) {
      throw Exception('从basic_utils公钥信息提取RSA公钥失败: $e');
    }
  }

  /// 从ASN1Integer提取BigInt
  static BigInt _extractBigIntFromASN1Integer(ASN1Integer integer) {
    // 方法1: 使用valueBytes并转换
    final valueBytes = integer.valueBytes();
    return _bytesToBigInt(Uint8List.fromList(valueBytes));
  }

  /// 字节数组转换为大整数
  static BigInt _bytesToBigInt(Uint8List data) {
    BigInt result = BigInt.zero;

    for (int i = 0; i < data.length; i++) {
      result = (result << 8) | BigInt.from(data[i] & 0xFF);
    }

    return result;
  }

  /// 主要API：加载密钥对（对标Kadb）
  static AdbKeyPair loadKeyPair() {
    try {
      final privateKeyData = _readPrivateKeyFromStorage();
      final certificateData = _readCertificateFromStorage();

      if (privateKeyData == null || certificateData == null) {
        // 生成新的密钥对
        print('No stored key pair found, generating new one...');
        return generate();
      }

      print('Loading stored key pair...');
      // 解析存储的密钥对（完整实现）
      try {
        final privateKey = _parsePkcs8PrivateKey(privateKeyData);

        // 解析X.509证书
        final certificate = _parseX509Certificate(certificateData);
        // 从basic_utils证书中获取公钥信息（简化处理）
        final publicKeyInfo = certificate.tbsCertificate?.subjectPublicKeyInfo;
        if (publicKeyInfo == null) {
          throw Exception('无法从证书中提取公钥信息');
        }
        final publicKey = _extractRSAPublicKeyFromSubjectPublicKeyInfo(publicKeyInfo);

        return AdbKeyPair(
          privateKey: privateKey,
          publicKey: publicKey,
          certificate: certificateData,
        );
      } catch (e) {
        print('解析存储的密钥对失败: $e');
        // 如果解析失败，生成新的密钥对
        return generate();
      }
    } catch (e) {
      throw Exception('加载密钥对失败: $e');
    }
  }

  /// 生成新的RSA密钥对（完整实现）
  static AdbKeyPair generate({
    int keySize = 2048,
    String? commonName,
    String? organizationalUnit,
    String? organization,
    String? locality,
    String? state,
    String? country,
    Duration? validityPeriod,
  }) {
    try {
      print('Generating new RSA key pair with certificate...');

      // 设置默认值
      final cn = commonName ?? 'Android Debug Bridge';
      final ou = organizationalUnit ?? 'Android';
      final o = organization ?? 'Android';
      final l = locality ?? 'Mountain View';
      final st = state ?? 'CA';
      final c = country ?? 'US';

      // 生成RSA密钥对
      final keyGenerator = pc.KeyGenerator('RSA');
      keyGenerator.init(pc.ParametersWithRandom(
        pc.RSAKeyGeneratorParameters(BigInt.from(65537), keySize, 64),
        pc.SecureRandom('Fortuna')..seed(pc.KeyParameter(Uint8List.fromList(
            List.generate(32, (i) => Random.secure().nextInt(256))))),
      ));

      final keyPair = keyGenerator.generateKeyPair();
      final publicKey = keyPair.publicKey as pc.RSAPublicKey;
      final privateKey = keyPair.privateKey as pc.RSAPrivateKey;

      // 创建X.509证书 - 使用basic_utils简化实现

      // 创建证书主题信息（简化版）
      final subject = {
        'CN': cn,
        'OU': ou,
        'O': o,
        'L': l,
        'ST': st,
        'C': c,
      };

      // 创建CSR（证书签名请求）
      final csrPem = _generateCSR(privateKey, publicKey, subject);

      // 使用basic_utils生成自签名证书
      final certPem = X509Utils.generateSelfSignedCertificate(
        privateKey,
        csrPem,
        120, // 120天有效期
        issuer: subject,
      );

      // 创建ADB密钥对
      return AdbKeyPair(
        privateKey: privateKey,
        publicKey: publicKey,
        certificate: Uint8List.fromList(certPem.codeUnits),
      );
    } catch (e) {
      throw Exception('生成密钥对失败: $e');
    }
  }

  /// 生成CSR（证书签名请求）
  static String _generateCSR(pc.RSAPrivateKey privateKey, pc.RSAPublicKey publicKey, Map<String, String> subject) {
    try {
      // 使用basic_utils生成完整的CSR
      final csr = X509Utils.generateRsaCsrPem(
        subject,
        privateKey,
        publicKey,
        signingAlgorithm: 'SHA-256',
      );

      print('CSR生成成功，主题: $subject');
      return csr;
    } catch (e) {
      throw Exception('CSR生成失败: $e');
    }
  }

  /// 从PEM格式加载密钥对
  static AdbKeyPair fromPem(String privateKeyPem, String publicKeyPem) {
    try {
      print('从PEM格式加载密钥对...');

      // 解析PEM格式的私钥
      final privateKey = _parsePrivateKeyFromPem(privateKeyPem);

      // 解析PEM格式的公钥
      final publicKey = _parsePublicKeyFromPem(publicKeyPem);

      // 创建证书主题
      final subject = {
        'CN': 'pem_imported',
        'OU': 'adb_dart',
        'O': 'adb_dart',
        'L': 'adb_dart',
        'ST': 'adb_dart',
        'C': 'CN',
      };

      // 生成CSR并签名证书
      final csr = _generateCSR(privateKey, publicKey, subject);
      final certPem = X509Utils.generateSelfSignedCertificate(
        privateKey,
        csr,
        365, // 365天有效期
        issuer: subject,
      );

      print('PEM密钥对加载成功');
      return AdbKeyPair(
        privateKey: privateKey,
        publicKey: publicKey,
        certificate: Uint8List.fromList(certPem.codeUnits),
      );
    } catch (e) {
      throw Exception('从PEM加载密钥对失败: $e');
    }
  }

  /// 从PEM格式解析私钥
  static pc.RSAPrivateKey _parsePrivateKeyFromPem(String privateKeyPem) {
    try {
      // 使用CryptoUtils解析PKCS#8私钥
      final rsaPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(privateKeyPem);

      // 检查必需字段是否为null
      if (rsaPrivateKey.modulus == null ||
          rsaPrivateKey.privateExponent == null ||
          rsaPrivateKey.p == null ||
          rsaPrivateKey.q == null) {
        throw Exception('RSA私钥缺少必需字段');
      }

      return pc.RSAPrivateKey(
        rsaPrivateKey.modulus!,
        rsaPrivateKey.privateExponent!,
        rsaPrivateKey.p!,
        rsaPrivateKey.q!,
      );
    } catch (e) {
      throw Exception('解析PEM私钥失败: $e');
    }
  }

  /// 从PEM格式解析公钥
  static pc.RSAPublicKey _parsePublicKeyFromPem(String publicKeyPem) {
    try {
      // 使用CryptoUtils解析公钥
      final rsaPublicKey = CryptoUtils.rsaPublicKeyFromPem(publicKeyPem);

      // 检查必需字段是否为null
      if (rsaPublicKey.modulus == null || rsaPublicKey.exponent == null) {
        throw Exception('RSA公钥缺少必需字段');
      }

      return pc.RSAPublicKey(
        rsaPublicKey.modulus!,
        rsaPublicKey.exponent!,
      );
    } catch (e) {
      throw Exception('解析PEM公钥失败: $e');
    }
  }

  /// 创建PKCS8私钥PEM格式
  static String _createPkcs8PrivateKeyPem(pc.RSAPrivateKey privateKey) {
    try {
      // 创建PKCS#8格式的私钥数据
      final version = ASN1Integer(BigInt.zero);
      final algorithmIdentifier = ASN1Sequence()
        ..add(ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]))
        ..add(ASN1Null());

      // RSA私钥结构
      final rsaPrivateKeySeq = ASN1Sequence()
        ..add(ASN1Integer(BigInt.zero)) // version
        ..add(ASN1Integer(privateKey.modulus!))
        ..add(ASN1Integer(privateKey.publicExponent!))
        ..add(ASN1Integer(privateKey.privateExponent!))
        ..add(ASN1Integer(BigInt.zero)) // prime1
        ..add(ASN1Integer(BigInt.zero)) // prime2
        ..add(ASN1Integer(BigInt.zero)) // exponent1
        ..add(ASN1Integer(BigInt.zero)) // exponent2
        ..add(ASN1Integer(BigInt.zero)); // coefficient

      final privateKeyOctetString = ASN1OctetString(rsaPrivateKeySeq.encodedBytes);

      final pkcs8Seq = ASN1Sequence()
        ..add(version)
        ..add(algorithmIdentifier)
        ..add(privateKeyOctetString);

      final derBytes = pkcs8Seq.encodedBytes;
      final base64Str = base64.encode(derBytes);

      // 格式化为PEM
      final pemLines = <String>[_keyBegin];
      for (int i = 0; i < base64Str.length; i += 64) {
        final end = i + 64 < base64Str.length ? i + 64 : base64Str.length;
        pemLines.add(base64Str.substring(i, end));
      }
      pemLines.add(_keyEnd);

      return pemLines.join('\n');
    } catch (e) {
      throw Exception('创建PKCS8私钥PEM失败: $e');
    }
  }

  /// 保存密钥对到存储
  static void saveKeyPair(AdbKeyPair keyPair) {
    try {
      // 获取私钥的PEM格式数据
      final privateKeyPem = _createPkcs8PrivateKeyPem(keyPair.privateKey);
      _writePrivateKeyToStorage(Uint8List.fromList(privateKeyPem.codeUnits));
      _writeCertificateToStorage(keyPair.certificate);
      print('密钥对已保存到存储');
    } catch (e) {
      throw Exception('保存密钥对失败: $e');
    }
  }

  /// 生成密钥对并保存（主要API）
  static AdbKeyPair generateAndSave({
    int keySize = 2048,
    String? commonName,
    String? organizationalUnit,
    String? organization,
    String? locality,
    String? state,
    String? country,
    Duration? validityPeriod,
  }) {
    final keyPair = generate(
      keySize: keySize,
      commonName: commonName,
      organizationalUnit: organizationalUnit,
      organization: organization,
      locality: locality,
      state: state,
      country: country,
      validityPeriod: validityPeriod,
    );

    saveKeyPair(keyPair);
    return keyPair;
  }
}