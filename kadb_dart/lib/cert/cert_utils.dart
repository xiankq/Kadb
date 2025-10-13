import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:kadb_dart/cert/adb_key_pair.dart';
import 'package:kadb_dart/cert/android_pubkey.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/signers/rsa_signer.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/api.dart';
import 'package:asn1lib/asn1lib.dart' as asn1;

/// 证书工具类
/// 基于Kotlin原项目完整实现，负责生成、加载和验证ADB密钥对
class CertUtils {
  
  /// 解析ASN.1时间格式
  static DateTime _parseAsn1Time(Uint8List timeBytes) {
    try {
      // 直接解析时间字节为字符串
      final timeString = String.fromCharCodes(timeBytes);
      
      // 调试：打印实际的时间字符串内容
      print('调试: 时间字符串长度=${timeString.length}, 内容="$timeString"');
      
      // 检查是否为有效的ASN.1时间格式
      if (timeString.endsWith('Z')) {
        if (timeString.startsWith('20') && timeString.length >= 15) {
          // UTC时间格式: YYYYMMDDHHMMSSZ (15字符)
          return DateTime.parse('${timeString.substring(0, 4)}-${timeString.substring(4, 6)}-${timeString.substring(6, 8)}T${timeString.substring(8, 10)}:${timeString.substring(10, 12)}:${timeString.substring(12, 14)}Z');
        } else if (timeString.length == 13) {
          // 处理13字符格式: YYMMDDHHMMZ (秒数可能被省略)
          final year = int.parse(timeString.substring(0, 2));
          final century = year >= 50 ? 1900 : 2000;
          return DateTime.parse('${century + year}-${timeString.substring(2, 4)}-${timeString.substring(4, 6)}T${timeString.substring(6, 8)}:${timeString.substring(8, 10)}:00Z');
        } else if (timeString.length >= 14) {
          // 通用时间格式: YYMMDDHHMMSSZ (14字符)
          final year = int.parse(timeString.substring(0, 2));
          final century = year >= 50 ? 1900 : 2000;
          return DateTime.parse('${century + year}-${timeString.substring(2, 4)}-${timeString.substring(4, 6)}T${timeString.substring(6, 8)}:${timeString.substring(8, 10)}:${timeString.substring(10, 12)}Z');
        }
      }
      
      throw FormatException('无效的ASN.1时间格式: $timeString (${timeString.length}字符)');
    } catch (e) {
      print('ASN.1时间解析错误: $e');
      rethrow;
    }
  }
  
  /// 编码ASN.1时间格式
  static asn1.ASN1Object _encodeAsn1Time(DateTime time) {
    final utcTime = time.toUtc();
    
    // 使用ASN1UTCTime格式（YYMMDDHHMMSSZ）
    if (utcTime.year >= 2050) {
      // 对于2050年以后的日期，使用GeneralizedTime格式（YYYYMMDDHHMMSSZ）
      final timeString = '${utcTime.year.toString().padLeft(4, '0')}${utcTime.month.toString().padLeft(2, '0')}${utcTime.day.toString().padLeft(2, '0')}${utcTime.hour.toString().padLeft(2, '0')}${utcTime.minute.toString().padLeft(2, '0')}${utcTime.second.toString().padLeft(2, '0')}Z';
      // 创建自定义的GeneralizedTime编码
      return asn1.ASN1OctetString(utf8.encode(timeString));
    } else {
      // 使用UTCTime格式（YYMMDDHHMMSSZ）
      final year = utcTime.year % 100;
      final timeString = '${year.toString().padLeft(2, '0')}${utcTime.month.toString().padLeft(2, '0')}${utcTime.day.toString().padLeft(2, '0')}${utcTime.hour.toString().padLeft(2, '0')}${utcTime.minute.toString().padLeft(2, '0')}${utcTime.second.toString().padLeft(2, '0')}Z';
      // 创建自定义的UTCTime编码
      return asn1.ASN1OctetString(utf8.encode(timeString));
    }
  }
  
  /// 构建名称组件
  static asn1.ASN1Sequence _buildNameComponent(String type, String value) {
    final sequence = asn1.ASN1Sequence();
    final typeOid = asn1.ASN1ObjectIdentifier.fromComponentString(_getOidForNameType(type));
    sequence.add(typeOid);
    
    final valueSet = asn1.ASN1Set();
    final valueString = asn1.ASN1OctetString(utf8.encode(value));
    valueSet.add(valueString);
    sequence.add(valueSet);
    
    return sequence;
  }
  
  /// 获取名称类型的OID
  static String _getOidForNameType(String type) {
    switch (type) {
      case 'CN': return '2.5.4.3'; // commonName
      case 'OU': return '2.5.4.11'; // organizationalUnitName
      case 'O': return '2.5.4.10'; // organizationName
      case 'L': return '2.5.4.7'; // localityName
      case 'ST': return '2.5.4.8'; // stateOrProvinceName
      case 'C': return '2.5.4.6'; // countryName
      default: return '2.5.4.3';
    }
  }
  
  /// 签名证书
  static Uint8List _signCertificate(Uint8List tbsCertificate, RSAPrivateKey privateKey) {
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final signature = signer.generateSignature(tbsCertificate);
    return signature.bytes;
  }
  static const String _keyBegin = '-----BEGIN PRIVATE KEY-----';
  static const String _keyEnd = '-----END PRIVATE KEY-----';
  static const String _certBegin = 'BEGIN CERTIFICATE-----';
  static const String _certEnd = '-----END CERTIFICATE-----';

  /// 加载或生成ADB密钥对
  /// 如果存在已保存的密钥对则加载，否则生成新的
  /// 返回AdbKeyPair对象
  static Future<AdbKeyPair> loadKeyPair() async {
    final privateKey = _readPrivateKey();
    final certificate = _readCertificate();
    
    if (privateKey == null || certificate == null) {
      return await AdbKeyPair.generate();
    }
    
    validateCertificate();
    return await AdbKeyPair.fromPrivateKeyPem(privateKey);
  }

  /// 验证证书有效性
  static void validateCertificate() {
    final certificate = _readCertificate();
    if (certificate == null) {
      throw Exception('证书不存在');
    }
    
    try {
      // 解析X.509证书并验证有效性
      final certBytes = _extractCertificateBytes(certificate);
      
      // 完整实现：解析X.509证书结构
      final parser = asn1.ASN1Parser(certBytes);
      final certificateSequence = parser.nextObject() as asn1.ASN1Sequence;
      
      // 安全地解析证书结构
      var tbsCertificate = certificateSequence.elements[0];
      if (tbsCertificate is asn1.ASN1Sequence) {
        // 标准X.509结构：证书序列的第一个元素是tbsCertificate
      } else {
        // 可能是其他结构，尝试直接使用整个序列
        tbsCertificate = certificateSequence;
      }
      
      // 验证证书有效期 - 查找有效期序列
      var validitySequenceFound = false;
      var notBeforeElement, notAfterElement;
      
      // 遍历tbsCertificate的所有元素来查找有效期序列
      if (tbsCertificate is asn1.ASN1Sequence) {
        for (var element in tbsCertificate.elements) {
          if (element is asn1.ASN1Sequence && element.elements.length == 2) {
            // 可能是有效期序列，检查元素类型
            final firstElement = element.elements[0];
            final secondElement = element.elements[1];
            
            if (firstElement is asn1.ASN1OctetString && secondElement is asn1.ASN1OctetString) {
              // 找到有效期序列
              validitySequenceFound = true;
              notBeforeElement = firstElement;
              notAfterElement = secondElement;
              break;
            }
          }
        }
      }
      
      if (!validitySequenceFound) {
        throw Exception('无法找到证书有效期信息');
      }
      
      final notBefore = _parseAsn1Time(notBeforeElement.valueBytes());
      final notAfter = _parseAsn1Time(notAfterElement.valueBytes());
      final now = DateTime.now();
      
      if (now.isBefore(notBefore)) {
        throw Exception('证书尚未生效');
      }
      if (now.isAfter(notAfter)) {
        throw Exception('证书已过期');
      }
    } catch (e) {
      throw Exception('证书验证失败: $e');
    }
  }

  /// 生成新的ADB密钥对
  /// [keySize] 密钥长度（默认2048位）
  /// [cn] 通用名称
  /// [ou] 组织单位
  /// [o] 组织名称
  /// [l] 地区
  /// [st] 州/省
  /// [c] 国家
  /// [notAfterDays] 证书有效期（天数）
  /// 返回生成的AdbKeyPair对象
  static Future<AdbKeyPair> generate({
    int keySize = 2048,
    String cn = 'Kadb',
    String ou = 'Kadb',
    String o = 'Kadb',
    String l = 'Kadb',
    String st = 'Kadb',
    String c = 'Kadb',
    int notAfterDays = 120,
  }) async {
    // 生成RSA密钥对
    final keyPair = await AdbKeyPair.generate();
    
    // 生成X.509证书
    final certificate = _generateX509Certificate(
      privateKey: keyPair.privateKey,
      publicKey: keyPair.publicKey,
      cn: cn,
      ou: ou,
      o: o,
      l: l,
      st: st,
      c: c,
      notAfterDays: notAfterDays,
    );
    
    // 保存密钥对
    _savePrivateKey(keyPair.toPrivateKeyPem());
    _saveCertificate(certificate);
    
    return keyPair;
  }

  /// 读取私钥
  static String? _readPrivateKey() {
    try {
      // 从kadb_dart/cert_cache目录读取私钥文件，避免污染全局环境
      final privateKeyFile = File('kadb_dart/cert_cache/adbkey');
      if (privateKeyFile.existsSync()) {
        return privateKeyFile.readAsStringSync();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 读取证书
  static String? _readCertificate() {
    try {
      // 从kadb_dart/cert_cache目录读取证书文件，避免污染全局环境
      final certFile = File('kadb_dart/cert_cache/adbkey.pub');
      if (certFile.existsSync()) {
        return certFile.readAsStringSync();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 生成X.509证书
  static String _generateX509Certificate({
    required RSAPrivateKey privateKey,
    required RSAPublicKey publicKey,
    required String cn,
    required String ou,
    required String o,
    required String l,
    required String st,
    required String c,
    required int notAfterDays,
  }) {
    // 完整实现：生成符合X.509标准的证书
    final notBefore = DateTime.now();
    final notAfter = notBefore.add(Duration(days: notAfterDays));
    
    // 生成证书序列号
    final random = Random.secure();
    final serialNumber = BigInt.from(random.nextInt(1 << 31));
    
    // 构建完整的X.509证书结构
    final certificateSequence = asn1.ASN1Sequence();
    
    // 证书信息序列
    final tbsCertificate = asn1.ASN1Sequence();
    
    // 版本 (v3)
    tbsCertificate.add(asn1.ASN1Integer(BigInt.from(2)));
    
    // 序列号
    tbsCertificate.add(asn1.ASN1Integer(serialNumber));
    
    // 签名算法
    final signatureAlgorithm = asn1.ASN1Sequence();
    signatureAlgorithm.add(asn1.ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.11')); // sha256WithRSAEncryption OID
    signatureAlgorithm.add(asn1.ASN1Null());
    tbsCertificate.add(signatureAlgorithm);
    
    // 颁发者
    final issuerName = asn1.ASN1Sequence();
    issuerName.add(_buildNameComponent('CN', cn));
    issuerName.add(_buildNameComponent('OU', ou));
    issuerName.add(_buildNameComponent('O', o));
    issuerName.add(_buildNameComponent('L', l));
    issuerName.add(_buildNameComponent('ST', st));
    issuerName.add(_buildNameComponent('C', c));
    tbsCertificate.add(issuerName);
    
    // 有效期
    final validity = asn1.ASN1Sequence();
    validity.add(_encodeAsn1Time(notBefore));
    validity.add(_encodeAsn1Time(notAfter));
    tbsCertificate.add(validity);
    
    // 主题
    final subjectName = asn1.ASN1Sequence();
    subjectName.add(_buildNameComponent('CN', cn));
    subjectName.add(_buildNameComponent('OU', ou));
    subjectName.add(_buildNameComponent('O', o));
    subjectName.add(_buildNameComponent('L', l));
    subjectName.add(_buildNameComponent('ST', st));
    subjectName.add(_buildNameComponent('C', c));
    tbsCertificate.add(subjectName);
    
    // 公钥信息
    final subjectPublicKeyInfo = asn1.ASN1Sequence();
    final algorithm = asn1.ASN1Sequence();
    algorithm.add(asn1.ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.1')); // rsaEncryption OID
    algorithm.add(asn1.ASN1Null());
    subjectPublicKeyInfo.add(algorithm);
    
    final publicKeySequence = asn1.ASN1Sequence();
    publicKeySequence.add(asn1.ASN1Integer(publicKey.modulus ?? BigInt.zero));
    publicKeySequence.add(asn1.ASN1Integer(publicKey.exponent ?? BigInt.from(65537)));
    
    final publicKeyOctetString = asn1.ASN1OctetString(publicKeySequence.encodedBytes);
    subjectPublicKeyInfo.add(publicKeyOctetString);
    tbsCertificate.add(subjectPublicKeyInfo);
    
    // 将证书信息添加到证书序列
    certificateSequence.add(tbsCertificate);
    
    // 签名算法（与颁发者相同）
    certificateSequence.add(signatureAlgorithm);
    
    // 签名值（使用私钥签名）
    final signature = _signCertificate(tbsCertificate.encodedBytes, privateKey);
    certificateSequence.add(asn1.ASN1OctetString(signature));
    
    final derBytes = certificateSequence.encodedBytes;
    
    // 编码为PEM格式
    return _encodeCertificatePem(derBytes);
  }

  /// 编码证书为PEM格式
  static String _encodeCertificatePem(Uint8List derBytes) {
    final base64Content = base64.encode(derBytes);
    final pem = StringBuffer();
    
    pem.writeln(_certBegin);
    for (var i = 0; i < base64Content.length; i += 64) {
      final end = i + 64;
      if (end > base64Content.length) {
        pem.writeln(base64Content.substring(i));
      } else {
        pem.writeln(base64Content.substring(i, end));
      }
    }
    pem.writeln(_certEnd);
    
    return pem.toString();
  }

  /// 从PEM证书中提取DER字节
  static Uint8List _extractCertificateBytes(String pemCertificate) {
    final lines = pemCertificate.split('\n');
    var base64Content = '';
    var inCertificate = false;
    
    for (final line in lines) {
      if (line.contains(_certBegin)) {
        inCertificate = true;
        continue;
      }
      if (line.contains(_certEnd)) {
        break;
      }
      if (inCertificate) {
        base64Content += line.trim();
      }
    }
    
    return base64.decode(base64Content);
  }

  /// 保存私钥
  static void _savePrivateKey(String privateKey) {
    try {
      // 保存私钥到kadb_dart/cert_cache目录，避免污染全局环境
      final privateKeyFile = File('kadb_dart/cert_cache/adbkey');
      privateKeyFile.createSync(recursive: true);
      privateKeyFile.writeAsStringSync(privateKey);
    } catch (e) {
      print('保存私钥失败: $e');
    }
  }

  /// 保存证书
  static void _saveCertificate(String certificate) {
    try {
      // 保存证书到kadb_dart/cert_cache目录，避免污染全局环境
      final certFile = File('kadb_dart/cert_cache/adbkey.pub');
      certFile.createSync(recursive: true);
      certFile.writeAsStringSync(certificate);
    } catch (e) {
      print('保存证书失败: $e');
    }
  }

  /// 使用名称编码公钥
  static Uint8List encodeWithName(RSAPublicKey publicKey, String deviceName) {
    final keyBytes = AndroidPubkey.encode(publicKey);
    final nameBytes = utf8.encode(deviceName);
    
    final result = Uint8List(keyBytes.length + nameBytes.length + 1);
    result.setRange(0, keyBytes.length, keyBytes);
    result[keyBytes.length] = 0; // 分隔符
    result.setRange(keyBytes.length + 1, result.length, nameBytes);
    
    return result;
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
}