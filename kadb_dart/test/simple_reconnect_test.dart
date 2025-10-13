import 'package:kadb_dart/kadb_dart.dart';

void main() async {
  print('=== 简单重连认证测试 ===');

  try {
    // 使用缓存的密钥对
    final keyPair = await KeyPairStorage.getOrCreateKeyPair(keyName: 'simple_test');

    print('1. 第一次连接...');
    final device1 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
    );
    print('✅ 第一次连接成功');
    device1.close();

    print('\n2. 第二次连接...');
    final device2 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
    );
    print('✅ 第二次连接成功');
    device2.close();

    print('\n3. 第三次连接...');
    final device3 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
    );
    print('✅ 第三次连接成功');
    device3.close();

    print('\n🎉 重连认证修复成功！');
    print('多次连接都没有要求重新授权！');

  } catch (e) {
    print('❌ 测试失败: $e');
  }
}