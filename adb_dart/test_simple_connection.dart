import 'dart:io';
import 'dart:typed_data';
import 'package:adb_dart/adb_dart.dart';

/// 简化的ADB连接测试
void main() async {
  print('=== 简化ADB连接测试 ===');
  
  try {
    // 创建ADB客户端
    print('创建ADB客户端...');
    final client = AdbClient(
      host: 'localhost',
      port: 5037,
      connectTimeout: const Duration(seconds: 10),
    );
    
    print('连接到ADB服务器...');
    await client.connect().timeout(const Duration(seconds: 15));
    print('✅ 连接成功！');
    
    // 测试简单的shell命令
    print('执行测试命令...');
    final result = await client.shell('echo "Hello from Dart ADB!"');
    print('命令输出: ${result.stdout}');
    print('退出码: ${result.exitCode}');
    
    await client.disconnect();
    print('✅ 断开连接成功');
    
  } catch (e) {
    print('❌ 连接失败: $e');
  }
  
  print('=== 测试完成 ===');
}