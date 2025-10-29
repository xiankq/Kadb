# AdbDart - 纯Dart实现的ADB协议库

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

纯 Dart 实现的 Android Debug Bridge (ADB) 协议库，完整复刻 Kadb 功能。

## 🚀 功能特性

### ✅ 核心功能
- **完整的ADB协议实现** - 基于官方ADB协议文档实现
- **RSA认证** - 支持RSA密钥对生成和Android公钥格式
- **连接管理** - 可靠的TCP连接和消息队列管理
- **异常处理** - 完整的中文异常体系

### ✅ 高级功能
- **TLS/SSL加密** - 安全的设备配对和通信
- **设备配对** - WiFi设备配对支持（SPAKE2+TLS）
- **端口转发** - TCP端口转发功能
- **文件同步** - ADB SYNC协议实现
- **Shell命令** - 交互式Shell和命令执行
- **Shell v2** - 支持标准输入/输出/错误分离

### ✅ 传输层
- **TCP传输** - 标准TCP连接
- **TLS传输** - 加密安全连接
- **消息队列** - 异步消息处理
- **流管理** - 双向数据流支持

## 📦 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  adb_dart:
    path: ../adb_dart
```

## 🎯 快速开始

### 基本连接

```dart
import 'package:adb_dart/adb_dart.dart';

void main() async {
  // 创建ADB客户端
  final adb = AdbDart(
    host: 'localhost',
    port: 5555,
  );

  try {
    // 连接到设备
    await adb.connect();
    print('已连接到设备');

    // 获取设备信息
    final deviceInfo = await adb.getDeviceInfo();
    print('设备型号: ${deviceInfo.model}');

    // 执行Shell命令
    final result = await adb.shell('getprop ro.product.model');
    print('设备型号: $result');

  } catch (e) {
    print('连接失败: $e');
  } finally {
    await adb.disconnect();
  }
}
```

### TLS安全配对

```dart
import 'package:adb_dart/adb_dart.dart';
import 'package:adb_dart/src/cert/adb_key_pair.dart';

void main() async {
  // 生成RSA密钥对
  final keyPair = AdbKeyPair.generate(
    keySize: 2048,
    commonName: 'my_device',
  );

  // 执行安全配对
  await TlsDevicePairingManager.pairDeviceSecurely(
    host: '192.168.1.100',
    port: 5555,
    pairingCode: '123456', // 6位配对码
    keyPair: keyPair,
    deviceName: 'my_computer',
    useTls: true, // 启用TLS加密
  );

  print('设备配对成功！');
}
```

### 文件传输

```dart
// 推送文件到设备
final localFile = File('app.apk');
final stream = await adb.openStream('sync:');
final syncStream = AdbSyncStream(stream);
await syncStream.send(localFile, '/data/local/tmp/app.apk');
await stream.close();

// 从设备拉取文件
final remoteFile = File('downloaded.txt');
await syncStream.recv('/sdcard/file.txt', remoteFile);
```

### 端口转发

```dart
// 设置端口转发
final forwarder = await adb.forward(
  hostPort: 8080,
  targetPort: 80,
);

print('端口转发已启动: localhost:8080 -> device:80');

// 使用转发...

// 停止转发
await forwarder.stop();
```

## 🔧 高级用法

### 交互式Shell

```dart
// 打开交互式Shell
final stream = await adb.openStream('shell:');
final shellStream = AdbShellStream(stream);

// 监听输出
shellStream.dataStream.listen((data) {
  print(utf8.decode(data));
});

// 发送命令
await stream.writeString('ls -la\n');

// 等待退出
await stream.close();
```

### 自定义密钥对

```dart
// 生成自定义密钥对
final keyPair = AdbKeyPair.generate(
  keySize: 2048,
  commonName: 'my_adb_client',
  organization: 'MyCompany',
);

// 保存公钥
final publicKey = keyPair.getAdbPublicKey();
File('my_key.pub').writeAsBytesSync(publicKey);

// 使用密钥对连接
final adb = AdbDart(
  host: 'localhost',
  port: 5555,
  keyPair: keyPair,
);
```

### TLS配置

```dart
// 自定义TLS配置
final tlsConfig = TlsConfig(
  enabled: true,
  handshakeTimeout: Duration(seconds: 60),
  requireClientCertificate: true,
);

// 使用TLS包装器
final tlsWrapper = await TlsWrapper.create(
  socket: socket,
  host: 'device_ip',
  port: 5555,
  isServer: false,
  keyPair: keyPair,
);
```

## 📁 项目结构

```
adb_dart/
├── lib/
│   ├── adb_dart.dart           # 主库文件
│   ├── src/
│   │   ├── core/               # 核心协议实现
│   │   │   ├── adb_protocol.dart     # 协议常量
│   │   │   ├── adb_message.dart      # 消息结构
│   │   │   ├── adb_connection.dart   # 连接管理
│   │   │   └── ...
│   │   ├── cert/               # 证书和密钥管理
│   │   │   ├── adb_key_pair.dart     # RSA密钥对
│   │   │   └── android_pubkey.dart   # Android公钥格式
│   │   ├── transport/          # 传输层
│   │   │   ├── transport_channel.dart # 传输接口
│   │   │   └── socket_transport.dart  # TCP传输
│   │   ├── stream/             # 流管理
│   │   │   ├── adb_stream.dart       # 基础流
│   │   │   ├── adb_shell_stream.dart # Shell流
│   │   │   └── adb_sync_stream.dart  # 文件同步
│   │   ├── shell/              # Shell协议
│   │   │   └── adb_shell_packet_v2.dart # Shell v2协议
│   │   ├── forwarding/         # 端口转发
│   │   │   └── tcp_forwarder.dart     # TCP转发
│   │   ├── pair/               # 设备配对
│   │   │   ├── pairing_connection_ctx.dart # 配对连接
│   │   │   └── pairing_auth_ctx.dart     # 认证上下文
│   │   ├── tls/                # TLS/SSL支持
│   │   │   └── ssl_utils.dart       # SSL工具类
│   │   ├── queue/              # 消息队列
│   │   │   └── adb_message_queue.dart # 消息管理
│   │   └── exception/          # 异常定义
│   │       └── adb_exceptions.dart    # 异常类
│   └── example/
│       ├── basic_usage.dart    # 基础使用示例
│       └── tls_pairing_example.dart # TLS配对示例
├── pubspec.yaml
└── README.md
```

## 🔍 协议实现详情

### ADB协议支持
- **连接阶段** - CNXN消息和认证
- **认证阶段** - RSA公钥交换
- **命令阶段** - OPEN/CLOSE/WRITE/OKAY消息
- **流控制** - 基于OKAY的流控机制

### 文件同步协议 (SYNC)
- **SEND** - 发送文件到设备
- **RECV** - 从设备接收文件
- **STAT** - 获取文件状态信息
- **LIST** - 列出目录内容
- **64KB分块** - 大数据分块传输

### Shell v2协议
- **标准I/O分离** - stdin/stdout/stderr独立流
- **退出码支持** - 命令返回值获取
- **窗口大小** - 终端窗口大小调整
- **信号处理** - 进程信号支持

### 设备配对协议
- **SPAKE2+认证** - 密码认证密钥交换
- **TLS加密** - 传输层安全保护
- **RSA密钥交换** - 公钥基础设施
- **二维码支持** - 快速配对二维码

## ⚠️ 注意事项

1. **Android版本兼容性** - 支持Android 4.0+
2. **网络要求** - WiFi调试需要设备和电脑在同一网络
3. **安全配对** - 首次配对需要确认设备上的授权对话框
4. **权限要求** - 设备需要启用ADB调试模式

## 🐛 故障排除

### 连接失败
- 检查设备是否启用了ADB调试
- 确认网络连接正常
- 验证IP地址和端口正确
- 检查防火墙设置

### 配对失败
- 确认配对码正确（6位数字）
- 检查设备是否在配对模式
- 验证时间同步（影响TLS握手）
- 尝试重新生成密钥对

### 文件传输失败
- 检查文件权限
- 确认目标路径存在
- 验证存储空间充足
- 检查SELinux策略

## 📚 相关文档

- [Android Debug Bridge文档](https://developer.android.com/studio/command-line/adb)
- [ADB协议规范](https://android.googlesource.com/platform/system/core/+/master/adb/protocol.txt)
- [Kadb项目](https://github.com/vidstige/kadb) - Kotlin实现参考
- [ADB第三方文档](adb-thirdparty-doc/) - 协议实现细节
- [libmincrypt](libmincrypt/) - Android加密库参考

## 🤝 贡献

欢迎提交Issue和Pull Request！

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- [Kadb](https://github.com/vidstige/kadb) - 提供实现参考
- [Android Open Source Project](https://source.android.com/) - ADB协议规范
- [Dart团队](https://dart.dev/) - 优秀的Dart语言