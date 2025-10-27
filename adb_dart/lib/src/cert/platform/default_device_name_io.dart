/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:io';

/// IO平台的默认设备名称
String defaultDeviceName() {
  try {
    // 尝试获取主机名
    return Platform.localHostname;
  } catch (e) {
    // 如果失败，返回默认值
    return 'dart-device';
  }
}
