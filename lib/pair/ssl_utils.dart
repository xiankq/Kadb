import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import '../cert/adb_key_pair.dart';
import '../crypto/crypto_utils.dart';

/// SSL工具类
/// 用于处理SSL/TLS相关的工具函数
class SslUtils {
  /// 生成AES密钥
  static Uint8List generateAesKey() {
    return CryptoUtils.generateRandomBytes(32); // 256位AES密钥
  }

  /// AES加密
  static Uint8List aesEncrypt(Uint8List key, Uint8List data, Uint8List iv) {
    final cipher = CBCBlockCipher(AESEngine());
    final params = ParametersWithIV(KeyParameter(key), iv);
    cipher.init(true, params);

    final encrypted = Uint8List(data.length);
    var offset = 0;

    while (offset < data.length) {
      offset += cipher.processBlock(data, offset, encrypted, offset);
    }

    return encrypted;
  }

  /// AES解密
  static Uint8List aesDecrypt(Uint8List key, Uint8List data, Uint8List iv) {
    final cipher = CBCBlockCipher(AESEngine());
    final params = ParametersWithIV(KeyParameter(key), iv);
    cipher.init(false, params);

    final decrypted = Uint8List(data.length);
    var offset = 0;

    while (offset < data.length) {
      offset += cipher.processBlock(data, offset, decrypted, offset);
    }

    return decrypted;
  }

  /// 生成RSA密钥对
  static Future<AdbKeyPair> generateRsaKeyPair() async {
    return await AdbKeyPair.generate();
  }

  /// RSA加密
  static Uint8List rsaEncrypt(RSAPublicKey publicKey, Uint8List data) {
    final encryptor = OAEPEncoding(RSAEngine());
    encryptor.init(true, PublicKeyParameter(publicKey));
    return encryptor.process(data);
  }

  /// RSA解密
  static Uint8List rsaDecrypt(RSAPrivateKey privateKey, Uint8List data) {
    final decryptor = OAEPEncoding(RSAEngine());
    decryptor.init(false, PrivateKeyParameter(privateKey));
    return decryptor.process(data);
  }

  /// 生成数字签名
  static Uint8List signData(RSAPrivateKey privateKey, Uint8List data) {
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
    signer.init(true, PrivateKeyParameter(privateKey));
    return signer.generateSignature(data).bytes;
  }

  /// 验证数字签名
  static bool verifySignature(
    RSAPublicKey publicKey,
    Uint8List data,
    Uint8List signature,
  ) {
    final verifier = RSASigner(SHA256Digest(), '0609608648016503040201');
    verifier.init(false, PublicKeyParameter(publicKey));

    try {
      final sig = RSASignature(signature);
      return verifier.verifySignature(data, sig);
    } catch (e) {
      return false;
    }
  }

  /// 生成TLS握手随机数
  static Uint8List generateTlsRandom() {
    final random = Uint8List(32);
    final time = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // 写入时间戳（4字节）
    random[0] = (time >> 24) & 0xFF;
    random[1] = (time >> 16) & 0xFF;
    random[2] = (time >> 8) & 0xFF;
    random[3] = time & 0xFF;

    // 填充随机字节
    final secureRandom = Random.secure();
    for (int i = 4; i < 32; i++) {
      random[i] = secureRandom.nextInt(256);
    }

    return random;
  }

  /// 计算TLS主密钥
  static Uint8List computeTlsMasterSecret(
    Uint8List preMasterSecret,
    Uint8List clientRandom,
    Uint8List serverRandom,
  ) {
    final seed = Uint8List(clientRandom.length + serverRandom.length);
    seed.setRange(0, clientRandom.length, clientRandom);
    seed.setRange(clientRandom.length, seed.length, serverRandom);

    return _prf(preMasterSecret, 'master secret', seed, 48);
  }

  /// 计算TLS密钥块
  static Uint8List computeTlsKeyBlock(
    Uint8List masterSecret,
    Uint8List clientRandom,
    Uint8List serverRandom,
    int length,
  ) {
    final seed = Uint8List(clientRandom.length + serverRandom.length);
    seed.setRange(0, clientRandom.length, clientRandom);
    seed.setRange(clientRandom.length, seed.length, serverRandom);

    return _prf(masterSecret, 'key expansion', seed, length);
  }

  /// PRF函数（伪随机函数）
  static Uint8List _prf(
    Uint8List secret,
    String label,
    Uint8List seed,
    int length,
  ) {
    final labelBytes = utf8.encode(label);
    final seedBytes = Uint8List(labelBytes.length + seed.length);
    seedBytes.setRange(0, labelBytes.length, labelBytes);
    seedBytes.setRange(labelBytes.length, seedBytes.length, seed);

    return _pHash(secret, seedBytes, length);
  }

  /// P_Hash函数
  static Uint8List _pHash(Uint8List secret, Uint8List seed, int length) {
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(secret));

    final result = Uint8List(length);
    var offset = 0;
    var a = seed;

    while (offset < length) {
      a = hmac.process(a);
      final chunk = hmac.process(Uint8List.fromList([...a, ...seed]));

      final copyLength = min(chunk.length, length - offset);
      result.setRange(offset, offset + copyLength, chunk);
      offset += copyLength;
    }

    return result;
  }
}
