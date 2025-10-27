import 'dart:math';
import 'dart:typed_data';

/// RSA工具类，提供密钥生成、签名和验证功能
class RsaUtils {
  static const int _keySize = 2048;
  static const int _publicExponent = 65537;

  /// RSA密钥对
  static Future<RsaKeyPair> generateKeyPair() async {
    // 使用Dart的RSA实现
    final keyPair = await _generateRsaKeyPair();
    return keyPair;
  }

  /// 使用私钥签名数据
  static Future<Uint8List> sign(
    Uint8List data,
    RsaPrivateKey privateKey,
  ) async {
    // 实现RSA签名
    return await _rsaSign(data, privateKey);
  }

  /// 使用公钥验证签名
  static Future<bool> verify(
    Uint8List data,
    Uint8List signature,
    RsaPublicKey publicKey,
  ) async {
    // 实现RSA签名验证
    return await _rsaVerify(data, signature, publicKey);
  }

  /// 将公钥转换为Android格式
  static Uint8List convertToAndroidFormat(RsaPublicKey publicKey) {
    // Android ADB公钥格式：
    // 4字节：魔数 ("ADB\x00")
    // 4字节：RSA模数长度 (小端序)
    // 4字节：RSA公钥指数长度 (小端序)
    // n字节：RSA模数
    // e字节：RSA公钥指数

    final modulus = publicKey.modulus;
    final exponent = publicKey.exponent;

    // 确保模数是256字节 (2048位)
    final paddedModulus = _padToLength(modulus, 256);

    final buffer = ByteData(12 + paddedModulus.length + exponent.length);

    // 写入魔数 "ADB\x00"
    buffer.setUint32(0, 0x00424441, Endian.little); // "ADB\x00" 的小端序

    // 写入模数长度 (256字节)
    buffer.setUint32(4, paddedModulus.length, Endian.little);

    // 写入指数长度
    buffer.setUint32(8, exponent.length, Endian.little);

    // 写入模数
    for (int i = 0; i < paddedModulus.length; i++) {
      buffer.setUint8(12 + i, paddedModulus[i]);
    }

    // 写入指数
    for (int i = 0; i < exponent.length; i++) {
      buffer.setUint8(12 + paddedModulus.length + i, exponent[i]);
    }

    return buffer.buffer.asUint8List();
  }

  /// 从Android格式解析公钥
  static RsaPublicKey parseFromAndroidFormat(Uint8List data) {
    if (data.length < 12) {
      throw ArgumentError('Invalid Android public key format');
    }

    final buffer = ByteData.sublistView(data);

    // 检查魔数
    final magic = buffer.getUint32(0, Endian.little);
    if (magic != 0x00424441) {
      // "ADB\x00"
      throw ArgumentError('Invalid magic number');
    }

    // 读取模数长度
    final modulusLength = buffer.getUint32(4, Endian.little);

    // 读取指数长度
    final exponentLength = buffer.getUint32(8, Endian.little);

    if (data.length < 12 + modulusLength + exponentLength) {
      throw ArgumentError('Invalid data length');
    }

    // 提取模数
    final modulus = data.sublist(12, 12 + modulusLength);

    // 提取指数
    final exponent = data.sublist(
      12 + modulusLength,
      12 + modulusLength + exponentLength,
    );

    return RsaPublicKey(modulus, exponent);
  }

  /// 辅助方法：将数据填充到指定长度
  static Uint8List _padToLength(Uint8List data, int targetLength) {
    if (data.length == targetLength) {
      return data;
    }

    if (data.length > targetLength) {
      throw ArgumentError('Data is larger than target length');
    }

    final result = Uint8List(targetLength);
    // 前面补零
    result.setAll(targetLength - data.length, data);
    return result;
  }

  /// 生成RSA密钥对（简化实现）
  static Future<RsaKeyPair> _generateRsaKeyPair() async {
    // 在实际应用中，这里应该使用专业的加密库
    // 这里提供一个基于数学运算的简化实现

    // 生成大素数 p 和 q
    final p = _generateLargePrime(_keySize ~/ 2);
    final q = _generateLargePrime(_keySize ~/ 2);

    // 计算 n = p * q
    final n = p * q;

    // 计算 φ(n) = (p-1) * (q-1)
    final phi = (p - BigInt.one) * (q - BigInt.one);

    // 选择公钥指数 e
    final e = BigInt.from(_publicExponent);

    // 计算私钥指数 d = e^(-1) mod φ(n)
    final d = e.modInverse(phi);

    // 转换为字节数组
    final modulus = _bigIntToBytes(n);
    final privateExponent = _bigIntToBytes(d);
    final publicExponent = _bigIntToBytes(e);

    return RsaKeyPair(
      publicKey: RsaPublicKey(modulus, publicExponent),
      privateKey: RsaPrivateKey(
        modulus,
        privateExponent,
        publicExponent,
        p,
        q,
        d,
      ),
    );
  }

  /// RSA签名实现
  static Future<Uint8List> _rsaSign(
    Uint8List data,
    RsaPrivateKey privateKey,
  ) async {
    // 简化实现：直接进行RSA加密
    final message = _bytesToBigInt(data);

    // 签名 = 消息^私钥指数 mod 模数
    final signature = message.modPow(
      _bytesToBigInt(privateKey.privateExponent),
      _bytesToBigInt(privateKey.modulus),
    );

    return _bigIntToBytes(signature);
  }

  /// RSA签名验证
  static Future<bool> _rsaVerify(
    Uint8List data,
    Uint8List signature,
    RsaPublicKey publicKey,
  ) async {
    try {
      final message = _bytesToBigInt(data);
      final sig = _bytesToBigInt(signature);

      // 解密签名 = 签名^公钥指数 mod 模数
      final decrypted = sig.modPow(
        _bytesToBigInt(publicKey.exponent),
        _bytesToBigInt(publicKey.modulus),
      );

      return decrypted == message;
    } catch (e) {
      return false;
    }
  }

  /// 生成大素数
  static BigInt _generateLargePrime(int bits) {
    final random = Random.secure();

    while (true) {
      // 生成随机大数
      BigInt candidate = BigInt.zero;
      for (int i = 0; i < bits; i += 32) {
        candidate = (candidate << 32) | BigInt.from(random.nextInt(1 << 32));
      }

      // 设置最高位和最低位
      candidate = candidate | (BigInt.one << (bits - 1)); // 确保位数
      candidate = candidate | BigInt.one; // 确保为奇数

      // 简单的素性测试
      if (_isProbablePrime(candidate, 25)) {
        return candidate;
      }
    }
  }

  /// 素性测试（Miller-Rabin算法的简化版）
  static bool _isProbablePrime(BigInt n, int iterations) {
    if (n < BigInt.two) return false;
    if (n == BigInt.two) return true;
    if (n.isEven) return false;

    // 找到 n-1 = 2^s * d
    BigInt d = n - BigInt.one;
    int s = 0;
    while (d.isEven) {
      d = d >> 1;
      s++;
    }

    final random = Random.secure();

    for (int i = 0; i < iterations; i++) {
      // 选择随机基数 a，其中 2 <= a <= n-2
      BigInt a;
      do {
        a =
            BigInt.from(random.nextInt(1 << 16)) << 16 |
            BigInt.from(random.nextInt(1 << 16));
      } while (a < BigInt.two || a >= n - BigInt.one);

      BigInt x = a.modPow(d, n);

      if (x == BigInt.one || x == n - BigInt.one) {
        continue;
      }

      bool composite = true;
      for (int j = 0; j < s - 1; j++) {
        x = x.modPow(BigInt.two, n);
        if (x == n - BigInt.one) {
          composite = false;
          break;
        }
        if (x == BigInt.one) {
          break;
        }
      }

      if (composite) {
        return false;
      }
    }

    return true;
  }

  /// BigInt转字节数组
  static Uint8List _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) {
      return Uint8List.fromList([0]);
    }

    final bytes = <int>[];
    BigInt temp = value;

    while (temp > BigInt.zero) {
      bytes.add((temp & BigInt.from(0xFF)).toInt());
      temp = temp >> 8;
    }

    return Uint8List.fromList(bytes.reversed.toList());
  }

  /// 字节数组转BigInt
  static BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;

    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }

    return result;
  }
}

/// RSA公钥
class RsaPublicKey {
  final Uint8List modulus;
  final Uint8List exponent;

  RsaPublicKey(this.modulus, this.exponent);
}

/// RSA私钥
class RsaPrivateKey {
  final Uint8List modulus;
  final Uint8List privateExponent;
  final Uint8List publicExponent;
  final BigInt p;
  final BigInt q;
  final BigInt d;

  RsaPrivateKey(
    this.modulus,
    this.privateExponent,
    this.publicExponent,
    this.p,
    this.q,
    this.d,
  );
}

/// RSA密钥对
class RsaKeyPair {
  final RsaPublicKey publicKey;
  final RsaPrivateKey privateKey;

  RsaKeyPair({required this.publicKey, required this.privateKey});
}
