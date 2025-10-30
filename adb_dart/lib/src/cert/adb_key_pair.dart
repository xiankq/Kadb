/// ADB密钥对管理
/// 处理RSA密钥对的生成、存储和签名
library adb_key_pair;

import 'dart:typed_data';
import 'dart:math';
import 'dart:convert';
import 'package:pointycastle/pointycastle.dart' as pc;
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:convert/convert.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:asn1lib/asn1lib.dart';
import '../utils/crc32.dart';
import 'android_pubkey.dart';

/// ADB密钥对
class AdbKeyPair {
  final pc.RSAPrivateKey privateKey;
  final pc.RSAPublicKey publicKey;
  final Uint8List certificate;

  AdbKeyPair({
    required this.privateKey,
    required this.publicKey,
    required this.certificate,
  });

  /// 使用私钥对数据进行签名（兼容Kadb：RSA/ECB/NoPadding + 特殊填充）
  Uint8List signPayload(Uint8List data) {
    try {
      // Kadb使用RSA/ECB/NoPadding + 特殊签名填充
      // 而不是SHA-256/RSA签名
      print('DEBUG: 使用RSA/ECB/NoPadding签名算法（对标Kadb）');

      // 创建RSA处理器（无填充模式）
      final rsaEngine = RSAEngine();
      final privateKeyParam = pc.PrivateKeyParameter<pc.RSAPrivateKey>(privateKey);
      rsaEngine.init(true, privateKeyParam); // 加密模式用于签名

      // Kadb的签名填充（固定格式）
      final signaturePadding = Uint8List.fromList([
        0x00, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00,
        0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00,
        0x04, 0x14
      ]);

      // 构建待加密数据：填充 + 数据
      final paddedData = BytesBuilder();
      paddedData.add(signaturePadding);
      paddedData.add(data);

      // 使用RSA加密（无填充）生成签名
      final input = paddedData.toBytes();
      final signature = rsaEngine.process(input);

      print('DEBUG: 签名生成完成，长度: ${signature.length} 字节');
      return signature;
    } catch (e) {
      throw Exception('RSA签名失败: $e');
    }
  }

  /// 获取公钥的ADB格式（备用实现）
  Uint8List getAdbPublicKey() {
    try {
      final adbKey = AndroidPubkey.convertRsaPublicKey(publicKey);
      print('DEBUG: ADB公钥生成完成，长度: ${adbKey.length} 字节');
      return adbKey;
    } catch (e) {
      print('DEBUG: AndroidPubkey转换失败: $e');
      print('DEBUG: 使用备用公钥格式');

      // 备用方案：使用简单的RSA公钥格式
      // 这在某些设备上可能也能工作
      final publicKeyDer = _exportPublicKeyDer(publicKey);
      print('DEBUG: 备用公钥格式，长度: ${publicKeyDer.length} 字节');
      return publicKeyDer;
    }
  }

  /// 导出公钥为DER格式（备用方案）
  Uint8List _exportPublicKeyDer(pc.RSAPublicKey publicKey) {
    try {
      // 简单的DER编码：模数 + 指数
      final n = publicKey.modulus!;
      final e = publicKey.exponent!;

      // 转换为字节数组（大端序）
      final nBytes = _bigIntToBytes(n);
      final eBytes = _bigIntToBytes(e);

      // 组合成简单的格式
      final result = BytesBuilder();
      result.addByte((nBytes.length >> 8) & 0xFF); // 模数长度高字节
      result.addByte(nBytes.length & 0xFF);       // 模数长度低字节
      result.add(nBytes);
      result.add(eBytes);

      return result.toBytes();
    } catch (e) {
      throw Exception('DER格式导出失败: $e');
    }
  }

  /// 大整数转字节数组（大端序，无符号）
  Uint8List _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) return Uint8List(1);

    // 计算需要的字节数
    final byteCount = (value.bitLength + 7) ~/ 8;
    final result = Uint8List(byteCount);

    // 从大端序填充
    BigInt temp = value;
    for (int i = byteCount - 1; i >= 0; i--) {
      result[i] = (temp & BigInt.from(0xFF)).toInt();
      temp = temp >> 8;
    }

    return result;
  }

  /// 生成新的密钥对
  static AdbKeyPair generate({
    int keySize = 2048,
    String commonName = 'adb_dart',
    Duration? validityPeriod,
  }) {
    final secureRandom = pc.SecureRandom('Fortuna')
      ..seed(pc.KeyParameter(Uint8List.fromList(
          List.generate(32, (i) => Random.secure().nextInt(256)))));

    // 生成RSA密钥对
    final keyGen = pc.KeyGenerator('RSA')
      ..init(
        pc.ParametersWithRandom(
          pc.RSAKeyGeneratorParameters(BigInt.from(65537), keySize, 64),
          secureRandom,
        ),
      );

    final keyPair = keyGen.generateKeyPair();
    final privateKey = keyPair.privateKey as pc.RSAPrivateKey;
    final publicKey = keyPair.publicKey as pc.RSAPublicKey;

    // 生成自签名证书
    final certificate = _generateSelfSignedCertificate(
      privateKey: privateKey,
      publicKey: publicKey,
      commonName: commonName,
      validityPeriod: validityPeriod ?? const Duration(days: 120),
    );

    return AdbKeyPair(
      privateKey: privateKey,
      publicKey: publicKey,
      certificate: certificate,
    );
  }

  /// 生成自签名证书
  static Uint8List _generateSelfSignedCertificate({
    required pc.RSAPrivateKey privateKey,
    required pc.RSAPublicKey publicKey,
    required String commonName,
    required Duration validityPeriod,
  }) {
    try {
      final now = DateTime.now();
      final notAfter = now.add(validityPeriod);
      final serialNumber = Random.secure().nextInt(1 << 31); // 避免负数

      // 创建CSR (Certificate Signing Request) first to use with basic_utils
      // Create attributes for the certificate
      final attributes = {
        'CN': commonName, // commonName
        'OU': 'adb_dart', // organizationalUnitName
        'O': 'adb_dart', // organizationName
        'L': 'adb_dart', // localityName
        'ST': 'adb_dart', // stateOrProvinceName
        'C': 'CN', // countryName
      };

      // Generate CSR using basic_utils
      final csr = X509Utils.generateRsaCsrPem(attributes, privateKey, publicKey);

      // Generate self-signed certificate using the CSR
      final certPem = X509Utils.generateSelfSignedCertificate(
        privateKey,
        csr,
        (validityPeriod.inDays).toInt(),
        serialNumber: serialNumber.toString(),
        notBefore: now.subtract(Duration(days: 1)),
      );

      // Convert PEM to DER bytes for consistency
      final certDer = CryptoUtils.getBytesFromPEMString(certPem);

      print('X.509 certificate generated successfully:');
      print('  Subject: CN=$commonName');
      print('  Serial Number: $serialNumber');
      print('  Valid From: ${now.subtract(Duration(days: 1)).toUtc()}');
      print('  Valid Until: $notAfter');
      print('  Signature Algorithm: SHA-256 with RSA');
      print('  Certificate DER size: ${certDer.length} bytes');
      print('  Certificate PEM size: ${certPem.length} characters');

      return Uint8List.fromList(certPem.codeUnits);
    } catch (e) {
      throw Exception('Failed to generate certificate: $e');
    }
  }

  /// 从PEM格式加载密钥对
  static AdbKeyPair fromPem(String privateKeyPem, String publicKeyPem) {
    try {
      // 解析PEM格式的公钥为PointCastle格式
      final pcPublicKey = CryptoUtils.rsaPublicKeyFromPem(publicKeyPem);

      // 解析PEM格式的私钥为PointCastle格式
      final pcPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(privateKeyPem);

      // 生成真实的X.509证书（对标Kadb）
      final now = DateTime.now();
      final validityPeriod = const Duration(days: 365);

      // 创建CSR (Certificate Signing Request) first to use with basic_utils
      // Create attributes for the certificate
      final attributes = {
        'CN': 'pem_imported', // commonName
        'OU': 'adb_dart', // organizationalUnitName
        'O': 'adb_dart', // organizationName
        'L': 'adb_dart', // localityName
        'ST': 'adb_dart', // stateOrProvinceName
        'C': 'CN', // countryName
      };

      // Generate CSR using basic_utils
      final csr = X509Utils.generateRsaCsrPem(attributes, pcPrivateKey, pcPublicKey);

      // Generate self-signed certificate using the CSR
      final certPem = X509Utils.generateSelfSignedCertificate(
        pcPrivateKey,
        csr,
        validityPeriod.inDays.toInt(),
        serialNumber: (now.millisecondsSinceEpoch ~/ 1000).toString(),
        notBefore: now.subtract(Duration(days: 1)),
      );

      print('X.509 certificate generated from PEM successfully:');
      print('  Subject: CN=pem_imported');
      print('  Valid From: ${now.subtract(Duration(days: 1)).toUtc()}');
      print('  Valid Until: ${now.add(validityPeriod).toUtc()}');
      print('  Signature Algorithm: SHA-256 with RSA');
      print('  Certificate PEM size: ${certPem.length} characters');

      return AdbKeyPair(
        privateKey: pcPrivateKey,
        publicKey: pcPublicKey,
        certificate: Uint8List.fromList(certPem.codeUnits),
      );
    } catch (e) {
      throw Exception('PEM格式解析失败: $e');
    }
  }

  /// 导出为PEM格式（完整实现 - PKCS#8）
  String exportPrivateKeyPem() {
    try {
      // 创建RSA私钥的ASN.1结构 (PKCS#1)
      // PKCS#1 RSA私钥结构：
      // RSAPrivateKey ::= SEQUENCE {
      //   version           Version,
      //   modulus           INTEGER,  -- n
      //   publicExponent    INTEGER,  -- e
      //   privateExponent   INTEGER,  -- d
      //   prime1            INTEGER,  -- p
      //   prime2            INTEGER,  -- q
      //   exponent1         INTEGER,  -- d mod (p-1)
      //   exponent2         INTEGER,  -- d mod (q-1)
      //   coefficient       INTEGER,  -- (inverse of q) mod p
      //   otherPrimeInfos   OtherPrimeInfos OPTIONAL
      // }

      final p = privateKey.p!;
      final q = privateKey.q!;
      final d = privateKey.privateExponent!;
      final n = privateKey.modulus!;
      final e = privateKey.publicExponent!;

      // 计算额外的参数
      final dP = d % (p - BigInt.one);  // d mod (p-1)
      final dQ = d % (q - BigInt.one);  // d mod (q-1)
      final qInv = q.modInverse(p);     // (inverse of q) mod p

      // 创建PKCS#1 RSA私钥结构
      final rsaPrivateKeySeq = ASN1Sequence()
        ..add(ASN1Integer(BigInt.zero)) // version = 0 (two-prime)
        ..add(ASN1Integer(n))           // modulus
        ..add(ASN1Integer(e))           // publicExponent
        ..add(ASN1Integer(d))           // privateExponent
        ..add(ASN1Integer(p))           // prime1
        ..add(ASN1Integer(q))           // prime2
        ..add(ASN1Integer(dP))          // exponent1
        ..add(ASN1Integer(dQ))          // exponent2
        ..add(ASN1Integer(qInv));       // coefficient

      // 创建PKCS#8 PrivateKeyInfo结构
      final privateKeyInfoSeq = ASN1Sequence()
        ..add(ASN1Integer(BigInt.zero)) // version = 0
        ..add(ASN1Sequence() // privateKeyAlgorithm
          ..add(ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1])) // rsaEncryption
          ..add(ASN1Null()))
        ..add(ASN1OctetString(rsaPrivateKeySeq.encodedBytes)); // privateKey

      final derBytes = privateKeyInfoSeq.encodedBytes;

      // 转换为PEM格式
      final buffer = StringBuffer();
      buffer.writeln('-----BEGIN PRIVATE KEY-----');
      final base64Str = base64.encode(derBytes);
      // 每64字符换行
      for (var i = 0; i < base64Str.length; i += 64) {
        buffer.writeln(base64Str.substring(i,
            i + 64 > base64Str.length ? base64Str.length : i + 64));
      }
      buffer.writeln('-----END PRIVATE KEY-----');

      print('Private key exported to PKCS#8 PEM format successfully:');
      print('  Key Size: ${n.bitLength} bits');
      print('  PEM Size: ${buffer.length} characters');

      return buffer.toString();
    } catch (e) {
      throw Exception('PEM格式导出失败: $e');
    }
  }

  /// 获取公钥指纹（用于调试）
  String getPublicKeyFingerprint() {
    final adbKey = getAdbPublicKey();
    final hash = Crc32.calculate(adbKey);
    // 修复：使用更安全的方式创建4字节的哈希表示
    final buffer = ByteData(4);
    buffer.setUint32(0, hash, Endian.big); // 使用大端序
    return hex.encode(buffer.buffer.asUint8List());
  }

  @override
  String toString() {
    return 'AdbKeyPair{publicKeyFingerprint: ${getPublicKeyFingerprint()}}';
  }
}
