import 'package:kadb_dart/kadb_dart.dart';

void main() async {
  print('=== ADB重连认证问题调试 ===');

  try {
    // 使用相同的密钥对进行多次连接测试
    print('1. 获取密钥对...');
    final keyPair = await KeyPairStorage.getOrCreateKeyPair(keyName: 'auth_test');
    print('密钥对准备完成');

    // 第一次连接
    print('\n2. 第一次连接...');
    final device1 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
    );
    print('✅ 第一次连接成功！');
    device1.close();

    // 立即进行第二次连接
    print('\n3. 立即进行第二次连接...');
    print('观察是否还需要认证流程...');

    final device2 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair, // 使用相同的密钥对
    );
    print('✅ 第二次连接成功！');
    device2.close();

    print('\n🎯 观察结果：');
    print('- 如果第二次连接没有显示 < AUTH[1, 0] 认证流程，说明重连认证正常工作');
    print('- 如果第二次连接仍然显示认证流程，说明签名验证有问题');

  } catch (e) {
    print('❌ 测试失败: $e');
  }
}