import 'dart:typed_data';
import 'package:kadb_dart/kadb_dart.dart';

void main() async {
  print('=== ADB签名调试测试 ===');
  print('用于调试重连认证中的签名验证问题');

  try {
    // 加载已存在的密钥对
    print('1. 加载密钥对...');
    final keyPair = await KeyPairStorage.loadKeyPair(keyName: 'reconnect_test');

    if (keyPair == null) {
      print('未找到测试密钥对，生成新的...');
      final newKeyPair = await AdbKeyPair.generate();
      await KeyPairStorage.saveKeyPair(newKeyPair, keyName: 'reconnect_test');
      final newDevice = await KadbDart.connect(
        host: '192.168.2.32',
        port: 5556,
        keyPair: newKeyPair,
      );
      print('请授权设备后重新运行此测试');
      newDevice.close();
      return;
    }

    print('✅ 密钥对加载成功');

    // 测试签名功能
    print('\n2. 测试签名功能...');
    final testToken = Uint8List.fromList([
      0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0,
      0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
      0x99, 0xAA, 0xBB, 0xCC,
    ]);

    print('测试token: ${testToken.map((b) => b.toString(16).padLeft(2, '0')).join(' ')}');

    // 使用我们的签名方法
    final signature = keyPair.signAdbMessagePayload(testToken.toList());
    print('签名长度: ${signature.length} 字节');

    // 验证签名
    final isValid = keyPair.verify(testToken, signature);
    print('签名验证结果: $isValid');

    if (!isValid) {
      print('❌ 签名验证失败！这可能是重连认证问题的根源');
    } else {
      print('✅ 签名验证成功');
    }

    // 连接到设备，观察实际的认证流程
    print('\n3. 观察实际认证流程...');
    final device = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
    );

    print('连接成功，检查是否需要认证...');
    device.close();

  } catch (e) {
    print('❌ 测试失败: $e');
  }
}