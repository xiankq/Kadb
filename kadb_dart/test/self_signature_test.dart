import 'dart:typed_data';
import 'package:kadb_dart/kadb_dart.dart';

void main() async {
  print('=== 签名自验证测试 ===');
  print('测试我们的签名算法能否正确验证自己的签名');

  try {
    // 生成密钥对
    final keyPair = await AdbKeyPair.generate();

    // 使用实际从设备收到的token
    final actualToken = Uint8List.fromList([
      0x95, 0xfe, 0x8c, 0x55, 0xa4, 0x36, 0x86, 0xa8,
      0xd6, 0x60, 0xd7, 0xf8, 0x49, 0x4b, 0x9c, 0x97,
      0x3a, 0x04, 0x1d, 0xfe
    ]);

    print('1. 生成密钥对完成');
    print('2. 使用实际token进行签名测试');
    print('Token: ${actualToken.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

    // 使用我们的签名方法签名
    final signature = keyPair.signAdbMessagePayload(actualToken.toList());
    print('3. 签名生成完成，长度: ${signature.length}');
    print('签名前8字节: ${signature.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

    // 验证我们自己的签名
    final isValid = keyPair.verify(actualToken, signature);
    print('4. 签名验证结果: $isValid');

    if (isValid) {
      print('✅ 自签名验证成功！');
      print('这说明我们的签名算法本身是正确的');
      print('问题可能在于设备期望的格式与我们不同');
    } else {
      print('❌ 自签名验证失败！');
      print('这说明我们的签名算法本身有问题');
    }

    // 尝试连接，看看认证流程
    print('\n5. 尝试连接设备进行实际认证测试...');
    final device = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
    );

    device.close();
    print('连接测试完成');

  } catch (e) {
    print('❌ 测试失败: $e');
  }
}