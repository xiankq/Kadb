/// ADB设备信息获取示例
library;

import 'dart:async';
import 'package:kadb_dart/kadb_dart.dart';

void main() async {
  final host = '192.168.2.32';
  final port = 5556;

  try {
    final keyPair = await CertUtils.loadKeyPair();
    final connection = await KadbDart.create(
      host: host,
      port: port,
      keyPair: keyPair,
    );

    await _getDeviceModel(connection);
    connection.close();
  } catch (e) {
    print('连接失败: $e');
  }
}

Future<void> _getDeviceModel(AdbConnection connection) async {
  try {
    final shellStream = await KadbDart.executeShell(
      connection,
      'getprop',
      args: ['ro.product.model'],
    );

    String deviceModel = '';
    shellStream.stdout.listen((data) {
      deviceModel = data.trim();
    });

    await for (final _ in shellStream.stdout) {
      break;
    }
    await shellStream.close();

    if (deviceModel.isNotEmpty) {
      print('设备型号: $deviceModel');
    }
  } catch (e) {
    print('获取设备型号失败: $e');
  }
}
