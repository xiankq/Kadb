/// ADB协议常量定义
/// 基于Android ADB协议规范
library adb_protocol;

/// ADB命令常量
class AdbProtocol {
  /// ADB消息头部大小（24字节）
  static const int adbMessageHeaderSize = 24;

  /// ADB当前版本
  static const int adbVersion = 0x01000000;

  /// 最大数据载荷大小
  static const int adbMaxPayload = 256 * 1024;

  /// 旧版本最大数据载荷大小（用于兼容性）
  static const int adbMaxPayloadLegacy = 4096;

  // 核心命令
  static const int cmdSync = 0x434e5953; // 'SYNC'
  static const int cmdCnxn = 0x4e584e43; // 'CNXN'
  static const int cmdAuth = 0x48545541; // 'AUTH'
  static const int cmdOpen = 0x4e45504f; // 'OPEN'
  static const int cmdOkay = 0x59414b4f; // 'OKAY'
  static const int cmdClse = 0x45534c43; // 'CLSE'
  static const int cmdWrte = 0x45545257; // 'WRTE'
  static const int cmdStls = 0x534c5453; // 'STLS'

  // 认证类型
  static const int authTypeToken = 1;
  static const int authTypeSignature = 2;
  static const int authTypeRsaPublic = 3;

  // 系统类型
  static const String systemTypeBootloader = 'bootloader';
  static const String systemTypeDevice = 'device';
  static const String systemTypeHost = 'host';

  // 特征支持
  static const Set<String> supportedFeatures = {
    'fixed_push_symlink_timestamp',
    'apex',
    'fixed_push_mkdir',
    'stat_v2',
    'abb_exec',
    'cmd',
    'abb',
    'shell_v2',
  };

  /// 获取命令名称
  static String getCommandName(int command) {
    final raw = '0x${command.toRadixString(16).padLeft(8, '0')}';
    switch (command) {
      case cmdSync:
        return 'SYNC ($raw)';
      case cmdCnxn:
        return 'CNXN ($raw)';
      case cmdAuth:
        return 'AUTH ($raw)';
      case cmdOpen:
        return 'OPEN ($raw)';
      case cmdOkay:
        return 'OKAY ($raw)';
      case cmdClse:
        return 'CLSE ($raw)';
      case cmdWrte:
        return 'WRTE ($raw)';
      case cmdStls:
        return 'STLS ($raw)';
      default:
        return 'UNKNOWN ($raw)';
    }
  }
}
