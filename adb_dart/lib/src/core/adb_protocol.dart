/// ADB协议常量定义
/// 基于Android ADB协议规范
library adb_protocol;

/// ADB消息头部大小（24字节）
const int adbMessageHeaderSize = 24;

/// ADB当前版本
const int adbVersion = 0x01000000;

/// 最大数据载荷大小
const int adbMaxPayload = 256 * 1024;

/// 旧版本最大数据载荷大小（用于兼容性）
const int adbMaxPayloadLegacy = 4096;

/// ADB命令常量
class AdbProtocol {
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

  /// 获取命令名称（用于调试）
  static String getCommandName(int command) {
    switch (command) {
      case cmdSync:
        return 'SYNC';
      case cmdCnxn:
        return 'CNXN';
      case cmdAuth:
        return 'AUTH';
      case cmdOpen:
        return 'OPEN';
      case cmdOkay:
        return 'OKAY';
      case cmdClse:
        return 'CLSE';
      case cmdWrte:
        return 'WRTE';
      case cmdStls:
        return 'STLS';
      default:
        return 'UNKNOWN(0x${command.toRadixString(16).padLeft(8, '0')})';
    }
  }
}