import 'package:kadb_dart/kadb_dart.dart';

void main() async {
  print('=== Shell输出解析修复测试 ===');
  print('这个测试将验证Shell v2协议数据类型解析的修复效果');

  try {
    // 使用持久化的密钥对
    print('1. 准备密钥对...');
    final keyPair = await KeyPairStorage.getOrCreateKeyPair(keyName: 'shell_test');
    print('密钥对准备完成');

    // 连接到设备
    print('\n2. 连接到设备...');
    final device = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
    );
    print('✅ 连接成功！');

    // 测试简单命令
    print('\n3. 测试Shell命令执行...');
    final shellStream = await KadbDart.executeShell(
      device,
      'getprop ro.product.model',
      [],
    );

    // 监听输出
    bool hasStdout = false;
    bool hasStderr = false;

    shellStream.stdout.listen((data) {
      print('📱 STDOUT: $data');
      hasStdout = true;
    });

    shellStream.stderr.listen((data) {
      print('❌ STDERR: $data');
      hasStderr = true;
    });

    shellStream.exitCode.listen((code) {
      print('🔢 EXIT CODE: $code');
    });

    // 等待输出完成
    await for (final _ in shellStream.stdout) {
      break; // 只需要第一个输出
    }

    await shellStream.close();

    // 分析结果
    print('\n4. 结果分析:');
    if (hasStdout && !hasStderr) {
      print('✅ 修复成功！设备型号正确识别为stdout输出');
    } else if (hasStderr) {
      print('❌ 修复失败！设备型号仍然被识别为stderr输出');
    } else {
      print('⚠️  未收到任何输出');
    }

    // 关闭连接
    device.close();
    print('\n✅ 测试完成');

  } catch (e) {
    print('❌ 测试失败: $e');
    print('\n请检查：');
    print('1. 设备是否已连接并启用USB调试');
    print('2. ADB服务是否运行在 192.168.2.32:5556');
    print('3. 是否已信任此计算机');
  }
}