import 'package:kadb_dart/kadb_dart.dart';

void main() async {
  print('=== ADB重连认证修复示例 ===');
  print('这个示例展示了如何使用修复后的ADB连接功能');

  try {
    // 1. 获取或创建持久化的密钥对
    print('\n1. 获取或创建密钥对...');
    final keyPair = await KeyPairStorage.getOrCreateKeyPair(keyName: 'my_device');
    print('密钥对已准备就绪');

    // 2. 连接到设备
    print('\n2. 连接到设备...');
    print('提示：如果这是第一次连接，请在设备上点击"始终允许"授权');

    final device = await KadbDart.connect(
      host: 'localhost',
      port: 5555,
      keyPair: keyPair,
    );
    print('✅ 连接成功！');

    // 3. 执行简单命令测试
    print('\n3. 测试连接...');
    try {
      final shellStream = await KadbDart.executeShell(device, 'echo "Hello from ADB!"');
      final output = await shellStream.readAll();
      print('命令输出: ${output.trim()}');
      await shellStream.close();
    } catch (e) {
      print('命令执行出错: $e');
    }

    // 4. 断开连接
    print('\n4. 断开连接...');
    device.close();
    print('连接已断开');

    // 5. 模拟重连（在实际使用中，这可能是程序重启后）
    print('\n5. 模拟重连...');
    print('使用相同的密钥对重新连接，应该不需要重新授权');

    final device2 = await KadbDart.connect(
      host: 'localhost',
      port: 5555,
      keyPair: keyPair, // 使用相同的密钥对
    );
    print('✅ 重连成功！');

    // 6. 验证重连后的功能
    print('\n6. 验证重连后的功能...');
    try {
      final shellStream2 = await KadbDart.executeShell(device2, 'getprop ro.product.model');
      final deviceModel = await shellStream2.readAll();
      print('设备型号: ${deviceModel.trim()}');
      await shellStream2.close();
    } catch (e) {
      print('命令执行出错: $e');
    }

    // 7. 清理
    print('\n7. 清理资源...');
    device2.close();
    print('✅ 所有连接已关闭');

    print('\n🎉 重连认证测试完成！');
    print('如果第二次连接没有要求重新授权，说明修复成功！');

  } catch (e) {
    print('❌ 操作失败: $e');
    print('\n请检查：');
    print('1. 设备是否已连接并启用USB调试');
    print('2. ADB服务是否运行在 localhost:5555');
    print('3. 是否已信任此计算机');
  }
}