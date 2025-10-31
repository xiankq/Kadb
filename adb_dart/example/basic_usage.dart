/// AdbDart使用示例
/// 展示如何连接ADB设备并执行基本操作
library;

import 'package:adb_dart/adb_dart.dart';

void main() async {
  print('=== ADB Dart 示例 ===');

  // 创建ADB客户端实例
  final adb = AdbDart(
    host: '192.168.2.148',
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
