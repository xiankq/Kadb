/// ADB协议常量定义
class AdbProtocol {
  static const int headerLength = 24;

  // 命令常量
  static const int cmdAuth = 0x48545541; // AUTH
  static const int cmdCnxn = 0x4e584e43; // CNXN
  static const int cmdOpen = 0x4e45504f; // OPEN
  static const int cmdOkay = 0x59414b4f; // OKAY
  static const int cmdClse = 0x45534c43; // CLSE
  static const int cmdWrte = 0x45545257; // WRTE
  static const int cmdStls = 0x534c5453; // STLS

  // 认证类型
  static const int authTypeToken = 1;
  static const int authTypeSignature = 2;
  static const int authTypeRsaPublic = 3;

  // 连接参数
  static const int connectVersion = 0x01000000;
  static const int connectMaxdata = 1024 * 1024;
  static const int stlsVersion = 0x01000000;


  static final List<int> connectPayload = 'host::\u0000'.codeUnits;

  /// 获取协议版本
  static int get version => connectVersion;

  /// 获取最大负载大小
  static int get maxPayload => connectMaxdata;

  /// 获取RSA公钥认证类型
  static int get authTypeRsapublickey => authTypeRsaPublic;

  /// 计算ADB负载数据的校验和
  static int getPayloadChecksum(List<int> data, int offset, int length) {
    int checksum = 0;
    for (int i = offset; i < offset + length; i++) {
      checksum += data[i] & 0xFF;
    }
    return checksum;
  }

  /// 生成ADB消息
  static List<int> generateMessage(int command, int arg0, int arg1, List<int>? data) {
    return generateMessageWithOffset(command, arg0, arg1, data, 0, data?.length ?? 0);
  }

  /// 生成ADB消息（带偏移量）
  static List<int> generateMessageWithOffset(
      int command, int arg0, int arg1, List<int>? data, int offset, int length) {
    final message = <int>[];

    // 写入命令和参数（小端序）
    _writeIntLe(message, command);
    _writeIntLe(message, arg0);
    _writeIntLe(message, arg1);

    if (data != null) {
      _writeIntLe(message, length);
      _writeIntLe(message, getPayloadChecksum(data, offset, length));
    } else {
      _writeIntLe(message, 0);
      _writeIntLe(message, 0);
    }

    // 写入魔数（命令的按位取反）
    _writeIntLe(message, command ^ 0xFFFFFFFF);

    // 写入负载数据
    if (data != null) {
      final payloadData = data.sublist(offset, offset + length);
      message.addAll(payloadData);
    }

    return message;
  }

  /// 以小端序写入32位整数到字节列表
  static void _writeIntLe(List<int> buffer, int value) {
    buffer.add(value & 0xFF);
    buffer.add((value >> 8) & 0xFF);
    buffer.add((value >> 16) & 0xFF);
    buffer.add((value >> 24) & 0xFF);
  }
}