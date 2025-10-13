import 'package:kadb_dart/cert/adb_key_pair.dart';

void main() async {
  print('测试ADB密钥对生成...');
  try {
    var keyPair = await AdbKeyPair.generate();
    print('生成成功: $keyPair');
    print('公钥模数长度: ${keyPair.publicKey.modulus?.bitLength ?? 0} bits');
    print('私钥模数长度: ${keyPair.privateKey.modulus?.bitLength ?? 0} bits');
  } catch (e) {
    print('生成失败: $e');
  }
}