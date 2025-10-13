import 'dart:typed_data';
import 'package:kadb_dart/kadb_dart.dart';

void main() async {
  print('=== 改进的ADB二次连接认证测试 ===');

  try {
    // 生成密钥对
    print('1. 生成ADB密钥对...');
    final keyPair = await AdbKeyPair.generate();

    // 测试新的签名方法
    print('2. 测试新的payload签名方法...');
    final testPayload = Uint8List.fromList([
      1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
      11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    ]);

    final signature = keyPair.signAdbMessagePayload(testPayload);
    final isValid = keyPair.verify(testPayload, signature);
    print('新签名方法验证结果: $isValid');

    if (!isValid) {
      throw Exception('新签名方法验证失败');
    }

    // 第一次连接
    print('3. 第一次连接...');
    final device1 = await KadbDart.connect(
      host: 'localhost',
      port: 5555,
      keyPair: keyPair,
    );
    print('第一次连接成功！');

    // 通过执行简单命令来验证连接
    final shellStream = await KadbDart.executeShell(device1, 'getprop ro.product.model');
    final deviceModel = await shellStream.readAll();
    print('设备型号: ${deviceModel.trim()}');
    await shellStream.close();

    // 断开连接
    device1.close();
    print('第一次连接已断开');

    // 等待用户授权（如果需要）
    print('如果设备弹出授权对话框，请点击"始终允许"授权...');
    await Future.delayed(Duration(seconds: 5));

    // 第二次连接（应该不需要重新授权）
    print('4. 第二次连接...');
    final device2 = await KadbDart.connect(
      host: 'localhost',
      port: 5555,
      keyPair: keyPair, // 使用相同的密钥对
    );
    print('第二次连接成功！');

    // 验证第二次连接
    final shellStream2 = await KadbDart.executeShell(device2, 'getprop ro.product.model');
    final deviceModel2 = await shellStream2.readAll();
    print('设备型号: ${deviceModel2.trim()}');
    await shellStream2.close();

    // 断开连接
    device2.close();
    print('第二次连接已断开');

    print('✅ 二次连接测试完成！');
    print('如果第二次连接成功且没有要求授权，说明修复有效！');

  } catch (e) {
    print('❌ 连接失败: $e');
    print('请检查设备是否在线，以及IP地址和端口是否正确');
  }
}