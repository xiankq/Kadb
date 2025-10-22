library;

/// 字节数组处理工具类
class ByteUtils {
  /// 从小端序字节数组中读取32位整数
  static int readIntLe(List<int> data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  /// 将32位整数写入小端序字节数组
  static void writeIntLe(int value, List<int> data, int offset) {
    data[offset] = value & 0xFF;
    data[offset + 1] = (value >> 8) & 0xFF;
    data[offset + 2] = (value >> 16) & 0xFF;
    data[offset + 3] = (value >> 24) & 0xFF;
  }

  /// 将大整数转换为16进制字符串
  static String toHex(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }
    return hex.toUpperCase();
  }
}
