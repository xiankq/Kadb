# Scrcpy Server 流解析示例

这个示例程序演示了如何使用 KadbDart 连接到 Android 设备，启动 scrcpy-server，并解析其回传的音视频流。

## 功能

- 连接到指定的 Android 设备 (192.168.2.32:5556)
- 推送 scrcpy-server 到设备
- 设置 ADB 隧道 (forward 模式)
- 启动单个 scrcpy 服务器实例
- 使用 Socket 直接连接到本地端口
- 解析流数据并每5秒输出统计信息

## 使用方法

1. 确保 Android 设备已启用 ADB 调试并连接到网络
2. 确保 `assets/scrcpy-server` 文件存在
3. 运行程序：
   ```bash
   dart run example-dartonly/scrcpy_server_parsing.dart
   ```

## 输出信息

程序会每5秒输出一次统计信息，包括：
- 各流的总字节数和包数
- 传输速度（字节/秒）
- 解码器ID
- 视频流的分辨率
- 配置包和关键帧数量

## 注意事项

- 这只是一个示例程序，用于验证流解析的可行性
- 实际使用中可能需要根据具体的 scrcpy 协议版本进行调整
- 程序会运行1小时，按 Ctrl+C 可以提前停止

## Scrcpy协议解析

根据scrcpy文档，流数据格式如下：

### 视频/音频流格式
- 首先发送codec元数据：
  - 视频：12字节 (codec ID + 宽度 + 高度)
  - 音频：4字节 (codec ID)
- 每个数据包前有12字节帧头：
  - 配置包标志位 (1 bit)
  - 关键帧标志位 (1 bit)
  - PTS时间戳 (62 bits)
  - 数据包大小 (32 bits)

### 帧头格式
```
[PTS (8字节) | 包大小 (4字节)]
其中PTS的最高两位用作标志位：
- 第63位：配置包标志
- 第62位：关键帧标志
```

### 连接流程说明
- 首先建立 ADB forward 隧道 (tcp:随机端口 -> localabstract:scrcpy_$scid)
- 启动 scrcpy 服务器实例，使用 tunnel_forward=true 参数
- 服务器连接到 ADB 隧道，客户端通过 Socket 直接连接到本地端口
- 成功建立数据流连接并开始接收数据

## 已实现功能

1. 成功连接到Android设备并完成认证
2. 推送scrcpy-server到设备
3. 设置ADB forward隧道
4. 启动scrcpy服务器
5. 连接到本地端口并建立数据流监听
6. 实现基本的数据解析功能

## 待完善功能

1. 完善scrcpy协议解析，正确处理各种数据包类型
2. 实现完整的视频/音频解码功能
3. 添加控制流支持（触摸、按键等）
4. 优化连接稳定性