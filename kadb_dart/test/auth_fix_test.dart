import 'package:kadb_dart/kadb_dart.dart';

void main() async {
  print('=== ADB重连认证修复验证测试 ===');
  print('这个测试专门验证重连认证是否完全修复');

  try {
    // 使用新的密钥对名以确保从零开始测试
    const String keyName = 'auth_fix_test';

    // 1. 删除可能存在的旧密钥对
    print('1. 清理旧的密钥对...');
    await KeyPairStorage.deleteKeyPair(keyName: keyName);

    // 2. 生成新的密钥对
    print('2. 生成新的密钥对...');
    final keyPair = await KeyPairStorage.getOrCreateKeyPair(keyName: keyName);
    print('✅ 密钥对生成完成');

    // 3. 第一次连接（需要手动授权）
    print('\n3. 第一次连接（需要手动授权）...');
    print('请在设备上点击"始终允许"授权，然后等待连接完成');

    final device1 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
    );
    print('✅ 第一次连接成功！');

    // 测试基本功能
    final shellStream1 = await KadbDart.executeShell(device1, 'echo "第一次连接测试"');
    final output1 = await shellStream1.readAll();
    print('命令输出: ${output1.trim()}');
    await shellStream1.close();

    // 断开连接
    device1.close();
    print('第一次连接已断开');

    // 4. 等待一小段时间
    print('\n4. 等待3秒后进行重连测试...');
    await Future.delayed(Duration(seconds: 3));

    // 5. 第二次连接（关键测试 - 应该不需要重新授权）
    print('\n5. 第二次连接（关键测试）...');
    print('🔍 观察是否出现认证流程：');
    print('   - 如果没有 < AUTH[1,0] 消息，说明重连认证成功');
    print('   - 如果仍有认证流程，说明修复未完全成功');

    final device2 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair, // 使用相同的密钥对
    );
    print('✅ 第二次连接成功！');

    // 测试重连后的功能
    final shellStream2 = await KadbDart.executeShell(device2, 'echo "重连认证测试成功"');
    final output2 = await shellStream2.readAll();
    print('重连命令输出: ${output2.trim()}');
    await shellStream2.close();

    device2.close();
    print('第二次连接已断开');

    // 6. 第三次连接（进一步验证）
    print('\n6. 第三次连接（进一步验证）...');

    final device3 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
    );
    print('✅ 第三次连接成功！');

    final shellStream3 = await KadbDart.executeShell(device3, 'echo "多次重连测试成功"');
    final output3 = await shellStream3.readAll();
    print('第三次命令输出: ${output3.trim()}');
    await shellStream3.close();

    device3.close();
    print('第三次连接已断开');

    print('\n🎉 测试完成！');
    print('如果第二次和第三次连接都没有要求重新授权，');
    print('说明重连认证问题已完全解决！');

  } catch (e) {
    print('❌ 测试失败: $e');
    print('\n故障排除建议：');
    print('1. 确保设备已连接并启用USB调试');
    print('2. 确认网络连接正常');
    print('3. 检查设备是否已正确授权第一次连接');
  }
}