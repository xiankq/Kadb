/// ADB密钥对管理
/// 处理RSA密钥对的生成、存储和签名
library adb_key_pair;

import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/pointycastle.dart' as pc;
import 'package:convert/convert.dart';
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
      final signature = signer.generateSignature(data);
      return signature as Uint8List; // 修正这里
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
    // TODO: 实现完整的X.509证书生成
    // 这里简化处理，返回一个模拟证书
    final now = DateTime.now();
    final expiry = now.add(validityPeriod);

    final certInfo =
        'CN=$commonName: ${now.toIso8601String()}-${expiry.toIso8601String()}';
    return Uint8List.fromList(certInfo.codeUnits);
  }

  /// 从PEM格式加载密钥对
  static AdbKeyPair fromPem(String privateKeyPem, String publicKeyPem) {
    // TODO: 实现PEM格式解析
    throw UnimplementedError('PEM format loading not implemented yet');
  }

  /// 导出为PEM格式
  String exportPrivateKeyPem() {
    // TODO: 实现PEM格式导出
    throw UnimplementedError('PEM format export not implemented yet');
  }

  /// 获取公钥指纹（用于调试）
  String getPublicKeyFingerprint() {
    final adbKey = getAdbPublicKey();
    final hash = Crc32.calculate(adbKey);
    return hex.encode(Uint8List(4)..buffer.asByteData().setUint32(0, hash));
  }

  @override
  String toString() {
    return 'AdbKeyPair{publicKeyFingerprint: ${getPublicKeyFingerprint()}}';
  }
}
