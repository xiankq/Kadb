/// 公钥编码测试
library;
import 'dart:convert';
import 'package:kadb_dart/cert/adb_key_pair.dart';
import 'package:kadb_dart/cert/android_pubkey.dart';

/// 测试Android公钥编码格式的正确性
void main() async {
  // 生成RSA密钥对
  final keyPair = await AdbKeyPair.generate();

  // 编码公钥为Android格式
  final androidPubkeyBytes = AndroidPubkey.encode(keyPair.publicKey);
  
  // 验证编码结果
  assert(androidPubkeyBytes.length == 524, 'Android公钥编码长度应为524字节');
  assert(androidPubkeyBytes.isNotEmpty, 'Android公钥编码不应为空');

  // Base64编码
  final base64Encoding = base64.encode(androidPubkeyBytes);
  assert(base64Encoding.isNotEmpty, 'Base64编码不应为空');

  // 验证密钥参数
  assert(keyPair.publicKey.modulus?.bitLength == 2048, 'RSA模数应为2048位');
  assert(keyPair.publicKey.exponent == BigInt.from(65537), 'RSA指数应为65537');

  // 解码验证（往返测试）
  final decodedKey = AndroidPubkey.parseAndroidPubkey(androidPubkeyBytes);
  assert(decodedKey.modulus == keyPair.publicKey.modulus, '解码后的模数应匹配原始模数');
  assert(decodedKey.exponent == keyPair.publicKey.exponent, '解码后的指数应匹配原始指数');

  // 测试通过
  print('Android公钥编码测试通过');
}