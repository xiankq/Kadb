/// AdbDart使用示例
/// 展示如何连接ADB设备并执行基本操作
library;

import 'package:adb_dart/adb_dart.dart';

void main() async {
  print('=== ADB Dart 示例 ===');

  // 创建ADB客户端实例
  final adb = AdbDart(
    host: '100.123.66.1',
    port: 5555,
  );

  try {
    // 建立连接
    print('正在连接ADB设备...');
    await adb.connect();
    print('✓ 连接成功');

    // 获取设备信息
    print('\n正在获取设备信息...');
    final deviceInfo = await adb.getDeviceInfo();
    print('设备信息:');
    print('  序列号: ${deviceInfo.serialNumber}');
    print('  型号: ${deviceInfo.model}');
    print('  厂商: ${deviceInfo.manufacturer}');
    print('  Android版本: ${deviceInfo.androidVersion}');
    print('  ADB版本: ${deviceInfo.adbVersion}');

    // 执行简单命令
    print('\n执行简单Shell命令:');
    final uptime = await adb.shell('uptime');
    print('设备运行时间: $uptime');

    final date = await adb.shell('date');
    print('系统时间: $date');

    // 获取已安装的应用包名
    print('\n获取已安装的应用...');
    final packages = await adb.shell('pm list packages | head -10');
    print('前10个应用包名:');
    packages.split('\n').forEach((pkg) => print('  $pkg'));

    // 获取屏幕分辨率
    print('\n获取屏幕信息...');
    final wmSize = await adb.shell('wm size');
    print('屏幕分辨率: $wmSize');

    final wmDensity = await adb.shell('wm density');
    print('屏幕密度: $wmDensity');

    print('\n=== 示例完成 ===');
  } catch (e) {
    print('错误: $e');
  } finally {
    // 断开连接
    await adb.disconnect();
    print('✓ 连接已断开');
  }
}

/// 另一个示例：交互式Shell
Future<void> interactiveShellExample() async {
  print('\n=== 交互式Shell示例 ===');

  final adb = AdbDart();

  try {
    await adb.connect();
    print('已连接到设备');

    // 打开交互式Shell
    final shellStream = await adb.openShell();
    print('已打开交互式Shell');

    // 发送命令
    await shellStream.writeString('ls /system/bin | head -5\n');
    final result = await shellStream.readString();
    print('系统bin目录前5个文件:');
    print(result);

    // 发送更多命令
    await shellStream.writeString('pwd\n');
    final pwd = await shellStream.readString();
    print('当前目录: $pwd');

    await shellStream.close();
  } catch (e) {
    print('交互式Shell错误: $e');
  } finally {
    await adb.disconnect();
  }
}

/// 设备管理示例
Future<void> deviceManagementExample() async {
  print('\n=== 设备管理示例 ===');

  final adb = AdbDart();

  try {
    await adb.connect();

    // 获取详细设备信息
    final info = await adb.getDeviceInfo();
    print('设备详细信息:');
    print(info);

    // 获取电池信息
    print('\n电池信息:');
    final batteryInfo = await adb.shell('dumpsys battery');
    print(batteryInfo);

    // 获取内存信息
    print('\n内存信息:');
    final memInfo = await adb.shell('cat /proc/meminfo');
    print(memInfo);

    // 获取CPU信息
    print('\nCPU信息:');
    final cpuInfo = await adb.shell('cat /proc/cpuinfo');
    print(cpuInfo);
  } catch (e) {
    print('设备管理错误: $e');
  } finally {
    await adb.disconnect();
  }
}
