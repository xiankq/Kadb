# ADB Dart

[![Pub Version](https://img.shields.io/pub/v/adb_dart.svg)](https://pub.dev/packages/adb_dart)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://github.com/your-username/adb_dart/blob/main/LICENSE)

纯 Dart 实现的 Android Debug Bridge (ADB) 协议库，完整复刻 Kadb 功能。

## 功能特性

✅ **完整的 ADB 协议支持**
- 连接建立和 RSA 认证
- TLS 加密支持（完整实现）
- 完整的握手流程

✅ **Shell 命令执行**
- 同步命令执行
- 交互式 Shell 支持
- 标准输入/输出/错误分离（v2 协议）
- 退出码获取

✅ **文件传输**
- 文件推送（push）
- 文件拉取（pull）
- 大文件分块传输（64KB）
- 进度回调支持
- 文件权限保持（完整实现）

✅ **应用管理**
- APK 安装/卸载
- 多 APK 安装支持
- 应用列表获取

✅ **设备管理**
- 设备信息获取
- 目录列表
- 文件状态查询
- 设备重启控制

✅ **高级特性**
- TCP 端口转发（完整实现）
- WiFi 设备配对（完整实现）
- 自定义 RSA 密钥对
- 连接池管理

## 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  adb_dart: ^1.0.0
```

## 快速开始

```dart
import 'package:adb_dart/adb_dart.dart';

void main() async {
  // 创建 ADB 连接
  final adb = Kadb('localhost', 5555);
  
  try {
    // 建立连接
    await adb.connect();
    
    // 执行 Shell 命令
    final response = await adb.shell('ls -la /sdcard');
    print('输出: ${response.output}');
    print('退出码: ${response.exitCode}');
    
  } catch (e) {
    print('错误: $e');
  } finally {
    // 关闭连接
    await adb.close();
  }
}
```

## 核心功能

### Shell 命令执行

```dart
// 同步执行命令
final response = await adb.shell('pwd');
print('当前目录: ${response.output.trim()}');

// 交互式 Shell
final shell = await adb.openShellStream();
shell.stdoutStream.listen((text) => print(text));
shell.stderrStream.listen((text) => print('错误: $text'));

await shell.writeInput('ls -la\n');
final result = await shell.readAll();
print('退出码: ${result.exitCode}');
```

### 文件传输

```dart
// 推送文件
await adb.pushFile(
  localFile: 'test.txt',
  remotePath: '/sdcard/test.txt',
  onProgress: (transferred, total) {
    print('进度: ${(transferred / total * 100).toStringAsFixed(1)}%');
  },
);

// 拉取文件
await adb.pullFile(
  localFile: 'downloaded.txt',
  remotePath: '/sdcard/test.txt',
);

// 获取文件信息
final info = await adb.statFile('/sdcard/test.txt');
print('文件大小: ${info['size']} 字节');
print('权限: ${info['permissions']}');
```

### 应用管理

```dart
// 安装 APK
await adb.installApk(
  apkFile: 'app.apk',
  options: ['-r'], // 重新安装
);

// 卸载应用
await adb.uninstallApp('com.example.app');

// 获取应用列表
final response = await adb.shell('pm list packages -f');
print(response.output);
```

### 设备信息

```dart
// 获取设备信息
final deviceInfo = await adb.getDeviceInfo();
print('设备型号: ${deviceInfo['ro.product.model']}');
print('Android 版本: ${deviceInfo['ro.build.version.release']}');

// 获取序列号
final serialNumber = await adb.getSerialNumber();
print('序列号: $serialNumber');
```

## 高级用法

### 自定义密钥对

```dart
import 'package:adb_dart/adb_dart.dart';

void main() async {
  // 生成新的密钥对
  final keyPair = await CertUtils.generateKeyPair(
    deviceName: 'my_device',
  );
  
  // 使用自定义密钥对连接
  final adb = Kadb('localhost', 5555);
  await adb.connect(keyPair: keyPair);
  
  // ... 使用 adb
}
```

### 错误处理

```dart
try {
  final response = await adb.shell('ls /nonexistent');
  if (response.isFailure) {
    print('命令失败: 退出码 ${response.exitCode}');
    print('错误输出: ${response.errorOutput}');
  }
} on AdbConnectionException catch (e) {
  print('连接错误: $e');
} on AdbShellException catch (e) {
  print('Shell 错误: $e');
} on AdbFileException catch (e) {
  print('文件错误: $e');
}
```

### 超时设置

```dart
final adb = Kadb(
  'localhost',
  5555,
  connectionTimeout: Duration(seconds: 10),
  readTimeout: Duration(seconds: 30),
  writeTimeout: Duration(seconds: 30),
);
```

## 架构设计

### 核心组件

- **AdbConnection**: 连接管理，处理握手和认证
- **AdbProtocol**: 协议常量定义
- **AdbMessage**: 消息格式处理
- **AdbStream**: 基础流管理
- **AdbSyncStream**: 文件同步协议
- **AdbShellStream**: Shell v2 协议
- **AdbKeyPair**: RSA 密钥管理
- **AndroidPubkey**: Android 格式公钥转换

### 协议支持

- **TCP 传输**: 基于 Dart Socket 的异步实现
- **消息格式**: 24 字节头部 + 载荷，小端字节序
- **认证机制**: RSA/ECB/NoPadding + PKCS#1 v1.5 填充
- **文件传输**: SYNC 协议，64KB 分块
- **Shell 执行**: v2 协议，支持标准 I/O 分离

### 特性检测

```dart
// 检查支持的特性
if (adb.connection.supportsFeature('cmd')) {
  // 使用 cmd 命令
  await adb.shell('cmd package list packages');
}

if (adb.connection.supportsFeature('abb_exec')) {
  // 使用 abb_exec 命令
  await adb.shell('abb_exec:package0install-create');
}
```

## 性能优化

- **异步 I/O**: 所有操作都是异步的
- **流式传输**: 大文件分块处理，不占用大量内存
- **连接复用**: 支持长连接和连接池
- **超时控制**: 完善的超时机制

## 错误处理

库提供了详细的异常类型：

- `AdbException`: 基础异常
- `AdbConnectionException`: 连接相关异常
- `AdbAuthException`: 认证异常
- `AdbStreamException`: 流操作异常
- `AdbFileException`: 文件操作异常
- `AdbShellException`: Shell 执行异常
- `AdbTimeoutException`: 超时异常

## 已知限制

- **USB 传输**: 仅支持 TCP 连接
- **RSA 操作**: 已实现基于 pointycastle 库的完整 RSA 支持

## 开发计划

- [x] 实现 TLS 加密支持 ✅
- [ ] 添加 USB 传输支持
- [x] 实现 WiFi 设备配对 ✅
- [x] 集成完整的 RSA 加密库 ✅
- [x] 添加 TCP 端口转发 ✅
- [ ] 支持多设备并发操作
- [ ] 添加更多测试用例

## 贡献指南

欢迎提交 Issue 和 Pull Request！

## 许可证

Apache License 2.0

## 致谢

感谢 [Kadb](https://github.com/Flyfish233/kadb) 项目提供的优秀实现参考。