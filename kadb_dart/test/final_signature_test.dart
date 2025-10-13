import 'package:kadb_dart/kadb_dart.dart';

void main() async {
  print('=== 最终签名认证验证测试 ===');
  print('这个测试将验证签名认证的稳定性和可靠性');

  try {
    // 删除旧的密钥对，确保从零开始
    const String keyName = 'final_signature_test';
    await KeyPairStorage.deleteKeyPair(keyName: keyName);

    // 生成新的密钥对
    print('1. 生成新的密钥对...');
    final keyPair = await KeyPairStorage.getOrCreateKeyPair(keyName: keyName);
    print('✅ 密钥对生成完成');

    // 第一次连接测试
    print('\n2. 第一次连接测试...');
    print('观察认证流程：');

    final device1 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
      debug: true, // 启用调试模式查看详细流程
    );
    print('✅ 第一次连接成功！');
    device1.close();

    // 等待一小段时间
    print('\n3. 等待3秒后进行重连测试...');
    await Future.delayed(Duration(seconds: 3));

    // 第二次连接测试
    print('\n4. 第二次连接测试（重连认证关键测试）...');
    print('🔍 观察认证流程：');
    print('   成功标志：直接 CNXN 或 AUTH -> AUTH(签名) -> CNXN');
    print('   失败标志：AUTH -> AUTH(签名) -> AUTH -> AUTH(公钥) -> CNXN');

    final device2 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
      debug: true,
    );
    print('✅ 第二次连接成功！');
    device2.close();

    // 第三次连接测试
    print('\n5. 第三次连接测试（进一步验证）...');
    final device3 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
      debug: true,
    );
    print('✅ 第三次连接成功！');
    device3.close();

    print('\n🎉 最终测试结果分析：');
    print('请根据上面的调试日志分析：');
    print('1. 如果所有连接都是"签名认证成功"，说明签名认证完全修复');
    print('2. 如果出现"回退到公钥认证"，说明签名认证仍有问题');
    print('3. 如果第一次成功，后续失败，说明重连机制有问题');

  } catch (e) {
    print('❌ 测试失败: $e');
    print('\n故障排除建议：');
    print('1. 确保设备已连接并启用USB调试');
    print('2. 确认网络连接正常');
    print('3. 检查设备是否已正确授权第一次连接');
  }
}