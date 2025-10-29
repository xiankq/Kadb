/**
 * CRC32计算工具类
 * 用于ADB消息的数据校验
 */

/// CRC32计算实现
class Crc32 {
  static const int _polynomial = 0xEDB88320;
  static final List<int> _table = _generateTable();

  static List<int> _generateTable() {
    final table = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int crc = i;
      for (int j = 0; j < 8; j++) {
        if ((crc & 1) == 1) {
          crc = (crc >> 1) ^ _polynomial;
        } else {
          crc >>= 1;
        }
      }
      table[i] = crc & 0xFFFFFFFF;
    }
    return table;
  }

  /// 计算数据的CRC32校验和
  static int calculate(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      final index = (crc ^ byte) & 0xFF;
      crc = (crc >> 8) ^ _table[index];
    }
    return (~crc) & 0xFFFFFFFF;
  }

  /// 计算Uint8List的CRC32校验和
  static int calculateFromBytes(List<int> data) {
    return calculate(data);
  }
}