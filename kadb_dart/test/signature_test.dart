import 'dart:typed_data';
import 'package:kadb_dart/cert/adb_key_pair.dart';
import 'package:kadb_dart/core/adb_message.dart';

void main() async {
  print('=== ADB签名算法测试 ===');

  try {
    // 生成测试密钥对
    print('1. 生成测试密钥对...');
    final keyPair = await AdbKeyPair.generate();
    print('密钥对生成成功');

    // 测试签名和验证
    print('2. 测试签名和验证...');
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

    // 签名
    final signature = keyPair.signAdbMessage(testMessage);
    print('签名生成成功，签名长度: ${signature.length}');

    // 验证签名
    final isValid = keyPair.verify(testPayload.sublist(0, 20), signature);
    print('签名验证结果: $isValid');

    if (isValid) {
      print('✅ 签名算法测试通过！');
      print('签名填充和RSA算法实现正确');
    } else {
      print('❌ 签名算法测试失败');
      print('签名验证失败，需要检查签名填充和RSA实现');
    }

    // 测试不同长度的消息
    print('3. 测试不同长度的消息...');
    for (int length in [10, 15, 20]) {
      final payload = Uint8List(length);
      for (int i = 0; i < length; i++) {
        payload[i] = i % 256;
      }

      final message = AdbMessage(
        command: 1213486401,
        arg0: 2,
        arg1: 0,
        payloadLength: length,
        checksum: 0,
        magic: 0,
        payload: payload,
      );

      final sig = keyPair.signAdbMessage(message);
      final valid = keyPair.verify(payload.sublist(0, length), sig);
      print('长度 $length 字节: $valid');
    }

    print('测试完成');
  } catch (e) {
    print('测试失败: $e');
  }
}
