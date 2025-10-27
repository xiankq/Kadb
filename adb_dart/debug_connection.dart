import 'package:adb_dart/adb_dart.dart';

/// 详细的连接调试测试
void main() async {
  print('=== ADB连接详细调试 ===');

  final client = AdbClient.create(host: 'localhost', port: 5037);

  try {
    print('1. 正在连接到ADB服务器...');
    await client.connect();
    print('✅ 连接成功！');

    print('2. 检查连接状态...');
    print('是否已连接: ${client.isConnected}');

    print('3. 测试简单命令...');
    final result = await client.shell('echo "Hello ADB"');
    print('命令输出：${result.stdout}');
    print('退出码：${result.exitCode}');
  } catch (e, stackTrace) {
    print('❌ 连接失败：$e');
    print('错误类型：${e.runtimeType}');
    print('堆栈跟踪：');
    print(stackTrace);
  } finally {
    print('4. 断开连接...');
    await client.dispose();
    print('连接已断开');
  }

  print('=== 调试结束 ===');
}
