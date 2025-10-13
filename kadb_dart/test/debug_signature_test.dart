import 'package:kadb_dart/kadb_dart.dart';

void main() async {
  print('=== ADB签名认证调试测试 ===');
  print('启用调试模式，查看详细的token和签名信息');

  try {
    // 生成新的密钥对
    print('1. 生成密钥对...');
    final keyPair = await KeyPairStorage.getOrCreateKeyPair(keyName: 'debug_test');
    print('✅ 密钥对生成完成');

    // 启用调试模式的连接
    print('\n2. 连接设备（启用调试模式）...');
    final device = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
      debug: true, // 启用调试模式
    );
    print('✅ 连接成功！');

    // 测试基本功能
    final shellStream = await KadbDart.executeShell(device, 'echo "调试测试成功"');
    final output = await shellStream.readAll();
    print('命令输出: ${output.trim()}');
    await shellStream.close();

    device.close();
    print('\n✅ 调试测试完成');
    print('请查看上面的调试信息，特别关注：');
    print('1. token内容和长度');
    print('2. 签名内容和长度');
    print('3. 认证流程是否成功');

  } catch (e) {
    print('❌ 测试失败: $e');
  }
}