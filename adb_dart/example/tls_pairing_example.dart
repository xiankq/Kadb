/// TLS安全配对示例
/// 演示如何使用TLS加密进行设备配对
library tls_pairing_example;

import 'dart:io';
import 'package:adb_dart/adb_dart.dart';
import 'package:adb_dart/src/cert/adb_key_pair.dart';

/// TLS安全配对示例
class TlsPairingExample {

  /// 运行配对示例
  static Future<void> runExample() async {
    print('=== ADB Dart TLS安全配对示例 ===\n');

    // 生成或加载RSA密钥对
    print('生成RSA密钥对...');
    final keyPair = AdbKeyPair.generate(
      keySize: 2048,
      commonName: 'adb_dart_example',
    );
    print('RSA密钥对生成完成\n');

    // 读取配对信息
    final host = await _readInput('请输入设备IP地址 (默认: 192.168.1.100): ') ?? '192.168.1.100';
    final port = int.tryParse(await _readInput('请输入设备端口 (默认: 5555): ') ?? '5555') ?? 5555;
    final pairingCode = await _readInput('请输入配对码 (6位数字): ');
    final deviceName = await _readInput('请输入设备名称 (默认: adb_dart_example): ') ?? 'adb_dart_example';

    // 验证配对码格式
    if (pairingCode == null || !TlsDevicePairingManager.validatePairingCode(pairingCode)) {
      print('❌ 配对码格式错误，请输入6位数字');
      return;
    }

    print('\n=== 开始安全配对 ===');
    print('目标设备: $host:$port');
    print('设备名称: $deviceName');
    print('配对码: ****${pairingCode.substring(4)}\n');

    try {
      // 执行安全配对
      await TlsDevicePairingManager.pairDeviceSecurely(
        host: host,
        port: port,
        pairingCode: pairingCode,
        keyPair: keyPair,
        deviceName: deviceName,
        useTls: true, // 启用TLS加密
      );

      print('\n✅ 配对成功！设备已安全连接。');
      print('现在可以使用ADB功能了。\n');

      // 演示配对成功后的ADB操作
      await _demoAdbOperations(host, port, keyPair);

    } catch (e) {
      print('\n❌ 配对失败: $e');
      print('请检查:');
      print('  - 设备是否已启用ADB调试');
      print('  - 设备是否在配对模式');
      print('  - 配对码是否正确');
      print('  - 网络连接是否正常');
    }
  }

  /// 演示ADB操作
  static Future<void> _demoAdbOperations(String host, int port, AdbKeyPair keyPair) async {
    print('=== 演示ADB操作 ===\n');

    final adb = AdbDart(
      host: host,
      port: port,
      keyPair: keyPair,
    );

    try {
      // 连接设备
      print('连接到设备...');
      await adb.connect();
      print('✅ 连接成功\n');

      // 获取设备信息
      print('获取设备信息...');
      final deviceInfo = await adb.getDeviceInfo();
      print('设备信息:');
      print('  型号: ${deviceInfo.model}');
      print('  厂商: ${deviceInfo.manufacturer}');
      print('  Android版本: ${deviceInfo.androidVersion}');
      print('  ADB版本: ${deviceInfo.adbVersion}');
      print('');

      // 执行简单命令
      print('执行设备命令: "getprop ro.product.model"');
      final result = await adb.shell('getprop ro.product.model');
      print('命令输出: $result\n');

      print('✅ ADB操作演示完成');

    } catch (e) {
      print('❌ ADB操作失败: $e');
    } finally {
      await adb.disconnect();
    }
  }

  /// 生成配对二维码
  static void generateQrCode() {
    print('\n=== 生成配对二维码 ===\n');

    final host = '192.168.1.100';
    final port = 5555;
    final deviceName = 'example_device';

    final qrContent = TlsDevicePairingManager.generatePairingQrContent(
      host: host,
      port: port,
      deviceName: deviceName,
    );

    print('配对二维码内容:');
    print(qrContent);
    print('');
    print('用户可以使用支持ADB配对的扫码工具扫描此二维码进行快速配对。');
  }

  /// 读取用户输入
  static Future<String?> _readInput(String prompt) async {
    stdout.write(prompt);
    final input = stdin.readLineSync();
    return input?.trim().isEmpty ?? true ? null : input!.trim();
  }
}

/// 主函数
void main() async {
  print('ADB Dart TLS配对示例程序');
  print('========================\n');

  // 显示菜单
  while (true) {
    print('请选择操作:');
    print('1. 运行TLS配对示例');
    print('2. 生成配对二维码');
    print('3. 退出');
    print('');

    final choice = await TlsPairingExample._readInput('请输入选项 (1-3): ');

    switch (choice) {
      case '1':
        await TlsPairingExample.runExample();
        break;
      case '2':
        TlsPairingExample.generateQrCode();
        break;
      case '3':
        print('再见！');
        return;
      default:
        print('❌ 无效选项，请重新选择。\n');
        continue;
    }

    print('\n${'=' * 50}\n');
  }
}