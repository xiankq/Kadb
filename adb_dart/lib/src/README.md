/**
 * ADB Dart - 纯Dart实现的ADB协议库
 *
 * 功能特点:
 * ✓ 完整复刻Kadb核心功能
 * ✓ 纯Dart实现，无Flutter依赖
 * ✓ 支持ADB协议的所有核心功能
 * ✓ 中文注释和错误信息
 * ✓ 简洁易用的API设计
 *
 * 已实现功能:
 * ✓ TCP连接管理
 * ✓ ADB消息协议处理
 * ✓ RSA密钥对生成和管理
 * ✓ Android公钥格式转换
 * ✓ 设备认证和连接建立
 * ✓ Shell命令执行
 * ✓ 交互式Shell流
 * ✓ APK安装和卸载
 * ✓ 设备信息获取
 *
 * TODO功能（已标识）:
 * ⚠ TLS/SSL加密传输
 * ⚠ 文件同步协议（push/pull）
 * ⚠ 端口转发功能
 * ⚠ PEM格式密钥导入导出
 * ⚠ 完整的X.509证书生成
 *
 * 架构设计:
 * 1. 核心层 (src/core/)
 *    - adb_protocol.dart: ADB协议常量定义
 *    - adb_message.dart: ADB消息结构定义
 *    - adb_reader.dart: ADB消息读取器
 *    - adb_writer.dart: ADB消息写入器
 *    - adb_connection.dart: ADB连接管理
 *
 * 2. 证书层 (src/cert/)
 *    - adb_key_pair.dart: RSA密钥对管理
 *    - android_pubkey.dart: Android公钥格式转换
 *
 * 3. 队列层 (src/queue/)
 *    - adb_message_queue.dart: 异步消息队列管理
 *
 * 4. 流层 (src/stream/)
 *    - adb_stream.dart: ADB数据流管理
 *
 * 5. 异常层 (src/exception/)
 *    - adb_exceptions.dart: 异常定义
 *
 * 6. 工具层 (src/utils/)
 *    - crc32.dart: CRC32校验和计算
 *
 * 使用示例:
 * ```dart
 * final adb = AdbDart(host: 'localhost', port: 5555);
 * await adb.connect();
 *
 * // 执行shell命令
 * final result = await adb.shell('ls -la');
 * print(result);
 *
 * // 获取设备信息
 * final info = await adb.getDeviceInfo();
 * print('序列号: ${info.serialNumber}');
 *
 * // 安装APK
 * await adb.installApk('/path/to/app.apk');
 *
 * await adb.disconnect();
 * ```
 *
 * 技术实现依据:
 * - 基于Android ADB官方协议文档
 * - 参考Kadb的Kotlin实现架构
 * - 遵循libmincrypt的RSA公钥格式
 * - 实现完整的ADB握手和认证流程
 *
 * 注意事项:
 * - 使用前确保设备已启用ADB调试
 * - 首次连接可能需要授权
 * - 部分功能需要设备root权限
 * - 文件同步功能待实现
 *
 * 作者: Claude AI
 * 日期: 2025-10-29
 * 版本: 1.0.0
 */

export 'src/core/adb_connection.dart';
export 'src/core/adb_protocol.dart';
export 'src/cert/adb_key_pair.dart';
export 'src/stream/adb_stream.dart';
export 'src/exception/adb_exceptions.dart';
export 'adb_dart.dart';