/// ADB协议常量定义
/// 包含ADB协议的所有命令、常量定义
class AdbProtocol {
  static const int adbHeaderLength = 24;

  static const int aStls = 0x534c5453;
  static const int aStlsVersion = 0x01000000;

  static const int authTypeToken = 1;
  static const int authTypeSignature = 2;
  static const int authTypeRsaPublic = 3;

  static const int cmdAuth = 0x48545541;
  static const int cmdCnxn = 0x4e584e43;
  static const int cmdOpen = 0x4e45504f;
  static const int cmdOkay = 0x59414b4f;
  static const int cmdClse = 0x45534c43;
  static const int cmdWrte = 0x45545257;

  static const int cmdStls = 0x534c5453;

  static const int connectVersion = 0x01000000;
  static const int connectMaxdata = 1024 * 1024;

  // 为测试文件提供兼容性常量
  static const int ADB_HEADER_LENGTH = adbHeaderLength;
  static const int CMD_CNXN = cmdCnxn;
  static const int CMD_AUTH = cmdAuth;
  static const int CMD_CLSE = cmdClse;
  static const int CMD_OPEN = cmdOpen;
  static const int CMD_OKAY = cmdOkay;
  static const int CMD_WRTE = cmdWrte;
  static const int CMD_STLS = cmdStls;
  static const int AUTH_TYPE_RSA_PUBLIC = authTypeRsaPublic;
  static const int CONNECT_VERSION = connectVersion;
  static const int CONNECT_MAXDATA = connectMaxdata;

  static final List<int> connectPayload = 'host::\u0000'.codeUnits;

  /// 获取协议版本
  static int get version => connectVersion;

  /// 获取最大负载大小
  static int get maxPayload => connectMaxdata;

  /// 获取系统标识字符串
  static String get systemIdentityString => 'host::';

  /// 获取RSA公钥认证类型
  static int get authTypeRsapublickey => authTypeRsaPublic;

  /// 计算ADB负载数据的校验和
  /// [data] 数据字节数组
  /// [offset] 数据起始偏移量
  /// [length] 要读取的字节数
  /// 返回数据的校验和
  static int getPayloadChecksum(List<int> data, int offset, int length) {
    int checksum = 0;
    for (int i = offset; i < offset + length; i++) {
      checksum += data[i] & 0xFF;
    }
    return checksum;
  }

  /// 生成ADB消息
  /// [command] 命令标识符常量
  /// [arg0] 第一个参数
  /// [arg1] 第二个参数
  /// [data] 数据字节数组
  /// 返回包含消息的字节数组
  static List<int> generateMessage(int command, int arg0, int arg1, List<int>? data) {
    return generateMessageWithOffset(command, arg0, arg1, data, 0, data?.length ?? 0);
  }

  /// 生成ADB消息（带偏移量）
  /// [command] 命令标识符常量
  /// [arg0] 第一个参数
  /// [arg1] 第二个参数
  /// [data] 数据字节数组
  /// [offset] 数据起始偏移量
  /// [length] 要读取的字节数
  /// 返回包含消息的字节数组
  static List<int> generateMessageWithOffset(
      int command, int arg0, int arg1, List<int>? data, int offset, int length) {
    // ADB协议结构定义：https://github.com/aosp-mirror/platform_system_core/blob/6072de17cd812daf238092695f26a552d3122f8c/adb/protocol.txt
    // struct message {
    //     unsigned command;       // 命令标识符常量
    //     unsigned arg0;          // 第一个参数
    //     unsigned arg1;          // 第二个参数
    //     unsigned data_length;   // 负载长度（允许为0）
    //     unsigned data_check;    // 数据负载的校验和
    //     unsigned magic;         // 命令 ^ 0xffffffff
    // };

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

  /// 生成STLS消息（带默认参数）
  /// STLS(version, 0, "")
  /// 返回包含消息的字节数组
  static List<int> generateStls() {
    return generateMessage(aStls, aStlsVersion, 0, null);
  }

  /// 以小端序写入32位整数到字节列表
  static void _writeIntLe(List<int> buffer, int value) {
    buffer.add(value & 0xFF);
    buffer.add((value >> 8) & 0xFF);
    buffer.add((value >> 16) & 0xFF);
    buffer.add((value >> 24) & 0xFF);
  }

  /// 从小端序字节数组中读取32位整数
  static int _readIntLe(List<int> data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }
}