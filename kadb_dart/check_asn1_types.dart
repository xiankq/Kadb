import 'dart:convert';
import 'dart:typed_data';
import 'package:asn1lib/asn1lib.dart';

void main() {
  print('检查ASN.1时间类可用性:');
  
  // 检查asn1lib库中实际可用的类
  print('检查可用类:');
  print('  - ASN1Object: ${ASN1Object}');
  print('  - ASN1Sequence: ${ASN1Sequence}');
  print('  - ASN1OctetString: ${ASN1OctetString}');
  print('  - ASN1Integer: ${ASN1Integer}');
  
  // 检查是否有时间相关的类
  try {
    // 尝试使用ASN1GeneralizedTime
    final timeBytes = Uint8List.fromList([0x18, 0x0F, 0x32, 0x30, 0x32, 0x35, 0x31, 0x30, 0x31, 0x32, 0x30, 0x34, 0x30, 0x37, 0x5A]);
    final timeObj = ASN1Parser(timeBytes).nextObject();
    print('时间对象类型: ${timeObj.runtimeType}');
    print('时间对象: $timeObj');
    
    // 检查时间对象的属性
    if (timeObj is ASN1OctetString) {
      print('时间对象是ASN1OctetString');
      final timeString = String.fromCharCodes(timeObj.valueBytes());
      print('时间字符串: $timeString');
    }
  } catch (e) {
    print('时间对象解析错误: $e');
  }
  
  // 检查asn1lib库中是否有时间类
  print('检查时间类可用性:');
  try {
    // 尝试创建时间对象
    final testBytes = Uint8List.fromList(utf8.encode('202510120407Z'));
    final testObj = ASN1OctetString(testBytes);
    print('创建ASN1OctetString成功: ${testObj.runtimeType}');
  } catch (e) {
    print('创建时间对象错误: $e');
  }
}