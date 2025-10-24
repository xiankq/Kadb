import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/export.dart';

/// 加密工具类，统一处理加密相关操作
class CryptoUtils {
  /// 生成随机字节
  static Uint8List generateRandomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  /// 计算SHA256哈希
  static Uint8List sha256(Uint8List data) {
    final digest = SHA256Digest();
    return digest.process(data);
  }

  /// 计算HMAC-SHA256
  static Uint8List hmacSha256(Uint8List key, Uint8List data) {
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(key));
    return hmac.process(data);
  }

  /// 将大整数转换为字节数组
  static Uint8List bigIntToBytes(BigInt value) {
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

  /// 将字节数组转换为大整数
  static BigInt bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (var i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  /// 将大整数转换为指定长度的字节数组
  static Uint8List bigIntToBytesFixed(BigInt value, int length) {
    var hex = value.toRadixString(16);
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }

    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }

    // 填充到指定长度
    while (bytes.length < length) {
      bytes.insert(0, 0);
    }

    // 如果超过指定长度，截断左侧
    if (bytes.length > length) {
      return Uint8List.fromList(bytes.sublist(bytes.length - length));
    }

    return Uint8List.fromList(bytes);
  }
}
