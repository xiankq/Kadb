import 'package:kadb_dart/kadb_dart.dart';
import 'package:kadb_dart/cert/key_pair_storage.dart';

void main() async {
  print('=== 最终的ADB二次连接认证测试 ===');
  print('这个测试将验证重连认证修复是否有效');

  try {
    // 获取或创建持久化的密钥对
    print('1. 获取或创建ADB密钥对...');
    final keyPair = await KeyPairStorage.getOrCreateKeyPair(keyName: 'test_reconnect');
    print('密钥对已准备就绪');

    // 第一次连接
    print('2. 第一次连接...');
    final device1 = await KadbDart.connect(
      host: 'localhost',
      port: 5555,
      keyPair: keyPair,
    );
    print('第一次连接成功！');

    // 通过执行简单命令来验证连接
    try {
      final shellStream = await KadbDart.executeShell(device1, 'echo "第一次连接测试"');
      final output = await shellStream.readAll();
      print('命令输出: ${output.trim()}');
      await shellStream.close();
    } catch (e) {
      print('执行命令时出错（可能需要授权）: $e');
    }

    // 断开连接
    device1.close();
    print('第一次连接已断开');

    // 等待用户授权（如果需要）
    print('\n重要提示：');
    print('1. 如果设备弹出授权对话框，请点击"始终允许"授权');
    print('2. 授权后，第二次连接应该不需要重新授权');
    print('\n等待10秒，请在此期间完成授权...');
    await Future.delayed(Duration(seconds: 10));

    // 第二次连接（应该不需要重新授权）
    print('3. 第二次连接...');
    final device2 = await KadbDart.connect(
      host: 'localhost',
      port: 5555,
      keyPair: keyPair, // 使用相同的密钥对
    );
    print('第二次连接成功！');

    // 验证第二次连接
    try {
      final shellStream2 = await KadbDart.executeShell(device2, 'echo "第二次连接测试"');
      final output2 = await shellStream2.readAll();
      print('命令输出: ${output2.trim()}');
      await shellStream2.close();
    } catch (e) {
      print('❌ 第二次连接执行命令失败: $e');
      print('这表明重连认证可能仍然有问题');
    }

    // 断开连接
    device2.close();
    print('第二次连接已断开');

    print('\n✅ 二次连接测试完成！');
    print('如果第二次连接成功且没有要求授权，说明修复有效！');
    print('密钥对已保存在 ~/.kadb_dart/test_reconnect.key');

  } catch (e) {
    print('❌ 连接失败: $e');
    print('请检查：');
    print('1. 设备是否在线');
    print('2. IP地址和端口是否正确（通常是 localhost:5555）');
    print('3. 是否已启用USB调试');
    print('4. 是否已信任此计算机（点击"始终允许"）');
  }
}