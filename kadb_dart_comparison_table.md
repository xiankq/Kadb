# Kadb Kotlin 与 Kadb Dart 项目表格对比分析

## 1. 项目结构对比

| 方面 | Kotlin项目 | Dart项目 | 说明 |
|------|------------|----------|------|
| 主要目录 | `kadb/src/commonMain/kotlin/com/flyfishxu/kadb/` | `kadb_dart/lib/` | 目录结构基本一致 |
| 模块划分 | `core`, `stream`, `transport`, `queue`, `cert`, `exception`, `shell`, `forwarding`, `tls`, `debug`, `pair` | `core`, `stream`, `transport`, `queue`, `cert`, `exception`, `shell`, `forwarding`, `tls`, `debug`, `pair` | 模块划分完全一致 |
| 包组织 | `com.flyfishxu.kadb` | `kadb_dart` | 基本一致 |

## 2. 核心类API设计对比

### AdbConnection 类对比

| 特性 | Kotlin | Dart | 说明 |
|------|--------|------|------|
| 构造方式 | `internal class AdbConnection internal constructor(...)` | `AdbConnection({required AdbKeyPair keyPair, ...})` | 构造方式适配语言特性 |
| 连接方法 | `suspend fun connect(...)` | `Future<void> connect(String host, int port, {bool useTls = false})` | 异步方式不同 |
| 流打开 | `fun open(destination: String): AdbStream` | `Future<AdbStream> open(String destination)` | 功能一致 |
| 连接关闭 | `override fun close()` | `void close()` | 功能一致 |

### AdbStream 类对比

| 特性 | Kotlin | Dart | 说明 |
|------|--------|------|------|
| 读取接口 | `val source = object : Source` | `AdbStreamSource get source` | Dart提供更结构化接口 |
| 写入接口 | `val sink = object : Sink` | `AdbStreamSink get sink` | Dart提供更结构化接口 |
| 远程ID获取 | 通过构造参数获取 | `Future<void> waitForRemoteId()` | Dart增加等待方法 |
| 关闭方法 | `override fun close()` | `Future<void> close()` | 都支持关闭 |

### AdbProtocol 类对比

| 特性 | Kotlin | Dart | 说明 |
|------|--------|------|------|
| 常量定义 | `const val CMD_CNXN = 0x4e584e43` | `static const int cmdCnxn = 0x4e584e43` | 常量定义一致 |
| 消息生成 | `private fun generateMessage(...)` | `static List<int> generateMessage(...)` | 功能一致 |
| 校验和计算 | `private fun getPayloadChecksum(...)` | `static int getPayloadChecksum(...)` | 功能一致 |
| 字节序处理 | 使用 `ByteBuffer.order(ByteOrder.LITTLE_ENDIAN)` | 使用 `_writeIntLe`/`_readIntLe` | 实现方式不同 |

## 3. ADB 协议实现对比

| 特性 | Kotlin | Dart | 说明 |
|------|--------|------|------|
| 消息格式 | 使用 `AdbMessage` 数据类 | 使用 `AdbMessage` 类 | 消息结构一致 |
| 消息读取 | `fun readMessage(): AdbMessage` | `Future<AdbMessage> readMessage()` | 功能一致，异步方式不同 |
| 消息写入 | `fun write(...)` | `Future<void> write(...)` | 功能一致 |
| 魔数验证 | 在 `readMessage` 中验证 | 在 `readMessage` 中验证 | 实现一致 |

## 4. 流处理机制对比

### 消息队列机制

| 特性 | Kotlin | Dart | 说明 |
|------|--------|------|------|
| 基础类 | `AdbMessageQueue` 继承 `MessageQueue<AdbMessage>` | 独立实现 | 继承 vs 独立实现 |
| 消息获取 | `fun take(localId: Int, command: Int): AdbMessage` | `Future<AdbMessage> take(int localId, int command)` | 功能一致，异步方式不同 |
| 超时处理 | 无显式超时 | 有超时机制 | Dart增加超时处理 |
| 队列管理 | 内置队列管理 | 使用 `Map<int, Map<int, Queue<AdbMessage>>>` | 实现方式一致 |

### 数据流处理

| 特性 | Kotlin | Dart | 说明 |
|------|--------|------|------|
| 数据读取 | Okio Source 模式 | Stream 模式 | 基于不同库的实现 |
| 数据写入 | Okio Sink 模式 | Future 模式 | 基于不同库的实现 |
| 缓冲区大小 | 默认缓冲区 | 优化为128KB块大小 | Dart优化性能 |

## 5. 传输层实现对比

### TransportChannel 接口

| 特性 | Kotlin | Dart | 说明 |
|------|--------|------|------|
| 接口定义 | `interface TransportChannel : Closeable` | `abstract class TransportChannel` | 接口形式不同 |
| 读方法 | `suspend fun read(dst: ByteBuffer, timeout: Long, unit: TimeUnit): Int` | `Future<int> read(Uint8List dst, Duration timeout)` | 参数类型不同 |
| 写方法 | `suspend fun write(src: ByteBuffer, timeout: Long, unit: TimeUnit): Int` | `Future<int> write(Uint8List src, Duration timeout)` | 参数类型不同 |
| 读取全部 | `suspend fun readExactly(...)` | `Future<void> readExactly(...)` | 功能一致 |

## 6. 认证机制对比

| 特性 | Kotlin | Dart | 说明 |
|------|--------|------|------|
| 密钥对 | `AdbKeyPair` | `AdbKeyPair` | 实现一致 |
| 认证类型 | `AUTH_TYPE_TOKEN`, `AUTH_TYPE_SIGNATURE`, `AUTH_TYPE_RSA_PUBLIC` | `authTypeToken`, `authTypeSignature`, `authTypeRsaPublic` | 常量定义一致 |
| 认证流程 | 在 `AdbConnection.connect()` 中处理 | 在 `_handleAuthentication()` 和 `_performAuthentication()` 中处理 | 逻辑一致，实现方式不同 |
| 签名方法 | `keyPair.signPayload(message)` | `keyPair.signAdbMessagePayload(tokenData)` | 功能一致 |

## 7. 错误处理机制对比

| 特性 | Kotlin | Dart | 说明 |
|------|--------|------|------|
| 异常类型 | `IOException`, `AdbAuthException` 等 | 专用异常类（`AdbAuthException`, `AdbStreamClosed` 等） | Dart定义更具体异常 |
| 异常处理 | try-catch | Future/Stream错误处理 | 异步处理方式不同 |
| 连接关闭异常 | 依赖底层异常 | `AdbStreamClosed` | Dart定义专用异常 |
| 超时处理 | 依赖底层超时 | 显式超时处理 | Dart更完善的超时 |

## 8. 特定功能对比

### TCP 转发器

| 特性 | Kotlin | Dart | 说明 |
|------|--------|------|------|
| 基本转发 | `TcpForwarder` | `TcpForwarder` | 基本功能一致 |
| 反向转发 | 无 | `ReverseTcpForwarder` | Dart增加反向转发 |
| 状态管理 | `enum class State` | `enum TcpForwarderState` | 实现一致 |
| 并发处理 | 线程池 | Future并发 | 并发模型不同 |
| 错误处理 | 基础错误处理 | 详细错误处理和提示 | Dart更完善 |

### 性能优化

| 特性 | Kotlin | Dart | 说明 |
|------|--------|------|------|
| I/O库 | Okio | dart:io | 不同的I/O库 |
| 缓冲区 | Okio缓冲 | 自定义缓冲 | Dart优化缓冲区大小 |
| 数据块大小 | 默认大小 | 优化为64KB/128KB | Dart优化性能 |

## 9. 总结

| 对比维度 | 相似度 | 说明 |
|----------|--------|------|
| 整体架构 | 非常相似 | Dart项目完整复刻了Kotlin的设计理念 |
| API设计 | 非常相似 | API命名和调用方式基本一致 |
| 功能实现 | 非常相似 | 核心功能都得到完整实现 |
| 错误处理 | Dart更完善 | Dart增加了更多错误处理机制 |
| 性能优化 | Dart有额外优化 | Dart针对特定场景进行了优化 |
| 扩展功能 | Dart更丰富 | Dart增加了一些新功能（如反向转发） |

Dart项目很好地遵循了Kotlin版本的设计理念，API命名和调用方式基本一致，同时根据Dart语言的特性进行了适当的调整和优化，还增加了一些额外的功能和错误处理机制。