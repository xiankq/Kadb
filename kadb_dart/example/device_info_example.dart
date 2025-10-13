import 'dart:async';
import 'package:kadb_dart/kadb_dart.dart';

/// 设备信息获取示例
/// 连接到指定ADB服务器并获取设备型号信息
void main() async {
  print('=== ADB设备信息获取示例 ===');

  final host = '192.168.2.32';
  final port = 5556;

  print('正在连接到 $host:$port...');

  try {
    // 加载或生成密钥对
    final keyPair = await CertUtils.loadKeyPair();

    // 连接到ADB服务器（使用密钥对进行认证）
    final connection = await KadbDart.connect(
      host: host,
      port: port,
      keyPair: keyPair,
    );

    print('✅ ADB连接建立成功');

    // 获取设备型号信息
    await _getDeviceModel(connection);

    // 关闭连接
    connection.close();
    print('✅ 连接已关闭');
  } catch (e) {
    print('❌ 连接失败: $e');
  }
}

/// 获取设备型号信息
Future<void> _getDeviceModel(AdbConnection connection) async {
  print('\n--- 获取设备型号信息 ---');

  try {
    // 执行getprop命令获取设备型号
    final shellStream = await KadbDart.executeShell(connection, 'getprop', [
      'ro.product.model',
    ]);

    // 监听标准错误
    shellStream.stderr.listen((data) {
      print('❌ Shell错误: $data');
    });

    // 监听退出码
    shellStream.exitCode.listen((code) {
      print('🔢 Shell退出码: $code');
    });

    // 等待命令执行完成（正确等待输出）
    final output = await shellStream.stdout.first;
    final deviceModel = output.trim();
    print('📱 设备型号: $deviceModel');

    // 关闭Shell流
    await shellStream.close();

    print('✅ 设备型号获取完成');
  } catch (e) {
    print('❌ 获取设备型号失败: $e');
  }
}

/// 获取更多设备信息
Future<void> _getDeviceInfo(AdbConnection connection) async {
  print('\n--- 获取完整设备信息 ---');

  // 定义要获取的设备属性列表
  final properties = {
    'ro.product.model': '设备型号',
    'ro.product.manufacturer': '制造商',
    'ro.product.brand': '品牌',
    'ro.build.version.release': 'Android版本',
    'ro.build.version.sdk': 'SDK版本',
    'ro.serialno': '序列号',
    'ro.product.name': '设备名称',
    'ro.hardware': '硬件平台',
    'ro.product.cpu.abi': 'CPU架构',
  };

  for (final entry in properties.entries) {
    try {
      final shellStream = await KadbDart.executeShell(connection, 'getprop', [
        entry.key,
      ]);

      // 收集输出数据
      final output = await shellStream.stdout.toList();
      final value = output.isNotEmpty ? output.join('').trim() : '未知';

      print('${entry.value}: $value');

      await shellStream.close();
    } catch (e) {
      print('❌ 获取${entry.value}失败: $e');
    }

    // 短暂延迟避免请求过快
    await Future.delayed(Duration(milliseconds: 100));
  }

  print('✅ 设备信息获取完成');
}
