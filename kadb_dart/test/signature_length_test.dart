import 'package:kadb_dart/cert/android_pubkey.dart';

void main() {
  print('签名填充长度: ${AndroidPubkey.signaturePadding.length}');
  
  // 验证签名填充内容
  final padding = AndroidPubkey.signaturePadding;
  print('开头字节: 0x${padding[0].toRadixString(16)} 0x${padding[1].toRadixString(16)}');
  print('结尾字节: 0x${padding[padding.length-16].toRadixString(16)} ... 0x${padding[padding.length-1].toRadixString(16)}');
  
  // 检查0xff的数量
  int ffCount = 0;
  for (int i = 0; i < padding.length; i++) {
    if (padding[i] == 0xff) ffCount++;
  }
  print('0xff字节数量: $ffCount');
  
  // 验证总长度
  print('总字节数: ${padding.length}');
  print('期望长度: 2(开头) + $ffCount(0xff) + 16(结尾) = ${2 + ffCount + 16}');
}