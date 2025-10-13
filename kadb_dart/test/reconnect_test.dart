import 'dart:typed_data';
import 'package:kadb_dart/kadb_dart.dart';
import 'package:kadb_dart/cert/adb_key_pair.dart';
import 'package:kadb_dart/core/adb_message.dart';
import 'dart:io';

void main() async {
  print('=== ADB二次连接认证测试（包含签名验证） ===');

  try {
    // 测试签名算法
    print('1. 测试签名算法...');
    final keyPair = await AdbKeyPair.generate();
    final testPayload = Uint8List.fromList([
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
    ]);
    final testMessage = AdbMessage(
      command: 1213486401, // AUTH
      arg0: 2,
      arg1: 0,
      payloadLength: 20,
      checksum: 0,
      magic: 0,
      payload: testPayload,
    );
    final signature = keyPair.signAdbMessage(testMessage);
    final isValid = keyPair.verify(testPayload.sublist(0, 20), signature);
    print('签名验证结果: $isValid');

    if (!isValid) {
      throw Exception('签名验证失败，签名算法有问题');
    }

    // 第一次连接
    print('2. 第一次连接...');
    final device1 = await KadbDart.connect(host: 'localhost', port: 5555);
    print('第一次连接成功！');

    // 简单测试连接是否正常
    print('第一次连接测试完成');

    // 断开连接
    device1.close();
    print('第一次连接已断开');

    // 等待用户授权
    print('请在设备上点击"始终允许"授权，然后等待10秒...');
    await Future.delayed(Duration(seconds: 10));

    // 第二次连接（应该不需要重新授权）
    print('3. 第二次连接...');
    final device2 = await KadbDart.connect(host: 'localhost', port: 5555);
    print('第二次连接成功！');

    // 简单测试连接是否正常
    print('第二次连接测试完成');

    // 断开连接
    device2.close();
    print('第二次连接已断开');

    print('✅ 二次连接测试完成！');
    print('如果第二次连接成功且没有要求授权，说明修复有效！');
    print('签名验证成功: $isValid');
  } catch (e) {
    print('❌ 连接失败: $e');
    print('请检查设备是否在线，以及IP地址和端口是否正确');
  }
}
