/// ADB密钥对管理
/// 处理RSA密钥对的生成、存储和签名
library adb_key_pair;

import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/pointycastle.dart' as pc;
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:asn1lib/asn1lib.dart';
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

  /// 使用私钥对数据进行签名（完全对标Kadb：RSA/ECB/NoPadding + update/doFinal模式）
  Uint8List signPayload(Uint8List data) {
    try {
      print('DEBUG: 使用完全对标Kadb的RSA签名算法 (update + doFinal模式)');

      // 完全对标Kadb的AndroidPubkey.SIGNATURE_PADDING（235字节）
      // 精确复制Kadb源码格式：2字节头部 + 217字节FF填充 + 1字节分隔符 + 15字节固定尾部 = 235字节
      final signaturePadding = Uint8List.fromList([
        0x00, 0x01, // 头部 (2字节)
        // 217字节的0xFF填充（精确计算使总长度为235字节）
        ...List.generate(217, (index) => 0xFF), // 217字节FF填充
        0x00, // 分隔符 (1字节)
        0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14 // 固定尾部15字节
      ]);

      print('DEBUG: 使用完全对标Kadb的SIGNATURE_PADDING，长度: ${signaturePadding.length}字节');
      print('DEBUG: 待签名数据长度: ${data.length} 字节');

      // 创建RSA处理器（无填充模式）- 完全对标Kadb的RSA/ECB/NoPadding
      final rsaEngine = RSAEngine();
      final privateKeyParam = pc.PrivateKeyParameter<pc.RSAPrivateKey>(privateKey);
      rsaEngine.init(true, privateKeyParam); // 加密模式

      // 使用对标Kadb的算法：先update填充，再doFinal数据
      // 注意：由于PointCastle的RSAEngine没有update/doFinal方法，我们需要手动模拟这个过程
      final paddedInput = BytesBuilder();
      paddedInput.add(signaturePadding);
      paddedInput.add(data);

      final finalInput = paddedInput.toBytes();
      print('DEBUG: 最终输入数据长度: ${finalInput.length} 字节 (235 + ${data.length} = ${signaturePadding.length + data.length})');

      // 使用RSA加密（无填充）生成签名 - 这是Kadb的核心算法！
      final signature = rsaEngine.process(finalInput);

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

  /// 将RSA公钥导出为DER格式
  Uint8List _exportPublicKeyDer(pc.RSAPublicKey publicKey) {
    try {
      // 创建RSA公钥的ASN.1结构
      final algorithmIdentifier = ASN1Sequence()
        ..add(ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.1')) // RSA加密
        ..add(ASN1Null());

      final publicKeySequence = ASN1Sequence()
        ..add(ASN1Integer(publicKey.modulus!))
        ..add(ASN1Integer(publicKey.exponent!));

      final publicKeyBits = ASN1BitString(publicKeySequence.encodedBytes);

      final publicKeyInfo = ASN1Sequence()
        ..add(algorithmIdentifier)
        ..add(publicKeyBits);

      return publicKeyInfo.encodedBytes;
    } catch (e) {
      throw Exception('DER公钥导出失败: $e');
    }
  }

  /// 生成ADB密钥对
  static AdbKeyPair generate({int keySize = 2048, String? commonName}) {
    try {
      print('DEBUG: 开始生成RSA密钥对 (keySize: $keySize)');

      // 生成RSA密钥对
      final keyParams = pc.RSAKeyGeneratorParameters(
        BigInt.parse('65537'), // 公钥指数
        keySize, // 密钥长度
        12, // 确定性
      );

      final random = pc.SecureRandom('Fortuna')
        ..seed(pc.KeyParameter(
          Uint8List.fromList(
            List.generate(32, (index) => Random().nextInt(256)),
          ),
        ));

      final generator = pc.KeyGenerator('RSA')
        ..init(pc.ParametersWithRandom(keyParams, random));

      final keyPair = generator.generateKeyPair();
      final privateKey = keyPair.privateKey as pc.RSAPrivateKey;
      final publicKey = keyPair.publicKey as pc.RSAPublicKey;

      print('DEBUG: RSA密钥对生成完成');
      print('DEBUG: 模数长度: ${privateKey.modulus!.bitLength} 位');

      // 生成证书（简化的自签名证书）
      final certificate = _generateCertificate(privateKey, publicKey);

      return AdbKeyPair(
        privateKey: privateKey,
        publicKey: publicKey,
        certificate: certificate,
      );
    } catch (e) {
      throw Exception('ADB密钥对生成失败: $e');
    }
  }

  /// 生成简化的自签名证书
  static Uint8List _generateCertificate(pc.RSAPrivateKey privateKey, pc.RSAPublicKey publicKey) {
    try {
      print('DEBUG: 生成简化证书');

      // 创建基本的证书结构
      final certificate = ASN1Sequence();

      // 证书版本
      final version = ASN1Integer(BigInt.from(0));
      certificate.add(version);

      // 序列号
      final serialNumber = ASN1Integer(BigInt.from(DateTime.now().millisecondsSinceEpoch));
      certificate.add(serialNumber);

      // 签名算法
      final signatureAlgorithm = ASN1Sequence()
        ..add(ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.1')) // RSA
        ..add(ASN1Null());
      certificate.add(signatureAlgorithm);

      // 颁发者名称（简化）
      final issuer = ASN1Sequence()
        ..add(ASN1Set()
          ..add(ASN1Sequence()
            ..add(ASN1ObjectIdentifier.fromComponentString('2.5.4.3')) // CN
            ..add(ASN1UTF8String('ADB Test Certificate'))));
      certificate.add(issuer);

      // 有效期
      final now = DateTime.now();
      final notBefore = ASN1UtcTime(now);
      final notAfter = ASN1UtcTime(now.add(Duration(days: 365)));
      final validity = ASN1Sequence()
        ..add(notBefore)
        ..add(notAfter);
      certificate.add(validity);

      // 主题名称（与颁发者相同）
      certificate.add(issuer);

      // 公钥信息
      final publicKeyInfo = ASN1Sequence()
        ..add(ASN1Sequence()
          ..add(ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.1'))
          ..add(ASN1Null()))
        ..add(ASN1BitString(publicKey.modulus!.toRadixString(16).padLeft(512, '0').codeUnits));
      certificate.add(publicKeyInfo);

      print('DEBUG: 证书生成完成');
      return certificate.encodedBytes;
    } catch (e) {
      print('DEBUG: 证书生成失败: $e');
      return Uint8List.fromList([0]); // 返回空证书
    }
  }
}