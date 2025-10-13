import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/signers/rsa_signer.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/pointycastle.dart';

void main() async {
  print('测试RSA密钥生成和签名...');
  
  // 生成RSA密钥对
  final keyGen = RSAKeyGenerator();
  final random = FortunaRandom();
  
  // 初始化随机数生成器
  final seedSource = Random.secure();
  final seeds = <int>[];
  for (int i = 0; i < 32; i++) {
    seeds.add(seedSource.nextInt(256));
  }
  random.seed(KeyParameter(Uint8List.fromList(seeds)));
  
  // 生成RSA密钥参数
  final params = RSAKeyGeneratorParameters(
    BigInt.from(65537),
    2048,
    64,
  );
  
  keyGen.init(ParametersWithRandom(params, random));
  
  // 生成密钥对
  final keyPair = keyGen.generateKeyPair();
  final publicKey = keyPair.publicKey as RSAPublicKey;
  final privateKey = keyPair.privateKey as RSAPrivateKey;
  
  print('公钥模数: ${publicKey.modulus}');
  print('私钥模数: ${privateKey.modulus}');
  print('p: ${privateKey.p}');
  print('q: ${privateKey.q}');
  
  // 测试签名
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
  signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
  
  final testData = Uint8List.fromList(utf8.encode('Hello ADB'));
  final signature = signer.generateSignature(testData);
  
  print('签名成功: ${signature.bytes.length} bytes');
  
  // 测试验证
  signer.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
  final isValid = signer.verifySignature(testData, signature);
  
  print('验证结果: $isValid');
}