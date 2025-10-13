import 'package:kadb_dart/kadb_dart.dart';

void main() async {
  print('=== ADB签名认证专项测试 ===');
  print('这个测试专门验证签名认证是否成功，避免回退到公钥认证');

  try {
    // 删除旧的密钥对，确保从零开始
    const String keyName = 'signature_test';
    await KeyPairStorage.deleteKeyPair(keyName: keyName);

    // 生成新的密钥对
    print('1. 生成新的密钥对...');
    final keyPair = await KeyPairStorage.getOrCreateKeyPair(keyName: keyName);
    print('✅ 密钥对生成完成');

    // 第一次连接（需要手动授权）
    print('\n2. 第一次连接（需要手动授权）...');
    print('📝 观察认证流程：');
    print('   - 期望：AUTH -> AUTH(签名) -> CNXN（签名成功）');
    print('   - 如果出现 AUTH -> AUTH(签名) -> AUTH -> AUTH(公钥) -> CNXN，说明签名失败');

    final device1 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
    );
    print('✅ 第一次连接成功！');

    // 测试基本功能
    final shellStream1 = await KadbDart.executeShell(device1, 'echo "签名认证测试"');
    final output1 = await shellStream1.readAll();
    print('命令输出: ${output1.trim()}');
    await shellStream1.close();

    device1.close();
    print('第一次连接已断开');

    // 等待一小段时间
    print('\n3. 等待3秒后进行重连测试...');
    await Future.delayed(Duration(seconds: 3));

    // 第二次连接（关键测试）
    print('\n4. 第二次连接（签名认证关键测试）...');
    print('🔍 仔细观察认证流程：');
    print('   ✅ 成功：直接 CNXN（无需认证）');
    print('   ⚠️  部分成功：AUTH -> AUTH(签名) -> CNXN（签名认证成功）');
    print('   ❌ 失败：AUTH -> AUTH(签名) -> AUTH -> AUTH(公钥) -> CNXN（签名失败，回退公钥）');

    final device2 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
    );
    print('✅ 第二次连接成功！');

    // 测试重连后的功能
    final shellStream2 = await KadbDart.executeShell(device2, 'echo "重连签名认证成功"');
    final output2 = await shellStream2.readAll();
    print('重连命令输出: ${output2.trim()}');
    await shellStream2.close();

    device2.close();
    print('第二次连接已断开');

    // 第三次连接（进一步验证）
    print('\n5. 第三次连接（进一步验证）...');

    final device3 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
    );
    print('✅ 第三次连接成功！');

    final shellStream3 = await KadbDart.executeShell(device3, 'echo "多次签名认证成功"');
    final output3 = await shellStream3.readAll();
    print('第三次命令输出: ${output3.trim()}');
    await shellStream3.close();

    device3.close();
    print('第三次连接已断开');

    print('\n🎉 签名认证测试完成！');
    print('请根据上面的日志判断：');
    print('1. 如果第二次和第三次连接都是"直接 CNXN"或"AUTH -> AUTH(签名) -> CNXN"');
    print('   说明签名认证修复成功！');
    print('2. 如果出现"AUTH -> AUTH(签名) -> AUTH -> AUTH(公钥) -> CNXN"');
    print('   说明签名认证仍然失败，需要进一步调试');

  } catch (e) {
    print('❌ 测试失败: $e');
    print('\n故障排除建议：');
    print('1. 确保设备已连接并启用USB调试');
    print('2. 确认网络连接正常');
    print('3. 检查设备是否已正确授权第一次连接');
  }
}