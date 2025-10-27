import 'package:adb_dart/adb_dart.dart';

/// ADB Dart基本使用示例
void main() async {
  print('=== ADB Dart 示例程序 ===');

  // 创建ADB客户端
  final client = AdbClient.create(host: '192.168.2.148', port: 5555);

  try {
    print('正在连接到ADB服务器...');
    await client.connect();
    print('✅ 连接成功');

    // 检查是否支持某些特性
    print('\n检查特性支持：');
    try {
      final supportsCmd = await client.supportsFeature('cmd');
      print('cmd特性: ${supportsCmd ? "✅ 支持" : "❌ 不支持"}');
    } catch (e) {
      print('cmd特性: ❌ 检查失败 - $e');
    }

    // 执行简单的shell命令
    print('\n执行shell命令：');
    try {
      final result = await client.shell('echo "Hello from ADB Dart!"');
      print('命令输出: ${result.stdout.trim()}');
      print('退出码: ${result.exitCode}');
      print('✅ 命令执行成功');
    } catch (e) {
      print('❌ 命令执行失败: $e');
    }

    // 获取设备信息
    print('\n获取设备信息：');
    try {
      final modelResult = await client.shell('getprop ro.product.model');
      final androidVersion = await client.shell(
        'getprop ro.build.version.release',
      );

      print('设备型号: ${modelResult.stdout.trim()}');
      print('Android版本: ${androidVersion.stdout.trim()}');
      print('✅ 设备信息获取成功');
    } catch (e) {
      print('❌ 设备信息获取失败: $e');
    }

    // 列出已安装的应用
    print('\n列出已安装应用：');
    try {
      final packagesResult = await client.shell('pm list packages | head -5');
      print('前5个已安装包：');
      for (final line in packagesResult.stdout.trim().split('\n')) {
        if (line.trim().isNotEmpty) {
          print('  ${line.trim()}');
        }
      }
      print('✅ 应用列表获取成功');
    } catch (e) {
      print('❌ 应用列表获取失败: $e');
    }
  } catch (e) {
    print('❌ 连接失败: $e');
    print('请确保：');
    print('  1. ADB服务器正在运行 (adb start-server)');
    print('  2. 设备已连接并授权');
    print('  3. 端口5037未被占用');
  } finally {
    print('\n正在断开连接...');
    await client.dispose();
    print('✅ 连接已断开');
  }

  print('\n=== 示例程序结束 ===');
}

/// 高级用法示例 - 流式shell命令
Future<void> advancedUsageExample() async {
  final client = AdbClient.create(host: 'localhost');

  try {
    await client.connect();

    print('使用流式shell命令：');
    final shellStream = await client.openShell('logcat -d | head -10');

    // 监听标准输出
    shellStream.stdoutStream.listen((data) {
      print('LOG: $data');
    });

    // 监听标准错误
    shellStream.stderrStream.listen((data) {
      print('ERROR: $data');
    });

    // 等待命令完成
    final exitCode = await shellStream.exitCode;
    print('命令完成，退出码: $exitCode');

    await shellStream.close();
  } finally {
    await client.dispose();
  }
}
