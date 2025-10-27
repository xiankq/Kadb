/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

/// 平台特定的默认设备名称
String defaultDeviceName() {
  // 默认实现，平台特定的版本会覆盖
  return 'dart-device';
}
