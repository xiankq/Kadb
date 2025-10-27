# ADB Dart

纯Dart实现的ADB（Android Debug Bridge）客户端库，基于Kadb项目移植。

## 功能特性

✅ 基本ADB协议支持  
✅ ADB消息解析和构建  
✅ ADB连接管理  
✅ Shell命令执行框架  
✅ 密钥管理框架  
⚠️  设备配对（待完善）  
⚠️  文件传输（待完善）  
⚠️  APK安装（待完善）  

## 安装

```yaml
dependencies:
  adb_dart:
    path: ../adb_dart
```

## 使用方法

### 基本连接

```dart
import 'package:adb_dart/adb_dart.dart';

void main() async {
  // 创建ADB客户端
  final client = AdbClient.create(host: 'localhost', port: 5037);
  
  try {
    // 连接到ADB服务器
    await client.connect();
    print('连接成功');
    
    // 执行shell命令
    final result = await client.shell('echo "Hello ADB"');
    print('输出: ${result.stdout}');
    
  } catch (e) {
    print('错误: $e');
  } finally {
    // 断开连接
    await client.dispose();
  }
}
```

### 命令行工具

```bash
# 连接到ADB服务器
dart run adb_dart connect localhost 5037

# 执行shell命令
dart run adb_dart shell "getprop ro.product.model"

# 查看设备信息
dart run adb_dart devices

# 安装APK
dart run adb_dart install app.apk

# 卸载应用
dart run adb_dart uninstall com.example.app
```

## 项目结构

```
adb_dart/
├── lib/
│   ├── src/
│   │   ├── core/           # 核心ADB协议实现
│   │   │   ├── adb_connection.dart
│   │   │   ├── adb_message.dart
│   │   │   ├── adb_protocol.dart
│   │   │   ├── adb_reader.dart
│   │   │   └── adb_writer.dart
│   │   ├── cert/           # 证书和密钥管理
│   │   │   ├── adb_key_pair.dart
│   │   │   └── cert_utils.dart
│   │   ├── shell/          # Shell命令执行
│   │   │   ├── adb_shell_response.dart
│   │   │   └── adb_shell_stream.dart
│   │   ├── stream/         # 流管理
│   │   │   └── adb_stream.dart
│   │   └── adb_client.dart # 主客户端类
│   └── adb_dart.dart       # 库入口文件
├── bin/
│   └── adb_dart.dart       # 命令行工具
└── test/
    └── adb_dart_test.dart  # 测试文件
```

## 待实现功能

以下是当前版本中的TODO列表，按优先级排序：

### 高优先级
- [ ] RSA密钥生成和签名功能
- [ ] TLS加密连接支持
- [ ] 完整的Shell命令执行
- [ ] 消息路由机制

### 中优先级
- [ ] 文件推送/拉取（sync协议）
- [ ] APK安装/卸载
- [ ] 设备配对功能
- [ ] 端口转发

### 低优先级
- [ ] 单元测试覆盖
- [ ] 性能优化
- [ ] 文档完善

## 技术细节

### ADB协议实现

本项目基于Kadb的协议实现，主要包含：

1. **消息格式**：实现了ADB协议的消息头和载荷格式
2. **连接流程**：支持AUTH认证和CNXN连接建立
3. **流管理**：支持OPEN/CLOSE/OKAY/WRTE消息类型

### 架构设计

采用分层架构：
- **协议层**：处理底层ADB消息格式
- **连接层**：管理与服务器的连接状态
- **应用层**：提供用户友好的API接口

## 注意事项

⚠️ **当前版本为开发预览版**，以下功能尚未完全实现：

- 加密连接（TLS）
- 完整的认证流程
- 文件传输
- 设备配对

这些功能将在后续版本中逐步完善。

## 许可证

基于Kadb项目的Apache 2.0许可证。

## 贡献

欢迎提交Issue和Pull Request来帮助改进这个项目。

## 相关项目

- [Kadb](https://github.com/flyfishxu/Kadb) - Kotlin实现的ADB库（本项目的基础）