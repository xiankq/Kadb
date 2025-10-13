import 'package:kadb_dart/cert/android_pubkey.dart';

void main() {
  print('签名填充长度: ${AndroidPubkey.signaturePadding.length}');
  print(
    '0xff数量: ${AndroidPubkey.signaturePadding.where((b) => b == 0xff).length}',
  );

  // 验证填充内容
  final padding = AndroidPubkey.signaturePadding;
  print(
    '开头字节: 0x${padding[0].toRadixString(16)} 0x${padding[1].toRadixString(16)}',
  );
  print(
    '结尾字节: 0x${padding[padding.length - 2].toRadixString(16)} 0x${padding[padding.length - 1].toRadixString(16)}',
  );

  // 验证填充结构
  print('填充结构:');
  print(
    '0x00, 0x01, [218个0xff], 0x00, 0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14',
  );
}
