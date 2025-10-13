import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:kadb_dart/cert/adb_key_pair.dart';

/// 证书工具类 - 简化的缓存机制实现
class CertUtils {
  
  // 持久化缓存目录 - 与真实ADB一致，放在项目根目录的.android文件夹中
  static const String _cacheDir = '.android';
  static const String _privateKeyFile = '$_cacheDir/adbkey';
  static const String _certificateFile = '$_cacheDir/adbkey.pub';
  
  /// 加载或生成ADB密钥对 - 核心缓存机制
  /// [cacheDir] 缓存目录路径，默认为'.android'
  /// 返回AdbKeyPair对象
  static Future<AdbKeyPair> loadKeyPair({String cacheDir = '.android'}) async {
    final privateKeyFile = '$cacheDir/adbkey';
    final certificateFile = '$cacheDir/adbkey.pub';
    
    // 检查文件缓存是否存在
    final privateKeyFileObj = File(privateKeyFile);
    final certificateFileObj = File(certificateFile);
    
    if (privateKeyFileObj.existsSync() && certificateFileObj.existsSync()) {
      try {
        final privateKey = privateKeyFileObj.readAsStringSync();
        final keyPair = await AdbKeyPair.fromPrivateKeyPem(privateKey);
        print('使用缓存证书');
        return keyPair;
      } catch (e) {
        print('缓存证书无效，重新生成: $e');
      }
    }
    
    // 缓存不存在或无效，生成新的密钥对
    final keyPair = await AdbKeyPair.generate();
    
    // 创建缓存目录
    final dir = Directory(cacheDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    
    // 保存到文件
    privateKeyFileObj.writeAsStringSync(keyPair.toPrivateKeyPem());
    certificateFileObj.writeAsStringSync(keyPair.toPublicKeySsh());
    
    print('生成新的密钥对并保存到文件缓存');
    return keyPair;
  }
  
  /// 编码公钥并附加名称信息 - 与Kotlin版本一致
  /// [publicKey] 公钥对象
  /// [name] 设备名称
  /// 返回编码后的字节数组
  static Uint8List encodeWithName(dynamic publicKey, String name) {
    // 简化实现：将公钥转换为PEM格式，然后附加名称信息
    final publicKeyPem = publicKey.toPublicKeyPem();
    final nameBytes = utf8.encode(' $name\u0000');
    
    // 合并公钥和名称信息
    final result = Uint8List(publicKeyPem.length + nameBytes.length);
    result.setRange(0, publicKeyPem.length, publicKeyPem.codeUnits);
    result.setRange(publicKeyPem.length, result.length, nameBytes);
    
    return result;
  }
}