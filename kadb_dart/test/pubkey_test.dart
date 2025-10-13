/// 测试公钥编码
import 'dart:convert';
import 'dart:typed_data';
import 'package:kadb_dart/cert/adb_key_pair.dart';
import 'package:kadb_dart/cert/android_pubkey.dart';

void main() async {
  print('=== 公钥编码测试 ===');

  // 生成密钥对
  final keyPair = await AdbKeyPair.generate();

  // 1. 使用我们的编码
  final ourEncoding = AndroidPubkey.encode(keyPair.publicKey);
  print('我们的编码长度: ${ourEncoding.length}');
  print('我们的编码 (hex): ${ourEncoding.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

  // 2. Base64编码我们的Android格式公钥
  final ourBase64 = base64.encode(ourEncoding);
  print('我们的Base64: $ourBase64');
  print('我们的Base64长度: ${ourBase64.length}');

  // 3. 检查公钥结构
  print('\n=== 检查公钥结构 ===');
  print('模数长度: ${keyPair.publicKey.modulus?.bitLength} bits');
  print('指数: ${keyPair.publicKey.exponent}');

  // 4. 解码验证
  try {
    final decoded = AndroidPubkey.parseAndroidPubkey(ourEncoding);
    print('解码成功: ${decoded.modulus == keyPair.publicKey.modulus}');
  } catch (e) {
    print('解码失败: $e');
  }
}