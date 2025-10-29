/// ADB协议核心常量和工具函数
///
/// 基于ADB官方协议文档实现，包含：
/// - 消息命令常量定义
/// - 协议版本和最大数据长度
/// - 校验和计算
/// - 字节序处理（小端）
library;

import 'dart:typed_data';

/// ADB协议核心常量类
class AdbProtocol {
  /// ADB消息头长度（24字节）
  static const int adbHeaderLength = 24;

  /// ADB命令常量（小端字节序）
  static const int aSync = 0x434e5953; // 'SYNC'
  static const int aCnxn = 0x4e584e43; // 'CNXN' - 连接
  static const int aAuth = 0x48545541; // 'AUTH' - 认证
  static const int aOpen = 0x4e45504f; // 'OPEN' - 打开流
  static const int aOkay = 0x59414b4f; // 'OKAY' - 确认
  static const int aClse = 0x45534c43; // 'CLSE' - 关闭流
  static const int aWrte = 0x45545257; // 'WRTE' - 写入数据
  static const int aStls = 0x534c5453; // 'STLS' - TLS加密

  /// STLS协议版本
  static const int aStlsVersion = 0x01000000;

  /// 认证类型
  static const int authTypeToken = 1; // Token挑战
  static const int authTypeSignature = 2; // 签名响应
  static const int authTypeRsaPublic = 3; // RSA公钥

  /// 连接协议版本
  static const int connectVersion = 0x01000000;

  /// 最大数据载荷大小（1MB）
  static const int connectMaxData = 1024 * 1024;

  /// 连接载荷（"host::" + null终止符）
  static final List<int> connectPayload = 'host::\x00'.codeUnits;

  /// 计算数据校验和（简单字节求和）
  ///
  /// ADB使用简单的字节求和作为校验和，而不是CRC32
  /// 这是为了性能考虑，因为ADB主要用于本地网络
  static int calculateChecksum(Uint8List data, [int offset = 0, int? length]) {
    final end = offset + (length ?? data.length - offset);
    int checksum = 0;

    for (int i = offset; i < end; i++) {
      checksum += data[i] & 0xFF;
    }

    return checksum;
  }

  /// 生成STLS消息
  static Uint8List generateStls() {
    final buffer = ByteData(adbHeaderLength);
    int offset = 0;

    // command
    offset = _writeInt32(buffer, offset, aStls);
    // arg0: version
    offset = _writeInt32(buffer, offset, aStlsVersion);
    // arg1: 0
    offset = _writeInt32(buffer, offset, 0);
    // data_length: 0
    offset = _writeInt32(buffer, offset, 0);
    // data_crc32: 0
    offset = _writeInt32(buffer, offset, 0);
    // magic: command ^ 0xffffffff
    offset = _writeInt32(buffer, offset, aStls ^ 0xffffffff);

    return buffer.buffer.asUint8List();
  }

  /// 将整数写入缓冲区（小端格式）
  static int _writeInt32(ByteData buffer, int offset, int value) {
    buffer.setUint32(offset, value, Endian.little);
    return offset + 4;
  }

  /// 从缓冲区读取整数（小端格式）
  static int _readInt32(ByteData buffer, int offset) {
    return buffer.getUint32(offset, Endian.little);
  }

  /// 获取命令的字符串表示（用于调试）
  static String getCommandString(int command) {
    switch (command) {
      case aAuth:
        return 'AUTH';
      case aCnxn:
        return 'CNXN';
      case aOpen:
        return 'OPEN';
      case aOkay:
        return 'OKAY';
      case aClse:
        return 'CLSE';
      case aWrte:
        return 'WRTE';
      case aStls:
        return 'STLS';
      default:
        return 'UNKNOWN(${command.toRadixString(16).toUpperCase()})';
    }
  }
}
