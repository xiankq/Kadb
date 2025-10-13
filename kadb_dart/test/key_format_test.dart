import 'dart:io';
import 'package:kadb_dart/kadb_dart.dart';
import 'package:kadb_dart/cert/cert_utils.dart';

void main() async {
  print('=== ADB公钥格式测试 ===');

  try {
    // 生成密钥对
    print('1. 生成密钥对...');
    final keyPair = await AdbKeyPair.generate();
    print('✅ 密钥对生成完成');

    // 生成ADB格式公钥
    print('\n2. 生成ADB格式公钥...');
    final adbPublicKeyBytes = CertUtils.generateAdbPublicKeyBytesForTest(keyPair);

    print('ADB公钥字节长度: ${adbPublicKeyBytes.length}');
    print('ADB公钥内容: ${String.fromCharCodes(adbPublicKeyBytes)}');

    // 保存到文件
    print('\n3. 保存到文件...');
    final file = File('/tmp/test_adbkey.pub');
    await file.writeAsBytes(adbPublicKeyBytes);
    print('✅ 已保存到: ${file.path}');

    // 显示格式详情
    final content = String.fromCharCodes(adbPublicKeyBytes);
    final parts = content.split(' ');
    if (parts.length >= 2) {
      print('\n📋 公钥格式分析:');
      print('Base64部分: ${parts[0].substring(0, 50)}...');
      print('设备标识符: ${parts[1]}');
      print('总长度: ${content.length} 字符');
    }

  } catch (e) {
    print('❌ 测试失败: $e');
  }
}