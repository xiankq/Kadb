import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

/// 专业的Base64编码解码工具类
/// 提供与标准Base64完全兼容的实现
class Base64Utils {
  static const String _base64Alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  static const String _base64UrlAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  static const int _paddingChar = 61; // '='

  /// 标准Base64编码
  static String encode(List<int> data) {
    return _encodeBase64(data, _base64Alphabet, true);
  }

  /// URL安全的Base64编码
  static String encodeUrl(List<int> data) {
    return _encodeBase64(data, _base64UrlAlphabet, false);
  }

  /// 标准Base64解码
  static Uint8List decode(String encoded) {
    return _decodeBase64(encoded, _base64Alphabet);
  }

  /// URL安全的Base64解码
  static Uint8List decodeUrl(String encoded) {
    return _decodeBase64(encoded, _base64UrlAlphabet);
  }

  /// 内部Base64编码实现
  static String _encodeBase64(List<int> data, String alphabet, bool padding) {
    if (data.isEmpty) return '';

    final result = StringBuffer();
    int buffer = 0;
    int bitsInBuffer = 0;

    for (final byte in data) {
      buffer = (buffer << 8) | byte;
      bitsInBuffer += 8;

      while (bitsInBuffer >= 6) {
        bitsInBuffer -= 6;
        final index = (buffer >> bitsInBuffer) & 0x3F;
        result.write(alphabet[index]);
      }
    }

    // 处理剩余位
    if (bitsInBuffer > 0) {
      final index = (buffer << (6 - bitsInBuffer)) & 0x3F;
      result.write(alphabet[index]);
    }

    // 添加填充
    if (padding) {
      while (result.length % 4 != 0) {
        result.write('=');
      }
    }

    return result.toString();
  }

  /// 内部Base64解码实现
  static Uint8List _decodeBase64(String encoded, String alphabet) {
    if (encoded.isEmpty) return Uint8List(0);

    // 移除填充和空白字符
    final cleanEncoded = encoded.replaceAll(RegExp(r'[\s=]'), '');

    if (cleanEncoded.isEmpty) return Uint8List(0);

    final result = <int>[];
    int buffer = 0;
    int bitsInBuffer = 0;

    for (final char in cleanEncoded.codeUnits) {
      final index = alphabet.indexOf(String.fromCharCode(char));
      if (index == -1) {
        throw FormatException(
          'Invalid Base64 character: ${String.fromCharCode(char)}',
        );
      }

      buffer = (buffer << 6) | index;
      bitsInBuffer += 6;

      if (bitsInBuffer >= 8) {
        bitsInBuffer -= 8;
        result.add((buffer >> bitsInBuffer) & 0xFF);
      }
    }

    return Uint8List.fromList(result);
  }

  /// 检查字符串是否为有效的Base64
  static bool isValidBase64(String encoded) {
    if (encoded.isEmpty) return true;

    // 检查字符集
    final validPattern = RegExp(r'^[A-Za-z0-9+/]*={0,2}$');
    if (!validPattern.hasMatch(encoded)) return false;

    // 检查填充
    final length = encoded.replaceAll(RegExp(r'[\s]'), '').length;
    return length % 4 == 0;
  }

  /// 获取Base64编码后的长度
  static int getEncodedLength(int dataLength) {
    return ((dataLength + 2) ~/ 3) * 4;
  }

  /// 获取解码后的长度（近似）
  static int getDecodedLength(String encoded) {
    final cleanLength = encoded.replaceAll(RegExp(r'[\s]'), '').length;
    return (cleanLength * 3) ~/ 4;
  }

  /// 编码整数为Base64
  static String encodeInt(int value, {int bytes = 4}) {
    final data = Uint8List(bytes);
    for (int i = 0; i < bytes; i++) {
      data[bytes - 1 - i] = (value >> (i * 8)) & 0xFF;
    }
    return encode(data);
  }

  /// 解码Base64为整数
  static int decodeInt(String encoded) {
    final data = decode(encoded);
    if (data.isEmpty) return 0;

    int result = 0;
    for (int i = 0; i < data.length; i++) {
      result = (result << 8) | data[i];
    }
    return result;
  }

  /// 编码字符串为Base64
  static String encodeString(String text, {Encoding encoding = utf8}) {
    return encode(encoding.encode(text));
  }

  /// 解码Base64为字符串
  static String decodeString(String encoded, {Encoding encoding = utf8}) {
    return encoding.decode(decode(encoded));
  }

  /// 生成Base64编码的随机数据
  static String generateRandom(int length) {
    final random = Random.secure();
    final data = Uint8List(length);

    for (int i = 0; i < length; i++) {
      data[i] = random.nextInt(256);
    }

    return encode(data);
  }

  /// 比较两个Base64编码的字符串（常量时间比较）
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;

    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }

    return result == 0;
  }
}
