library;

import 'dart:typed_data';
import 'package:pointycastle/asymmetric/api.dart';
import 'crypto_utils.dart';

/// Android公钥格式编码和解码类，基于Kotlin原项目完整实现Android RSA公钥格式
/// Android公钥工具类
class AndroidPubkey {
  /// RSA模数大小（字节）
  static const int androidPubkeyModulusSize = 2048 ~/ 8;

  /// 编码后的RSA密钥大小
  static const int androidPubkeyEncodedSize =
      3 * 4 + 2 * androidPubkeyModulusSize;

  /// RSA模数大小（字）
  static const int androidPubkeyModulusSizeWords =
      androidPubkeyModulusSize ~/ 4;

  /// Android公钥签名填充（与Kotlin版本完全一致，236字节，包含218个0xff）
  static final Uint8List signaturePadding = Uint8List.fromList([
    0x00, 0x01,
    ...List.filled(218, 0xff), // 218个0xff
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

  /// 将标准RSAPublicKey对象转换为特殊的ADB格式
  /// [publicKey] 要转换的RSAPublicKey对象
  /// [name] 不包含空终止符的名称
  /// 返回包含转换后的RSAPublicKey对象的字节数组
  static Uint8List encodeWithName(RSAPublicKey publicKey, String name) {
    final encodedKey = encode(publicKey);

    // 创建包含编码密钥和名称的缓冲区
    final buffer = BytesBuilder();
    buffer.add(encodedKey);
    buffer.add(_getUserInfo(name));

    return buffer.toBytes();
  }

  /// 获取用户信息
  static Uint8List _getUserInfo(String name) {
    final userInfo = ' $name\u0000';
    return Uint8List.fromList(userInfo.codeUnits);
  }

  /// 将给定的密钥编码为Android RSA公钥二进制格式
  /// 返回Android自定义二进制格式的公共RSA密钥
  static Uint8List encode(RSAPublicKey publicKey) {
    if (_bigIntToBytes(publicKey.modulus!).length < androidPubkeyModulusSize) {
      throw ArgumentError(
        '无效的密钥长度: ${_bigIntToBytes(publicKey.modulus!).length}',
      );
    }

    final keyStruct = ByteData(androidPubkeyEncodedSize);
    var offset = 0;

    // 存储模数大小
    keyStruct.setUint32(offset, androidPubkeyModulusSizeWords, Endian.little);
    offset += 4;

    // 计算并存储n0inv = -1 / N[0] mod 2^32
    final r32 = BigInt.from(2).pow(32); // r32 = 2^32
    var n0inv = publicKey.modulus! % r32; // n0inv = N[0] mod 2^32
    n0inv = n0inv.modInverse(r32); // n0inv = 1/n0inv mod 2^32
    n0inv = r32 - n0inv; // n0inv = 2^32 - n0inv
    keyStruct.setUint32(offset, n0inv.toInt(), Endian.little);
    offset += 4;

    // 存储模数
    final modulusBytes = _bigEndianToLittleEndianPadded(
      androidPubkeyModulusSize,
      publicKey.modulus!,
    );
    for (var i = 0; i < modulusBytes.length; i++) {
      keyStruct.setUint8(offset + i, modulusBytes[i]);
    }
    offset += androidPubkeyModulusSize;

    // 计算并存储rr = (2^(rsa_size)) ^ 2 mod N
    var rr = BigInt.from(
      2,
    ).pow(androidPubkeyModulusSize * 8); // rr = 2^(rsa_size)
    rr = rr.modPow(BigInt.from(2), publicKey.modulus!); // rr = rr^2 mod N
    final rrBytes = _bigEndianToLittleEndianPadded(
      androidPubkeyModulusSize,
      rr,
    );
    for (var i = 0; i < rrBytes.length; i++) {
      keyStruct.setUint8(offset + i, rrBytes[i]);
    }
    offset += androidPubkeyModulusSize;

    // 存储指数
    keyStruct.setUint32(offset, publicKey.exponent!.toInt(), Endian.little);

    return keyStruct.buffer.asUint8List();
  }

  /// 将大端序转换为小端序并填充
  static Uint8List _bigEndianToLittleEndianPadded(int len, BigInt input) {
    final out = Uint8List(len);
    final bytes = _swapEndianness(_bigIntToBytes(input)); // 转换大端序 -> 小端序
    var numBytes = bytes.length;

    if (len < numBytes) {
      if (!_fitsInBytes(bytes, numBytes, len)) {
        throw ArgumentError('数据不适合指定长度');
      }
      numBytes = len;
    }

    for (var i = 0; i < numBytes; i++) {
      out[i] = bytes[i];
    }
    return out;
  }

  /// 检查字节是否适合指定长度
  static bool _fitsInBytes(Uint8List bytes, int numBytes, int len) {
    var mask = 0;
    for (var i = len; i < numBytes; i++) {
      mask = mask | bytes[i];
    }
    return mask == 0;
  }

  /// 交换字节序
  static Uint8List _swapEndianness(Uint8List bytes) {
    final len = bytes.length;
    final out = Uint8List(len);
    for (var i = 0; i < len; i++) {
      out[i] = bytes[len - i - 1];
    }
    return out;
  }

  /// 解析Android公钥格式
  static RSAPublicKey parseAndroidPubkey(Uint8List pubkeyBytes) {
    if (pubkeyBytes.length < androidPubkeyEncodedSize) {
      throw ArgumentError('公钥数据过短');
    }

    final buffer = ByteData.view(pubkeyBytes.buffer);
    var offset = 0;

    // 读取模数大小
    final modulusSizeWords = buffer.getUint32(offset, Endian.little);
    offset += 4;

    if (modulusSizeWords != androidPubkeyModulusSizeWords) {
      throw ArgumentError('不支持的模数大小: $modulusSizeWords');
    }

    // 读取n0inv（虽然计算但未使用）
    offset += 4;

    // 读取模数
    final modulusBytes = pubkeyBytes.sublist(
      offset,
      offset + androidPubkeyModulusSize,
    );
    final modulus = _littleEndianToBigInt(modulusBytes);
    offset += androidPubkeyModulusSize;

    // 读取rr
    final rrBytes = pubkeyBytes.sublist(
      offset,
      offset + androidPubkeyModulusSize,
    );
    final rr = _littleEndianToBigInt(rrBytes);
    offset += androidPubkeyModulusSize;

    // 读取指数
    final exponent = buffer.getUint32(offset, Endian.little);

    // 验证rr计算
    final expectedRr = BigInt.from(2).pow(androidPubkeyModulusSize * 8);
    final expectedRrSquared = expectedRr.modPow(BigInt.from(2), modulus);
    if (rr != expectedRrSquared) {
      throw ArgumentError('rr验证失败');
    }

    return RSAPublicKey(modulus, BigInt.from(exponent));
  }

  /// 将小端序字节数组转换为大整数
  static BigInt _littleEndianToBigInt(Uint8List bytes) {
    final swapped = _swapEndianness(bytes);
    var result = BigInt.zero;
    for (var i = 0; i < swapped.length; i++) {
      result = (result << 8) | BigInt.from(swapped[i]);
    }
    return result;
  }

  /// 将大整数转换为字节数组
  static Uint8List _bigIntToBytes(BigInt value) {
    return CryptoUtils.bigIntToBytes(value);
  }
}
