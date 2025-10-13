import 'dart:typed_data';
import 'package:kadb_dart/kadb_dart.dart';

void main() async {
  print('=== 类型转换修复测试 ===');

  try {
    // 生成密钥对
    print('1. 生成ADB密钥对...');
    final keyPair = await AdbKeyPair.generate();
    print('密钥对生成成功');

    // 测试新的签名方法
    print('2. 测试signAdbMessagePayload方法...');
    final testPayload = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];

    final signature = keyPair.signAdbMessagePayload(testPayload);
    print('签名成功，签名长度: ${signature.length}字节');

    // 验证签名
    final isValid = keyPair.verify(Uint8List.fromList(testPayload), signature);
    print('签名验证结果: $isValid');

    if (isValid) {
      print('✅ 类型转换修复成功！');
      print('signAdbMessagePayload方法现在可以正确处理List<int>类型的payload');
    } else {
      print('❌ 签名验证失败');
    }

  } catch (e) {
    print('❌ 测试失败: $e');
    print('如果仍有类型错误，请检查实现');
  }
}