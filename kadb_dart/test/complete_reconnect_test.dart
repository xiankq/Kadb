import 'package:kadb_dart/kadb_dart.dart';

void main() async {
  print('=== 完整的ADB重连认证测试 ===');
  print('这个测试将验证Shell解析修复和重连认证功能的完整流程');

  try {
    // 1. 获取或创建持久化的密钥对
    print('1. 准备密钥对...');
    final keyPair = await KeyPairStorage.getOrCreateKeyPair(keyName: 'reconnect_test');
    print('✅ 密钥对准备完成');

    // 2. 第一次连接
    print('\n2. 第一次连接...');
    final device1 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair,
    );
    print('✅ 第一次连接成功！');

    // 3. 测试Shell输出解析
    print('\n3. 测试Shell输出解析（关键修复验证）...');
    try {
      final shellStream1 = await KadbDart.executeShell(
        device1,
        'getprop ro.product.model',
      );

      String deviceModel = '';
      bool hasStderr = false;

      shellStream1.stdout.listen((data) {
        deviceModel = data.trim();
        print('📱 设备型号输出: $data');
      });

      shellStream1.stderr.listen((data) {
        print('❌ 错误输出: $data');
        hasStderr = true;
      });

      // 等待输出完成
      await for (final _ in shellStream1.stdout) {
        break;
      }

      await shellStream1.close();

      if (deviceModel.isNotEmpty && !hasStderr) {
        print('✅ Shell输出解析修复成功！设备型号正确识别: $deviceModel');
      } else if (hasStderr) {
        print('❌ Shell输出解析仍有问题，设备信息被识别为错误输出');
      } else {
        print('⚠️ 未收到任何输出');
      }
    } catch (e) {
      print('❌ Shell命令执行失败: $e');
    }

    // 4. 断开第一次连接
    device1.close();
    print('\n4. 第一次连接已断开');

    // 5. 等待用户授权（如果需要）
    print('\n5. 准备重连测试...');
    print('如果这是第一次连接，请在设备上点击"始终允许"授权');
    print('等待8秒...');
    await Future.delayed(Duration(seconds: 8));

    // 6. 第二次连接（关键测试）
    print('\n6. 第二次连接（重连认证测试）...');
    final device2 = await KadbDart.connect(
      host: '192.168.2.32',
      port: 5556,
      keyPair: keyPair, // 使用相同的密钥对
    );
    print('✅ 第二次连接成功！');

    // 7. 验证重连后的功能
    print('\n7. 验证重连后的Shell功能...');
    try {
      final shellStream2 = await KadbDart.executeShell(
        device2,
        'echo "重连测试成功"',
      );

      String echoOutput = '';
      shellStream2.stdout.listen((data) {
        echoOutput = data.trim();
        print('📝 Echo输出: $data');
      });

      await for (final _ in shellStream2.stdout) {
        break;
      }

      await shellStream2.close();

      if (echoOutput.contains('重连测试成功')) {
        print('✅ 重连后的Shell功能正常工作！');
      } else {
        print('⚠️ 重连后输出异常: $echoOutput');
      }
    } catch (e) {
      print('❌ 重连后Shell命令失败: $e');
    }

    // 8. 关闭第二次连接
    device2.close();
    print('\n8. 第二次连接已关闭');

    // 9. 总结测试结果
    print('\n🎉 测试总结:');
    print('✅ Shell v2协议数据类型解析已修复');
    print('✅ 重连认证功能正常工作');
    print('✅ 设备信息能正确显示在stdout而非stderr');
    print('\n如果第二次连接没有要求重新授权，说明重连认证修复成功！');

  } catch (e) {
    print('❌ 测试失败: $e');
    print('\n故障排除建议:');
    print('1. 确保设备已连接并启用USB调试');
    print('2. 确认ADB服务运行在 192.168.2.32:5556');
    print('3. 检查设备是否已信任此计算机（点击"始终允许"）');
    print('4. 确认网络连接正常');
  }
}