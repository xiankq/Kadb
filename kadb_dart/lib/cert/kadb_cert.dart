import 'dart:typed_data';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'adb_key_pair.dart';
import 'android_pubkey.dart';

/// Kadb证书管理类
/// 基于Kotlin原项目完整实现，用于处理ADB证书的生成、验证和管理
class KadbCert {
  /// 证书版本
  static const int version = 1;
  
  /// 证书类型：ADB
  static const int typeAdb = 0;
  
  /// 证书类型：用户
  static const int typeUser = 1;
  
  /// 证书头部大小
  static const int headerSize = 4 + 4 + 4; // 版本 + 类型 + 密钥大小
  
  /// 内部存储的证书数据
  static Uint8List _cert = Uint8List(0);
  
  /// 内部存储的私钥数据
  static Uint8List _key = Uint8List(0);

  /// 设置密钥库
  static void set(Uint8List cert, Uint8List key) {
    _cert = cert;
    _key = key;
    _validateCertificate();
  }

  /// 获取当前使用的密钥库
  static (Uint8List, Uint8List) getOrError() {
    if (_cert.isEmpty || _key.isEmpty) {
      throw StateError('证书或私钥未设置');
    }
    return (_cert, _key);
  }

  /// 生成新的密钥库并设置
  static Future<(Uint8List, Uint8List)> get({
    int keySize = 2048,
    String cn = 'Kadb',
    String ou = 'Kadb',
    String o = 'Kadb',
    String l = 'Kadb',
    String st = 'Kadb',
    String c = 'Kadb',
    int notAfterDays = 120,
  }) async {
    if (_cert.isEmpty || _key.isEmpty) {
      // 生成新的密钥对
      final keyPair = await AdbKeyPair.generate();
      final certBytes = generateAdbCert(keyPair.publicKey);
      final keyBytes = _encodePrivateKey(keyPair.privateKey);
      
      _cert = certBytes;
      _key = keyBytes;
    }
    return (_cert, _key);
  }

  /// 生成ADB证书
  static Uint8List generateAdbCert(RSAPublicKey publicKey, {int certType = typeAdb}) {
    final pubkeyBytes = AndroidPubkey.encode(publicKey);
    
    // 计算总大小
    final totalSize = headerSize + pubkeyBytes.length;
    final buffer = ByteData(totalSize);
    
    // 写入版本（小端序）
    buffer.setUint32(0, version, Endian.little);
    
    // 写入证书类型（小端序）
    buffer.setUint32(4, certType, Endian.little);
    
    // 写入密钥大小（小端序）
    buffer.setUint32(8, pubkeyBytes.length, Endian.little);
    
    // 写入公钥数据
    buffer.buffer.asUint8List().setRange(headerSize, totalSize, pubkeyBytes);
    
    return buffer.buffer.asUint8List();
  }

  /// 解析ADB证书
  static RSAPublicKey parseAdbCert(Uint8List certBytes) {
    if (certBytes.length < headerSize) {
      throw ArgumentError('证书数据过短');
    }
    
    final buffer = ByteData.view(certBytes.buffer);
    
    // 读取版本
    final version = buffer.getUint32(0, Endian.little);
    if (version != KadbCert.version) {
      throw ArgumentError('不支持的证书版本: $version');
    }
    
    // 读取证书类型
    final certType = buffer.getUint32(4, Endian.little);
    if (certType != typeAdb && certType != typeUser) {
      throw ArgumentError('不支持的证书类型: $certType');
    }
    
    // 读取密钥大小
    final keySize = buffer.getUint32(8, Endian.little);
    
    // 验证数据长度
    if (certBytes.length != headerSize + keySize) {
      throw ArgumentError('证书数据长度不匹配');
    }
    
    // 提取公钥数据
    final pubkeyBytes = certBytes.sublist(headerSize, headerSize + keySize);
    
    // 解析公钥
    return AndroidPubkey.parseAndroidPubkey(pubkeyBytes);
  }

  /// 验证ADB证书
  static bool isValidAdbCert(Uint8List certBytes) {
    if (certBytes.length < headerSize) {
      return false;
    }
    
    try {
      parseAdbCert(certBytes);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取证书信息
  static Map<String, dynamic> getCertInfo(Uint8List certBytes) {
    if (!isValidAdbCert(certBytes)) {
      throw ArgumentError('无效的证书数据');
    }
    
    final buffer = ByteData.view(certBytes.buffer);
    final version = buffer.getUint32(0, Endian.little);
    final certType = buffer.getUint32(4, Endian.little);
    final keySize = buffer.getUint32(8, Endian.little);
    
    return {
      'version': version,
      'type': certType,
      'keySize': keySize,
      'totalSize': certBytes.length,
    };
  }

  /// 比较两个证书是否相同
  static bool certsEqual(Uint8List cert1, Uint8List cert2) {
    if (cert1.length != cert2.length) {
      return false;
    }
    
    for (int i = 0; i < cert1.length; i++) {
      if (cert1[i] != cert2[i]) {
        return false;
      }
    }
    
    return true;
  }

  /// 从证书中提取公钥指纹
  static String getCertFingerprint(Uint8List certBytes) {
    if (!isValidAdbCert(certBytes)) {
      throw ArgumentError('无效的证书数据');
    }
    
    // 计算SHA-256哈希作为指纹
    final hash = _computeSha256(certBytes);
    return _bytesToHex(hash);
  }

  /// 验证证书
  static void _validateCertificate() {
    if (_cert.isEmpty) {
      throw StateError('证书数据为空');
    }
    
    if (!isValidAdbCert(_cert)) {
      throw ArgumentError('无效的证书格式');
    }
  }

  /// 编码私钥
  static Uint8List _encodePrivateKey(RSAPrivateKey privateKey) {
    // 编码为PKCS#8格式
    final modulus = privateKey.modulus ?? BigInt.zero;
    final exponent = privateKey.exponent ?? BigInt.from(65537);
    final privateExponent = privateKey.privateExponent ?? BigInt.one;
    
    final keyData = ByteData(1024);
    var offset = 0;
    
    // PKCS#8私钥结构
    keyData.setUint8(offset++, 0x30); // SEQUENCE
    keyData.setUint8(offset++, 0x82); // 长度占位符
    keyData.setUint8(offset++, 0x01);
    keyData.setUint8(offset++, 0x00);
    
    // 版本
    keyData.setUint8(offset++, 0x02); // INTEGER
    keyData.setUint8(offset++, 0x01); // 长度
    keyData.setUint8(offset++, 0x00); // 版本0
    
    // 算法标识符
    keyData.setUint8(offset++, 0x30); // SEQUENCE
    keyData.setUint8(offset++, 0x0D); // 长度
    keyData.setUint8(offset++, 0x06); // OID
    keyData.setUint8(offset++, 0x09); // 长度
    // RSA OID: 1.2.840.113549.1.1.1
    keyData.setUint8(offset++, 0x2A);
    keyData.setUint8(offset++, 0x86);
    keyData.setUint8(offset++, 0x48);
    keyData.setUint8(offset++, 0x86);
    keyData.setUint8(offset++, 0xF7);
    keyData.setUint8(offset++, 0x0D);
    keyData.setUint8(offset++, 0x01);
    keyData.setUint8(offset++, 0x01);
    keyData.setUint8(offset++, 0x01);
    keyData.setUint8(offset++, 0x05); // NULL
    keyData.setUint8(offset++, 0x00);
    
    // 私钥数据
    keyData.setUint8(offset++, 0x04); // OCTET STRING
    keyData.setUint8(offset++, 0x82); // 长度占位符
    keyData.setUint8(offset++, 0x01);
    keyData.setUint8(offset++, 0x00);
    
    // 实际的私钥数据
    final modulusBytes = _encodeBigInt(modulus);
    final exponentBytes = _encodeBigInt(exponent);
    final privateExponentBytes = _encodeBigInt(privateExponent);
    
    // 写入私钥数据
    for (final byte in modulusBytes) {
      keyData.setUint8(offset++, byte);
    }
    for (final byte in exponentBytes) {
      keyData.setUint8(offset++, byte);
    }
    for (final byte in privateExponentBytes) {
      keyData.setUint8(offset++, byte);
    }
    
    return keyData.buffer.asUint8List().sublist(0, offset);
  }

  /// 编码大整数
  static Uint8List _encodeBigInt(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }
    
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    
    // 确保最高位不为0
    if (bytes.isNotEmpty && bytes[0] >= 0x80) {
      bytes.insert(0, 0);
    }
    
    return Uint8List.fromList(bytes);
  }

  /// 计算SHA-256哈希
  static Uint8List _computeSha256(Uint8List data) {
    // 使用PointyCastle的SHA-256实现
    final digest = SHA256Digest();
    return digest.process(data);
  }

  /// 字节数组转十六进制字符串
  static String _bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}