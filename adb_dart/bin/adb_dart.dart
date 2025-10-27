import 'dart:io';
import 'package:adb_dart/adb_dart.dart';

/// ADB Dart客户端示例程序
void main(List<String> arguments) async {
  if (arguments.isEmpty) {
    print('用法：dart run adb_dart <命令> [参数]');
    print('可用命令：');
    print('  connect <host> [port] - 连接到ADB服务器');
    print('  shell <command> - 执行shell命令');
    print('  devices - 列出设备');
    print('  install <apk文件> - 安装APK');
    print('  uninstall <包名> - 卸载应用');
    return;
  }

  final command = arguments[0].toLowerCase();

  try {
    switch (command) {
      case 'connect':
        await _handleConnect(arguments);
        break;
      case 'shell':
        await _handleShell(arguments);
        break;
      case 'devices':
        await _handleDevices(arguments);
        break;
      case 'install':
        await _handleInstall(arguments);
        break;
      case 'uninstall':
        await _handleUninstall(arguments);
        break;
      default:
        print('未知命令：$command');
        print('使用 "dart run adb_dart" 查看可用命令');
    }
  } catch (e) {
    print('错误：$e');
    exit(1);
  }
}

/// 处理连接命令
Future<void> _handleConnect(List<String> arguments) async {
  if (arguments.length < 2) {
    print('用法：dart run adb_dart connect <host> [port]');
    return;
  }

  final host = arguments[1];
  final port = arguments.length > 2 ? int.parse(arguments[2]) : 5037;

  print('正在连接到 $host:$port...');

  final client = AdbClient.create(host: host, port: port);

  try {
    await client.connect();
    print('成功连接到ADB服务器');

    // 测试执行简单命令
    final result = await client.shell('echo "连接成功"');
    print('设备响应：${result.stdout.trim()}');

    await client.dispose();
  } catch (e) {
    print('连接失败：$e');
    exit(1);
  }
}

/// 处理shell命令
Future<void> _handleShell(List<String> arguments) async {
  if (arguments.length < 2) {
    print('用法：dart run adb_dart shell <命令>');
    return;
  }

  final command = arguments.sublist(1).join(' ');

  print('执行shell命令：$command');

  final client = AdbClient.create(host: 'localhost');

  try {
    await client.connect();
    final result = await client.shell(command);

    if (result.stdout.isNotEmpty) {
      print('输出：');
      print(result.stdout);
    }

    if (result.stderr.isNotEmpty) {
      print('错误：');
      print(result.stderr);
    }

    print('退出码：${result.exitCode}');

    await client.dispose();
  } catch (e) {
    print('执行命令失败：$e');
    exit(1);
  }
}

/// 处理设备列表命令
Future<void> _handleDevices(List<String> arguments) async {
  print('获取设备列表...');

  final client = AdbClient.create(host: 'localhost');

  try {
    await client.connect();

    // 使用adb devices命令获取设备列表
    final result = await client.shell('getprop ro.product.model');

    if (result.isSuccess) {
      print('已连接设备：');
      print('设备型号：${result.stdout.trim()}');
    } else {
      print('没有连接的设备');
    }

    await client.dispose();
  } catch (e) {
    print('获取设备列表失败：$e');
    exit(1);
  }
}

/// 处理安装命令
Future<void> _handleInstall(List<String> arguments) async {
  if (arguments.length < 2) {
    print('用法：dart run adb_dart install <apk文件>');
    return;
  }

  final apkFile = File(arguments[1]);

  if (!await apkFile.exists()) {
    print('错误：APK文件不存在：${apkFile.path}');
    exit(1);
  }

  print('正在安装：${apkFile.path}');

  final client = AdbClient.create(host: 'localhost');

  try {
    await client.connect();
    await client.install(apkFile);
    print('安装成功');
    await client.dispose();
  } catch (e) {
    print('安装失败：$e');
    exit(1);
  }
}

/// 处理卸载命令
Future<void> _handleUninstall(List<String> arguments) async {
  if (arguments.length < 2) {
    print('用法：dart run adb_dart uninstall <包名>');
    return;
  }

  final packageName = arguments[1];

  print('正在卸载：$packageName');

  final client = AdbClient.create(host: 'localhost');

  try {
    await client.connect();
    await client.uninstall(packageName);
    print('卸载成功');
    await client.dispose();
  } catch (e) {
    print('卸载失败：$e');
    exit(1);
  }
}
