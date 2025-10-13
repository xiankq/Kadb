import 'dart:io';

/// 默认设备名称工具类
/// 用于获取平台特定的默认设备名称
class DefaultDeviceName {
  /// 获取默认设备名称
  /// 根据当前平台返回合适的设备名称
  static String get() {
    try {
      final platform = Platform.operatingSystem;
      
      switch (platform) {
        case 'linux':
          return _getLinuxDeviceName();
        case 'macos':
          return _getMacOSDeviceName();
        case 'windows':
          return _getWindowsDeviceName();
        case 'android':
          return _getAndroidDeviceName();
        default:
          return _getFallbackDeviceName();
      }
    } catch (e) {
      return _getFallbackDeviceName();
    }
  }

  /// 获取Linux设备名称
  static String _getLinuxDeviceName() {
    try {
      // 尝试获取主机名
      final hostname = Platform.localHostname;
      if (hostname.isNotEmpty) {
        return 'Linux-$hostname';
      }
    } catch (e) {
      // 忽略错误，使用备用名称
    }
    
    return 'Linux-Unknown';
  }

  /// 获取macOS设备名称
  static String _getMacOSDeviceName() {
    try {
      final hostname = Platform.localHostname;
      if (hostname.isNotEmpty) {
        return 'Mac-$hostname';
      }
    } catch (e) {
      // 忽略错误，使用备用名称
    }
    
    return 'Mac-Unknown';
  }

  /// 获取Windows设备名称
  static String _getWindowsDeviceName() {
    try {
      final hostname = Platform.localHostname;
      if (hostname.isNotEmpty) {
        return 'Windows-$hostname';
      }
    } catch (e) {
      // 忽略错误，使用备用名称
    }
    
    return 'Windows-Unknown';
  }

  /// 获取Android设备名称
  static String _getAndroidDeviceName() {
    try {
      // Android设备可能有特定的环境变量或文件
      final hostname = Platform.localHostname;
      if (hostname.isNotEmpty) {
        return 'Android-$hostname';
      }
    } catch (e) {
      // 忽略错误，使用备用名称
    }
    
    return 'Android-Unknown';
  }

  /// 获取备用设备名称
  static String _getFallbackDeviceName() {
    return 'Unknown-Device';
  }

  /// 验证设备名称是否有效
  static bool isValidDeviceName(String name) {
    if (name.isEmpty || name.length > 64) {
      return false;
    }
    
    // 检查是否包含非法字符
    final invalidChars = RegExp(r'[<>:"/\\|?*]');
    if (invalidChars.hasMatch(name)) {
      return false;
    }
    
    return true;
  }

  /// 清理设备名称
  /// 移除非法字符并限制长度
  static String sanitizeDeviceName(String name) {
    if (name.isEmpty) {
      return _getFallbackDeviceName();
    }
    
    // 移除非法字符
    var cleaned = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
    
    // 限制长度
    if (cleaned.length > 64) {
      cleaned = cleaned.substring(0, 64);
    }
    
    // 如果清理后为空，使用备用名称
    if (cleaned.isEmpty) {
      return _getFallbackDeviceName();
    }
    
    return cleaned;
  }
}