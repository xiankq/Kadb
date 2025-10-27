/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:typed_data';
import 'package:pointycastle/pointycastle.dart';
import 'rsa_utils.dart';

/// Android公钥格式处理
class AndroidPubkey {
  static const int androidPubkeyModulusSize = 2048 ~/ 8; // 256字节
  static const int androidPubkeyEncodedSize =
      3 * 4 + 2 * androidPubkeyModulusSize; // 524字节
  static const int androidPubkeyModulusSizeWords =
      androidPubkeyModulusSize ~/ 4; // 64个字

  /// 将RSA公钥转换为Android ADB格式
  static Uint8List convertToAndroidFormat(RsaPublicKey publicKey) {
    return RsaUtils.convertToAndroidFormat(publicKey);
  }

  /// 从Android ADB格式解析RSA公钥
  static RsaPublicKey parseFromAndroidFormat(Uint8List data) {
    return RsaUtils.parseFromAndroidFormat(data);
  }

  /// ADB签名填充
  static final Uint8List signaturePadding = Uint8List.fromList([
    0x00,
    0x01,
    for (int i = 0; i < 218; i++) 0xff,
    0x00,
    0x30,
    0x21,
    0x30,
    0x09,
    0x06,
    0x05,
    0x2b,
    0x0e,
    0x03,
    0x02,
    0x1a,
    0x05,
    0x00,
    0x04,
    0x14,
  ]);

  /// 编码RSA公钥为Android格式
  static Uint8List encodePublicKey(RSAPublicKey publicKey) {
    final buffer = ByteData(androidPubkeyEncodedSize);
    buffer.setUint32(0, androidPubkeyModulusSizeWords, Endian.little);

    // 计算n0inv (-1 / n[0] mod 2^32)
    final n0inv = _calculateN0Inv(publicKey.modulus!);
    buffer.setUint32(4, n0inv, Endian.little);

    // 写入模数（小端序）
    final modulusWords = _bigIntToWords(
      publicKey.modulus!,
      androidPubkeyModulusSizeWords,
    );
    for (int i = 0; i < androidPubkeyModulusSizeWords; i++) {
      buffer.setUint32(8 + i * 4, modulusWords[i], Endian.little);
    }

    // 计算R^2 mod n
    final rrWords = _calculateRR(
      publicKey.modulus!,
      androidPubkeyModulusSizeWords,
    );
    for (int i = 0; i < androidPubkeyModulusSizeWords; i++) {
      buffer.setUint32(
        8 + androidPubkeyModulusSizeWords * 4 + i * 4,
        rrWords[i],
        Endian.little,
      );
    }

    // 写入公钥指数
    buffer.setUint32(
      8 + 2 * androidPubkeyModulusSizeWords * 4,
      publicKey.exponent!.toInt(),
      Endian.little,
    );

    return buffer.buffer.asUint8List();
  }

  /// 计算n0inv (-1 / n[0] mod 2^32)
  static int _calculateN0Inv(BigInt n) {
    // 获取n的最低32位
    final n0 = n & BigInt.from(0xFFFFFFFF);

    // 计算 -1 / n0 mod 2^32
    try {
      final n0Inv = n0.modInverse(BigInt.from(0x100000000));
      return (-n0Inv).toInt() & 0xFFFFFFFF;
    } catch (e) {
      // 如果无法计算逆元，返回0
      return 0;
    }
  }

  /// 计算R^2 mod n，其中R = 2^(modulusSize * 32)
  static List<int> _calculateRR(BigInt n, int wordSize) {
    final r = BigInt.from(2).pow(wordSize * 32);
    final rr = r * r % n;

    final result = List<int>.filled(wordSize, 0);
    var temp = rr;

    for (int i = 0; i < wordSize; i++) {
      result[i] = (temp & BigInt.from(0xFFFFFFFF)).toInt();
      temp = temp >> 32;
    }

    return result;
  }

  /// 大整数转32位字数组（小端序）
  static List<int> _bigIntToWords(BigInt value, int wordCount) {
    final words = List<int>.filled(wordCount, 0);
    var temp = value;

    for (int i = 0; i < wordCount; i++) {
      words[i] = (temp & BigInt.from(0xFFFFFFFF)).toInt();
      temp = temp >> 32;
    }

    return words;
  }

  /// 解码Android格式的公钥
  static RSAPublicKey decodePublicKey(Uint8List encodedKey) {
    if (encodedKey.length != androidPubkeyEncodedSize) {
      throw ArgumentError('Invalid encoded key size: ${encodedKey.length}');
    }

    final buffer = ByteData.sublistView(encodedKey);

    // 读取模数字数
    final len = buffer.getUint32(0, Endian.little);
    if (len != androidPubkeyModulusSizeWords) {
      throw ArgumentError('Invalid modulus size: $len');
    }

    // 读取n0inv（暂时忽略）
    final n0inv = buffer.getUint32(4, Endian.little);

    // 读取模数
    final modulusWords = List<BigInt>.filled(
      androidPubkeyModulusSizeWords,
      BigInt.zero,
    );
    for (int i = 0; i < androidPubkeyModulusSizeWords; i++) {
      modulusWords[i] = BigInt.from(buffer.getUint32(8 + i * 4, Endian.little));
    }

    final modulus = _wordsToBigInt(modulusWords);

    // 读取rr（暂时忽略）

    // 读取公钥指数
    final exponent = BigInt.from(
      buffer.getUint32(
        8 + 2 * androidPubkeyModulusSizeWords * 4,
        Endian.little,
      ),
    );

    return RSAPublicKey(modulus, exponent);
  }

  /// 32位字数组转大整数（小端序）
  static BigInt _wordsToBigInt(List<BigInt> words) {
    BigInt result = BigInt.zero;

    for (int i = words.length - 1; i >= 0; i--) {
      result = (result << 32) | words[i];
    }

    return result;
  }
}
