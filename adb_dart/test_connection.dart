import 'dart:io';
import 'package:adb_dart/adb_dart.dart';

/// 简单的连接测试
void main() async {
  print('=== ADB连接测试 ===');

  final client = AdbClient.create(host: 'localhost', port: 5037);

  try {
    print('正在连接到ADB服务器...');
    await client.connect();
    print('✅ 连接成功！');

    print('正在测试简单命令...');
    final result = await client.shell('echo "Hello ADB"');
    print('命令输出：${result.stdout}');
    print('退出码：${result.exitCode}');
  } catch (e) {
    print('❌ 连接失败：$e');
    print('错误类型：${e.runtimeType}');

    // 打印更详细的错误信息
    if (e is SocketException) {
      final se = e;
      print('Socket错误：${se.message}');
      print('错误码：${se.osError?.errorCode}');
    }
  } finally {
    await client.dispose();
    print('连接已断开');
  }

  print('=== 测试结束 ===');
}
