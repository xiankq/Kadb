/// Android公钥格式转换
/// 将RSA公钥转换为Android ADB使用的特殊格式
library android_pubkey;

import 'dart:typed_data';
import 'package:pointycastle/pointycastle.dart' as pc;

/// Android公钥格式转换工具
class AndroidPubkey {
  static const int keyLengthBits = 2048;
  static const int keyLengthBytes = keyLengthBits ~/ 8;
  static const int keyLengthWords = keyLengthBytes ~/ 4;

  /// 将RSA公钥转换为ADB格式
  static Uint8List convertRsaPublicKey(pc.RSAPublicKey publicKey) {
    // 基于libmincrypt的RSA公钥格式
    // typedef struct RSAPublicKey {
    //   int len;           // Length of n[] in number of uint32_t
    //   uint32_t n0inv;    // -1 / n[0] mod 2^32
    //   uint32_t n[keyLengthWords]; // modulus as little endian array
    //   uint32_t rr[keyLengthWords]; // R^2 as little endian array
    //   int exponent;      // 3 or 65537
    // } RSAPublicKey;

    final n = publicKey.modulus!;
    final e = publicKey.exponent!;

    // 计算n0inv = -1 / n[0] mod 2^32
    final n0 = _extractWord(n, 0);
    final n0inv = _modularInverse(n0, 0x100000000);

    // 计算R = 2^(keyLengthWords * 32)
    final r = BigInt.from(2).pow(keyLengthWords * 32);

    // 计算R^2 mod n
    final rSquared = (r * r) % n;

    // 提取模数和R^2的各个字
    final nWords = _extractWords(n);
    final rrWords = _extractWords(rSquared);

    // 构建输出缓冲区 - 精确大小
    final buffer = ByteData(keyLengthWords * 4 * 2 + 8); // nWords + rrWords + len + n0inv + exponent
    var offset = 0;

    // len
    buffer.setUint32(offset, keyLengthWords, Endian.little);
    offset += 4;

    // n0inv
    buffer.setUint32(offset, (-n0inv) & 0xFFFFFFFF, Endian.little);
    offset += 4;

    // n[]
    for (final word in nWords) {
      buffer.setUint32(offset, word & 0xFFFFFFFF, Endian.little);
      offset += 4;
    }

    // rr[]
    for (final word in rrWords) {
      buffer.setUint32(offset, word & 0xFFFFFFFF, Endian.little);
      offset += 4;
    }

    // exponent - 使用setUint32而不是setInt32避免符号问题
    buffer.setUint32(offset, e.toInt(), Endian.little);
    offset += 4;

    // 只返回使用的字节 - 确保精确大小
    return buffer.buffer.asUint8List(0, offset);
  }

  /// 从大整数中提取指定位置的32位字
  static int _extractWord(BigInt value, int index) {
    final shift = index * 32;
    final mask = BigInt.from(0xFFFFFFFF);
    return ((value >> shift) & mask).toInt();
  }

  /// 从大整数中提取所有32位字（小端序）
  static List<int> _extractWords(BigInt value) {
    final words = List<int>.filled(keyLengthWords, 0);
    for (int i = 0; i < keyLengthWords; i++) {
      words[i] = _extractWord(value, i);
    }
    return words;
  }

  /// 计算模逆元
  static int _modularInverse(int a, int m) {
    // 扩展欧几里得算法
    int m0 = m, x0 = 0, x1 = 1;

    if (m == 1) return 0;

    while (a > 1) {
      // q是商
      int q = a ~/ m;
      int t = m;

      // m是余数，现在处理为除数
      m = a % m;
      a = t;
      t = x0;
      x0 = x1 - q * x0;
      x1 = t;
    }

    // 确保x1为正数
    if (x1 < 0) x1 += m0;

    return x1;
  }

  /// 验证公钥格式
  static bool verifyPublicKeyFormat(Uint8List keyData) {
    final expectedLength = keyLengthWords * 4 * 2 + 8; // 精确计算：nWords + rrWords + len + n0inv + exponent
    if (keyData.length != expectedLength) {
      print('公钥长度错误: 期望$expectedLength字节，实际${keyData.length}字节');
      return false;
    }

    try {
      final data = ByteData.sublistView(keyData);
      final len = data.getUint32(0, Endian.little);
      return len == keyLengthWords;
    } catch (e) {
      print('公钥格式验证错误: $e');
      return false;
    }
  }
}
