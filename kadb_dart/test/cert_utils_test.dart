import 'dart:io';
import 'package:kadb_dart/cert/cert_utils.dart';
import 'package:test/test.dart';

void main() {
  group('CertUtils 测试', () {
    test('密钥对生成和保存到项目目录', () async {
      // 清理可能存在的测试文件
      final privateKeyFile = File('kadb_dart/adbkey');
      final certFile = File('kadb_dart/adbkey.pub');
      
      if (privateKeyFile.existsSync()) {
        privateKeyFile.deleteSync();
      }
      if (certFile.existsSync()) {
        certFile.deleteSync();
      }
      
      // 生成密钥对
      final keyPair = await CertUtils.generate(
        keySize: 2048,
        cn: 'TestKadb',
        ou: 'TestKadb',
        o: 'TestKadb',
        l: 'TestKadb',
        st: 'TestKadb',
        c: 'TestKadb',
        notAfterDays: 30,
      );
      
      // 验证密钥对已保存到项目目录
      expect(privateKeyFile.existsSync(), isTrue, reason: '私钥文件应保存在项目目录');
      expect(certFile.existsSync(), isTrue, reason: '证书文件应保存在项目目录');
      
      // 验证不会污染全局环境
      final globalPrivateKeyFile = File('${Platform.environment['HOME']}/.android/adbkey');
      final globalCertFile = File('${Platform.environment['HOME']}/.android/adbkey.pub');
      
      expect(globalPrivateKeyFile.existsSync(), isFalse, reason: '不应污染全局私钥文件');
      expect(globalCertFile.existsSync(), isFalse, reason: '不应污染全局证书文件');
      
      // 验证可以正确加载保存的密钥对
      final loadedKeyPair = await CertUtils.loadKeyPair();
      expect(loadedKeyPair, isNotNull, reason: '应能正确加载保存的密钥对');
      
      // 清理测试文件
      if (privateKeyFile.existsSync()) {
        privateKeyFile.deleteSync();
      }
      if (certFile.existsSync()) {
        certFile.deleteSync();
      }
    });
    
    test('证书验证功能', () {
      // 测试证书验证功能
      expect(() => CertUtils.validateCertificate(), throwsA(isA<Exception>()),
          reason: '当证书不存在时应抛出异常');
    });
  });
}