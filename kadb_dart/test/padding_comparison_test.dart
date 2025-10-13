import 'dart:typed_data';
import 'package:kadb_dart/cert/android_pubkey.dart';

void main() {
  print('=== 签名填充对比测试 ===');

  print('我们的SIGNATURE_PADDING:');
  print('长度: ${AndroidPubkey.signaturePadding.length}');
  print('内容: ${AndroidPubkey.signaturePadding.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

  print('\n期望的填充格式（PKCS#1 SHA1）:');
  print('0x00 0x01 [0xff填充] 0x00 [SHA1标识符]');

  print('\nSHA1标识符应该是:');
  print('0x30 0x21 0x30 0x09 0x06 0x05 0x2b 0x0e 0x03 0x02 0x1a 0x05 0x00 0x04 0x14');

  // 检查我们的填充结尾
  final ourEnding = AndroidPubkey.signaturePadding.sublist(AndroidPubkey.signaturePadding.length - 15);
  print('\n我们的填充结尾:');
  print('${ourEnding.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

  // 验证SHA1标识符
  final expectedSha1Identifier = [
    0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e,
    0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14
  ];

  final ourSha1Identifier = AndroidPubkey.signaturePadding.sublist(
    AndroidPubkey.signaturePadding.length - 15
  );

  bool matches = true;
  for (int i = 0; i < expectedSha1Identifier.length; i++) {
    if (ourSha1Identifier[i] != expectedSha1Identifier[i]) {
      matches = false;
      print('❌ SHA1标识符不匹配！位置$i: 期望${expectedSha1Identifier[i].toRadixString(16)}, 实际${ourSha1Identifier[i].toRadixString(16)}');
    }
  }

  if (matches) {
    print('✅ SHA1标识符匹配正确！');
  }

  // 检查填充长度
  final expectedLength = 2 + 218 + 1 + 15; // 0x00 0x01 + 218个0xff + 0x00 + 15字节SHA1标识符 = 236
  if (AndroidPubkey.signaturePadding.length == expectedLength) {
    print('✅ 填充长度正确: ${AndroidPubkey.signaturePadding.length}');
  } else {
    print('❌ 填充长度错误: 期望${expectedLength}, 实际${AndroidPubkey.signaturePadding.length}');
  }
}