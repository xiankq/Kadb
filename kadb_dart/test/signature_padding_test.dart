import 'package:kadb_dart/cert/android_pubkey.dart';
import 'package:kadb_dart/cert/cert_utils.dart';
import 'package:test/test.dart';
import 'dart:io';

void main() {
  group('签名填充验证', () {
    test('签名填充长度与Kotlin版本一致', () {
      // 验证签名填充长度
      expect(AndroidPubkey.signaturePadding.length, equals(236));
      
      // 验证0xff的数量
      final ffCount = AndroidPubkey.signaturePadding.where((b) => b == 0xff).length;
      expect(ffCount, equals(218), reason: 'Kotlin版本有218个0xff，Dart版本应该有相同数量');
      
      // 验证开头和结尾
      expect(AndroidPubkey.signaturePadding[0], equals(0x00));
      expect(AndroidPubkey.signaturePadding[1], equals(0x01));
      
      // 验证结尾部分
      expect(AndroidPubkey.signaturePadding[220], equals(0x00));
      expect(AndroidPubkey.signaturePadding[221], equals(0x30));
      expect(AndroidPubkey.signaturePadding[235], equals(0x14));
    });
  });

  group('缓存机制验证', () {
    test('证书缓存和复用功能', () async {
      // 第一次生成密钥对
      final keyPair1 = await CertUtils.loadKeyPair(cacheDir: '.android');
      expect(keyPair1, isNotNull);
      expect(keyPair1.privateKey, isNotNull);
      expect(keyPair1.publicKey, isNotNull);
      
      // 第二次加载应该复用缓存
      final keyPair2 = await CertUtils.loadKeyPair(cacheDir: '.android');
      expect(keyPair2, isNotNull);
      
      // 验证公钥一致
      final pubKey1 = keyPair1.publicKeyBytes;
      final pubKey2 = keyPair2.publicKeyBytes;
      expect(pubKey1.length, equals(pubKey2.length));
      expect(pubKey1, equals(pubKey2));
    });
    
    test('缓存文件存在性验证', () async {
      final keyPair = await CertUtils.loadKeyPair(cacheDir: '.android');
      expect(keyPair, isNotNull);
      
      // 验证缓存文件存在
      final privateKeyFile = File('.android/adbkey');
      final publicKeyFile = File('.android/adbkey.pub');
      
      expect(privateKeyFile.existsSync(), isTrue);
      expect(publicKeyFile.existsSync(), isTrue);
    });
  });
}