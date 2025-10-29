/// ADB密钥对管理
/// 处理RSA密钥对的生成、存储和签名
library adb_key_pair;

import 'dart:typed_data';
import 'dart:math';
import 'dart:convert';
import 'package:pointycastle/pointycastle.dart' as pc;
import 'package:convert/convert.dart';
import 'package:x509_plus/x509.dart';
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

  /// 使用私钥对数据进行签名
  Uint8List signPayload(Uint8List data) {
    try {
      // 创建签名器
      final signer = pc.Signer('SHA-1/RSA')
        ..init(true, pc.PrivateKeyParameter<pc.RSAPrivateKey>(privateKey));

      // 对数据进行签名
      final signature = signer.generateSignature(data) as pc.RSASignature;
      return signature.bytes; // 返回签名的字节数据
    } catch (e) {
      throw Exception('Failed to sign payload: $e');
    }
  }

  /// 获取公钥的ADB格式
  Uint8List getAdbPublicKey() {
    return AndroidPubkey.convertRsaPublicKey(publicKey);
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
    // 实现真实的X.509证书生成
    try {
      final now = DateTime.now();
      final notAfter = now.add(validityPeriod);
      final serialNumber = Random.secure().nextInt(1 << 31); // 避免负数

      // 转换PointCastle公钥为crypto_keys格式
      final rsaPublicKey = RsaPublicKey(
        modulus: publicKey.modulus!,
        exponent: publicKey.exponent!,
      );

      // 构建完整的证书主题（对标Kadb）
      final subject = Name([
        {ObjectIdentifier([2, 5, 4, 3]): commonName}, // commonName
        {ObjectIdentifier([2, 5, 4, 11]): 'adb_dart'}, // organizationalUnitName
        {ObjectIdentifier([2, 5, 4, 10]): 'adb_dart'}, // organizationName
        {ObjectIdentifier([2, 5, 4, 7]): 'adb_dart'}, // localityName
        {ObjectIdentifier([2, 5, 4, 8]): 'adb_dart'}, // stateOrProvinceName
        {ObjectIdentifier([2, 5, 4, 6]): 'CN'}, // countryName
      ]);

      // 创建算法标识符
      final rsaEncryptionOid = ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]);
      final sha256WithRSAEncryptionOid = ObjectIdentifier([1, 2, 840, 113549, 1, 1, 11]);

      // 创建TbsCertificate（待签名证书）
      final tbsCertificate = TbsCertificate(
        version: 2, // X.509 v3 (版本号从0开始: 0=v1, 1=v2, 2=v3)
        serialNumber: serialNumber,
        signature: AlgorithmIdentifier(sha256WithRSAEncryptionOid, null),
        issuer: subject, // 自签名证书，颁发者和主题相同
        validity: Validity(
          notBefore: now.subtract(Duration(days: 1)).toUtc(), // 提前一天生效
          notAfter: notAfter.toUtc(),
        ),
        subject: subject,
        subjectPublicKeyInfo: SubjectPublicKeyInfo(
          AlgorithmIdentifier(rsaEncryptionOid, null),
          rsaPublicKey,
        ),
      );

      // 序列化TBSCertificate进行签名
      final tbsBytes = tbsCertificate.toAsn1().encodedBytes;

      // 使用私钥进行真实签名（SHA-256 + RSA）
      final signer = pc.Signer('SHA-256/RSA')
        ..init(true, pc.PrivateKeyParameter<pc.RSAPrivateKey>(privateKey));

      final signature = signer.generateSignature(tbsBytes) as pc.RSASignature;

      // 创建完整的X.509证书
      final certificate = X509Certificate(
        tbsCertificate,
        AlgorithmIdentifier(sha256WithRSAEncryptionOid, null),
        signature.bytes,
      );

      // 序列化证书为DER格式
      final certDer = certificate.toAsn1().encodedBytes;

      // 转换为PEM格式以便存储和使用
      final certPem = _createCertificatePem(certDer);

      print('X.509 certificate generated successfully:');
      print('  Subject: CN=$commonName');
      print('  Serial Number: $serialNumber');
      print('  Valid From: ${tbsCertificate.validity?.notBefore}');
      print('  Valid Until: ${tbsCertificate.validity?.notAfter}');
      print('  Signature Algorithm: SHA-256 with RSA');
      print('  Certificate DER size: ${certDer.length} bytes');
      print('  Certificate PEM size: ${certPem.length} characters');

      return Uint8List.fromList(certPem.codeUnits);
    } catch (e) {
      throw Exception('Failed to generate certificate: $e');
    }
  }

  /// 创建PEM格式的证书
  static String _createCertificatePem(List<int> certDer) {
    final buffer = StringBuffer();
    buffer.writeln('-----BEGIN CERTIFICATE-----');
    final base64Str = base64.encode(certDer);
    // 每64字符换行
    for (var i = 0; i < base64Str.length; i += 64) {
      buffer.writeln(base64Str.substring(i,
          i + 64 > base64Str.length ? base64Str.length : i + 64));
    }
    buffer.writeln('-----END CERTIFICATE-----');
    return buffer.toString();
  }

  /// 从PEM格式加载密钥对
  static AdbKeyPair fromPem(String privateKeyPem, String publicKeyPem) {
    try {
      // 解析PEM格式的公钥
      final publicKeyInfos = parsePem(publicKeyPem);
      if (publicKeyInfos.isEmpty) {
        throw Exception('未找到公钥');
      }

      final publicKeyInfo = publicKeyInfos.first as SubjectPublicKeyInfo;
      final cryptoPublicKey = publicKeyInfo.subjectPublicKey as RsaPublicKey;

      // 转换crypto_keys公钥为PointCastle格式
      final pcPublicKey = pc.RSAPublicKey(
        cryptoPublicKey.modulus,
        cryptoPublicKey.exponent,
      );

      // 解析PEM格式的私钥
      final privateKeyInfos = parsePem(privateKeyPem);
      if (privateKeyInfos.isEmpty) {
        throw Exception('未找到私钥');
      }

      final privateKeyInfo = privateKeyInfos.first as PrivateKeyInfo;
      final cryptoPrivateKey =
          privateKeyInfo.keyPair.privateKey as RsaPrivateKey;

      // 转换crypto_keys私钥为PointCastle格式
      final pcPrivateKey = pc.RSAPrivateKey(
        cryptoPrivateKey.modulus,
        cryptoPrivateKey.privateExponent,
        cryptoPrivateKey.firstPrimeFactor,
        cryptoPrivateKey.secondPrimeFactor,
      );

      // 生成真实的X.509证书（对标Kadb）
      final now = DateTime.now();
      final validityPeriod = const Duration(days: 365);

      // 构建完整的证书主题（对标Kadb）
      final subject = Name([
        {ObjectIdentifier([2, 5, 4, 3]): 'pem_imported'}, // commonName
        {ObjectIdentifier([2, 5, 4, 11]): 'adb_dart'}, // organizationalUnitName
        {ObjectIdentifier([2, 5, 4, 10]): 'adb_dart'}, // organizationName
        {ObjectIdentifier([2, 5, 4, 7]): 'adb_dart'}, // localityName
        {ObjectIdentifier([2, 5, 4, 8]): 'adb_dart'}, // stateOrProvinceName
        {ObjectIdentifier([2, 5, 4, 6]): 'CN'}, // countryName
      ]);

      // 创建算法标识符
      final rsaEncryptionOid = ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]);
      final sha256WithRSAEncryptionOid = ObjectIdentifier([1, 2, 840, 113549, 1, 1, 11]);

      // 创建主题公钥信息
      final subjectPublicKeyInfo = SubjectPublicKeyInfo(
        AlgorithmIdentifier(rsaEncryptionOid, null),
        cryptoPublicKey,
      );

      // 创建TbsCertificate（待签名证书）
      final tbsCertificate = TbsCertificate(
        version: 2, // X.509 v3
        serialNumber: now.millisecondsSinceEpoch ~/ 1000,
        signature: AlgorithmIdentifier(sha256WithRSAEncryptionOid, null),
        issuer: subject, // 自签名证书，颁发者和主题相同
        validity: Validity(
          notBefore: now.subtract(Duration(days: 1)).toUtc(), // 提前一天生效
          notAfter: now.add(validityPeriod).toUtc(),
        ),
        subject: subject,
        subjectPublicKeyInfo: subjectPublicKeyInfo,
      );

      // 序列化TBSCertificate进行签名
      final tbsBytes = tbsCertificate.toAsn1().encodedBytes;

      // 使用私钥进行真实签名（SHA-256 + RSA）
      final signer = pc.Signer('SHA-256/RSA')
        ..init(true, pc.PrivateKeyParameter<pc.RSAPrivateKey>(pcPrivateKey));

      final signature = signer.generateSignature(tbsBytes) as pc.RSASignature;

      // 创建完整的X.509证书
      final certificate = X509Certificate(
        tbsCertificate,
        AlgorithmIdentifier(sha256WithRSAEncryptionOid, null),
        signature.bytes,
      );

      // 序列化证书为DER格式
      final certDer = certificate.toAsn1().encodedBytes;

      // 转换为PEM格式以便存储和使用
      final certPem = _createCertificatePem(certDer);

      print('X.509 certificate generated from PEM successfully:');
      print('  Subject: CN=pem_imported');
      print('  Serial Number: ${tbsCertificate.serialNumber}');
      print('  Valid From: ${tbsCertificate.validity?.notBefore}');
      print('  Valid Until: ${tbsCertificate.validity?.notAfter}');
      print('  Signature Algorithm: SHA-256 with RSA');
      print('  Certificate DER size: ${certDer.length} bytes');
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
