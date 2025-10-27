/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

/// ADB协议常量定义
class AdbProtocol {
  /// ADB消息头长度
  static const int adbHeaderLength = 24;

  /// TLS相关常量
  static const int aStls = 0x534c5453;
  static const int aStlsVersion = 0x01000000;

  /// 认证类型
  static const int authTypeToken = 1;
  static const int authTypeSignature = 2;
  static const int authTypeRsaPublic = 3;

  /// ADB命令常量
  static const int cmdAuth = 0x48545541;
  static const int cmdCnxc = 0x4e584e43;
  static const int cmdOpen = 0x4e45504f;
  static const int cmdOkay = 0x59414b4f;
  static const int cmdClse = 0x45534c43;
  static const int cmdWrte = 0x45545257;
  static const int cmdStls = 0x534c5453;

  /// 连接版本和最大数据长度
  static const int connectVersion = 0x01000000;
  static const int connectMaxData = 1024 * 1024;

  /// 连接载荷
  static const String connectPayload = "host::\u0000";

  /// 计算数据校验和
  static int getPayloadChecksum(List<int> data, int offset, int length) {
    int checksum = 0;
    for (int i = offset; i < offset + length; i++) {
      checksum += data[i] & 0xFF;
    }
    return checksum;
  }

  /// 生成ADB消息
  static List<int> generateMessage(
    int command,
    int arg0,
    int arg1,
    List<int>? data,
  ) {
    return generateMessageWithOffset(
      command,
      arg0,
      arg1,
      data,
      0,
      data?.length ?? 0,
    );
  }

  /// 生成ADB消息（带偏移和长度）
  static List<int> generateMessageWithOffset(
    int command,
    int arg0,
    int arg1,
    List<int>? data,
    int offset,
    int length,
  ) {
    // ADB协议消息格式（小端序）：
    // struct message {
    //     unsigned command;       // 命令标识符常量
    //     unsigned arg0;          // 第一个参数
    //     unsigned arg1;          // 第二个参数
    //     unsigned data_length;   // 载荷长度（可以为0）
    //     unsigned data_check;    // 数据载荷校验和
    //     unsigned magic;         // command ^ 0xffffffff
    // };

    final message = _BytesBuilder();

    // 写入头部（小端序）
    message.addByte(command & 0xFF);
    message.addByte((command >> 8) & 0xFF);
    message.addByte((command >> 16) & 0xFF);
    message.addByte((command >> 24) & 0xFF);

    message.addByte(arg0 & 0xFF);
    message.addByte((arg0 >> 8) & 0xFF);
    message.addByte((arg0 >> 16) & 0xFF);
    message.addByte((arg0 >> 24) & 0xFF);

    message.addByte(arg1 & 0xFF);
    message.addByte((arg1 >> 8) & 0xFF);
    message.addByte((arg1 >> 16) & 0xFF);
    message.addByte((arg1 >> 24) & 0xFF);

    // 数据长度和校验和
    final dataLength = data != null ? length : 0;
    message.addByte(dataLength & 0xFF);
    message.addByte((dataLength >> 8) & 0xFF);
    message.addByte((dataLength >> 16) & 0xFF);
    message.addByte((dataLength >> 24) & 0xFF);

    final checksum = data != null
        ? getPayloadChecksum(data, offset, length)
        : 0;
    message.addByte(checksum & 0xFF);
    message.addByte((checksum >> 8) & 0xFF);
    message.addByte((checksum >> 16) & 0xFF);
    message.addByte((checksum >> 24) & 0xFF);

    // magic值
    final magic = command ^ 0xFFFFFFFF;
    message.addByte(magic & 0xFF);
    message.addByte((magic >> 8) & 0xFF);
    message.addByte((magic >> 16) & 0xFF);
    message.addByte((magic >> 24) & 0xFF);

    // 数据载荷
    if (data != null) {
      for (int i = offset; i < offset + length; i++) {
        message.addByte(data[i]);
      }
    }

    return message.build();
  }

  /// 生成STLS消息
  static List<int> generateStls() {
    return generateMessage(aStls, aStlsVersion, 0, null);
  }
}

/// 字节构建器工具类
class _BytesBuilder {
  final List<int> _bytes = [];

  void addByte(int byte) {
    _bytes.add(byte & 0xFF);
  }

  void addByte2(int value) {
    _bytes.add(value & 0xFF);
    _bytes.add((value >> 8) & 0xFF);
  }

  void addByte4(int value) {
    _bytes.add(value & 0xFF);
    _bytes.add((value >> 8) & 0xFF);
    _bytes.add((value >> 16) & 0xFF);
    _bytes.add((value >> 24) & 0xFF);
  }

  List<int> build() => List.from(_bytes);

  /// 将命令转换为字符串表示
  static String commandToString(int command) {
    switch (command) {
      case AdbProtocol.cmdAuth:
        return "AUTH";
      case AdbProtocol.cmdCnxc:
        return "CNXN";
      case AdbProtocol.cmdOpen:
        return "OPEN";
      case AdbProtocol.cmdOkay:
        return "OKAY";
      case AdbProtocol.cmdClse:
        return "CLSE";
      case AdbProtocol.cmdWrte:
        return "WRTE";
      default:
        return "????";
    }
  }
}
