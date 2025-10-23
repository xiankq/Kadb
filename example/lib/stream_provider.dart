import 'package:flutter/foundation.dart';
import 'package:kadb_dart/kadb_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

/// 视频编解码器枚举
enum VideoCodec { h264, h265, av1 }

/// 音频编解码器枚举
enum AudioCodec { opus, aac, raw }

/// 帧头信息
class FrameHeader {
  final bool isConfigPacket;
  final bool isKeyFrame;
  final int pts;
  final int packetSize;

  FrameHeader({
    required this.isConfigPacket,
    required this.isKeyFrame,
    required this.pts,
    required this.packetSize,
  });
}

/// 视频元数据
class VideoMetadata {
  final VideoCodec codec;
  final int width;
  final int height;

  VideoMetadata({
    required this.codec,
    required this.width,
    required this.height,
  });
}

/// 音频元数据
class AudioMetadata {
  final AudioCodec codec;

  AudioMetadata({required this.codec});
}

class VideoStreamProvider with ChangeNotifier {
  DirectForwarder? _directConnection;
  bool _isStreaming = false;
  bool _isStarting = false;
  String _streamStatus = '准备就绪';
  int _videoPort = 0;
  int _audioPort = 0;

  // 单个TCP服务器
  ServerSocket? _server;
  final List<Socket> _videoClients = [];
  final List<Socket> _audioClients = [];

  // 元数据
  VideoMetadata? _videoMetadata;
  AudioMetadata? _audioMetadata;

  // 数据缓冲区
  final BytesBuilder _dataBuffer = BytesBuilder();

  // 调试计数器
  int _dataCount = 0;
  int _videoFrameCount = 0;
  int _audioFrameCount = 0;
  int _metadataCount = 0;
  int _bufferedDataCount = 0;

  // Getters
  bool get isStreaming => _isStreaming;
  bool get isStarting => _isStarting;
  String get streamStatus => _streamStatus;
  int get videoPort => _videoPort;
  int get audioPort => _audioPort;
  DirectForwarder? get directConnection => _directConnection;

  String get videoUrl => 'tcp://127.0.0.1:$_videoPort';
  String get audioUrl => 'tcp://127.0.0.1:$_audioPort';

  VideoMetadata? get videoMetadata => _videoMetadata;
  AudioMetadata? get audioMetadata => _audioMetadata;

  // Constants
  static const int _baseVideoPort = 27183;
  static const int _baseAudioPort = 27184;
  static const int _filePermissions = 33261;
  static const String _serverPath = '/data/local/tmp/scrcpy-server.jar';
  static const String _assetPath = 'assets/scrcpy-server';

  VideoStreamProvider() {
    debugPrint('VideoStreamProvider 初始化');
  }

  Future<bool> startStream(AdbConnection connection) async {
    if (_isStarting || _isStreaming) return false;

    _updateStatus('启动视频流...', isStarting: true);

    try {
      debugPrint('📦 开始推送scrcpy-server到设备...');
      await _pushScrcpyServer(connection);
      debugPrint('✅ scrcpy-server推送完成');

      debugPrint('🎬 开始启动scrcpy服务器...');
      await _startScrcpyServer(connection);
      debugPrint('✅ scrcpy服务器启动完成');

      debugPrint('⏳ 等待scrcpy服务准备就绪...');
      // 等待一段时间确保scrcpy服务完全启动
      await Future.delayed(const Duration(seconds: 2));

      debugPrint('🔌 开始直接连接到scrcpy服务...');
      // 添加重试机制
      int retryCount = 0;
      const maxRetries = 3;

      while (retryCount < maxRetries) {
        try {
          _directConnection = DirectForwarder(
            connection,
            'localabstract:scrcpy',
            debug: false,
          );
          await _directConnection!.connect();
          debugPrint('✅ 直接连接到scrcpy服务成功');
          break;
        } catch (e) {
          retryCount++;
          debugPrint('⚠️ 连接scrcpy服务失败 (尝试 $retryCount/$maxRetries): $e');

          if (retryCount >= maxRetries) {
            rethrow;
          }

          // 等待一段时间后重试
          debugPrint('⏳ 等待 ${retryCount * 2} 秒后重试...');
          await Future.delayed(Duration(seconds: retryCount * 2));
        }
      }

      debugPrint('🌐 开始启动本地TCP服务器...');
      await _startLocalServers();
      debugPrint('✅ 本地TCP服务器启动成功');

      debugPrint('📡 开始处理数据流...');
      _startDataStreamProcessing();
      debugPrint('✅ 数据流处理已启动');

      _updateStatus('视频流已启动', isStreaming: true);
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ 视频流启动失败: $e');
      debugPrint('❌ 错误堆栈: $stackTrace');
      await _cleanupOnFailure();
      _updateStatus('启动失败: $e');
      return false;
    }
  }

  /// 启动本地TCP服务器
  Future<void> _startLocalServers() async {
    _videoPort = _baseVideoPort;
    _audioPort = _baseAudioPort;

    try {
      // 启动视频服务器
      final videoServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _videoPort,
      );
      videoServer.listen((client) => _handleClient(client, true));
      debugPrint('✅ 视频服务器启动成功: 端口 $_videoPort');

      // 启动音频服务器
      final audioServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _audioPort,
      );
      audioServer.listen((client) => _handleClient(client, false));
      debugPrint('✅ 音频服务器启动成功: 端口 $_audioPort');
    } catch (e) {
      debugPrint('❌ 启动本地TCP服务器失败: $e');
      rethrow;
    }
  }

  /// 处理客户端连接
  void _handleClient(Socket client, bool isVideo) {
    final clientType = isVideo ? '视频' : '音频';
    debugPrint(
      '📹 $clientType客户端连接: ${client.remoteAddress}:${client.remotePort}',
    );

    if (isVideo) {
      _videoClients.add(client);
    } else {
      _audioClients.add(client);
    }

    client.done.then((_) {
      if (isVideo) {
        _videoClients.remove(client);
      } else {
        _audioClients.remove(client);
      }
      debugPrint(
        '📹 $clientType客户端断开: ${client.remoteAddress}:${client.remotePort}',
      );
    });

    client.handleError((error) {
      if (isVideo) {
        _videoClients.remove(client);
      } else {
        _audioClients.remove(client);
      }
      debugPrint('📹 $clientType客户端错误: $error');
    });
  }

  /// 开始处理数据流
  void _startDataStreamProcessing() {
    if (_directConnection == null) return;

    _directConnection!.dataStream.listen(
      (data) {
        _dataCount++;
        // 每10个数据包打印一次调试信息
        if (_dataCount % 10 == 0) {
          debugPrint('📊 接收到第 $_dataCount 个数据包，大小: ${data.length} 字节');
        }

        // 将数据添加到缓冲区
        _dataBuffer.add(data);
        _bufferedDataCount += data.length;

        // 每累积1024字节数据处理一次
        if (_bufferedDataCount >= 1024) {
          final bufferedData = _dataBuffer.takeBytes();
          _bufferedDataCount = 0;
          _processScrcpyData(bufferedData);
        }
      },
      onError: (error) {
        debugPrint('❌ 数据流错误: $error');
        _updateStatus('数据流错误: $error');
      },
      onDone: () {
        debugPrint('🏁 数据流结束');
        _updateStatus('数据流已结束');

        // 处理剩余的缓冲数据
        if (_bufferedDataCount > 0) {
          final remainingData = _dataBuffer.takeBytes();
          _bufferedDataCount = 0;
          _processScrcpyData(remainingData);
        }
      },
    );
  }

  /// 处理 scrcpy 数据流
  void _processScrcpyData(Uint8List data) {
    if (data.isEmpty) {
      debugPrint('⚠️ 接收到空数据包');
      return;
    }

    debugPrint('🔄 处理数据块，大小: ${data.length} 字节');

    // 检查是否是视频元数据 (12字节)
    if (_isVideoMetadata(data)) {
      _metadataCount++;
      debugPrint('📋 视频元数据包 ($_metadataCount): ${data.length} 字节');
      _parseVideoMetadata(data);
      return;
    }

    // 检查是否是音频元数据 (4字节)
    if (_isAudioMetadata(data)) {
      _metadataCount++;
      debugPrint('📋 音频元数据包 ($_metadataCount): ${data.length} 字节');
      _parseAudioMetadata(data);
      return;
    }

    // 解析帧头
    if (data.length >= 12) {
      final frameHeader = _parseFrameHeader(data);
      if (frameHeader != null) {
        final frameData = data.sublist(12); // 跳过12字节帧头

        // 根据数据大小判断类型
        if (frameData.length > 1000) {
          // 大数据包很可能是视频帧
          _forwardToVideoClients(frameData);
          _videoFrameCount++;
          if (_videoFrameCount % 10 == 0) {
            debugPrint(
              '📹 视频帧: ${frameData.length} 字节, 关键帧: ${frameHeader.isKeyFrame} (第 $_videoFrameCount 帧)',
            );
          }
        } else if (frameData.length > 10) {
          // 中等大小数据包可能是音频帧
          _forwardToAudioClients(frameData);
          _audioFrameCount++;
          if (_audioFrameCount % 10 == 0) {
            debugPrint(
              '🎵 音频帧: ${frameData.length} 字节 (第 $_audioFrameCount 帧)',
            );
          }
        } else {
          // 小数据包，尝试转发给视频客户端
          _forwardToVideoClients(frameData);
          debugPrint('❓ 小数据帧: ${frameData.length} 字节');
        }
        return;
      }
    }

    // 如果无法解析为标准帧格式，根据大小转发数据
    if (data.length > 1000) {
      _forwardToVideoClients(data);
      _videoFrameCount++;
      if (_videoFrameCount % 10 == 0) {
        debugPrint('📹 原始大视频帧: ${data.length} 字节 (第 $_videoFrameCount 帧)');
      }
    } else if (data.length > 10) {
      _forwardToAudioClients(data);
      _audioFrameCount++;
      if (_audioFrameCount % 10 == 0) {
        debugPrint('🎵 原始中等音频帧: ${data.length} 字节 (第 $_audioFrameCount 帧)');
      }
    } else {
      debugPrint('❓ 无法识别的小数据包: ${data.length} 字节');
    }
  }

  /// 转发数据到视频客户端
  void _forwardToVideoClients(Uint8List data) {
    if (_videoClients.isEmpty) {
      debugPrint('⚠️ 没有视频客户端连接，丢弃数据');
      return;
    }

    final deadClients = <Socket>[];

    for (final client in _videoClients) {
      try {
        client.add(data);
        client.flush();
      } catch (e) {
        deadClients.add(client);
      }
    }

    // 移除断开的客户端
    for (final client in deadClients) {
      _videoClients.remove(client);
    }

    if (deadClients.isNotEmpty) {
      debugPrint('🗑️ 清理了 ${deadClients.length} 个断开的视频客户端');
    }
  }

  /// 转发数据到音频客户端
  void _forwardToAudioClients(Uint8List data) {
    if (_audioClients.isEmpty) {
      debugPrint('⚠️ 没有音频客户端连接，丢弃数据');
      return;
    }

    final deadClients = <Socket>[];

    for (final client in _audioClients) {
      try {
        client.add(data);
        client.flush();
      } catch (e) {
        deadClients.add(client);
      }
    }

    // 移除断开的客户端
    for (final client in deadClients) {
      _audioClients.remove(client);
    }

    if (deadClients.isNotEmpty) {
      debugPrint('🗑️ 清理了 ${deadClients.length} 个断开的音频客户端');
    }
  }

  /// 检查是否是视频元数据
  bool _isVideoMetadata(Uint8List data) {
    return data.length == 12 && _videoMetadata == null;
  }

  /// 检查是否是音频元数据
  bool _isAudioMetadata(Uint8List data) {
    return data.length == 4 && _audioMetadata == null;
  }

  /// 解析视频元数据
  void _parseVideoMetadata(Uint8List data) {
    if (data.length < 12) return;

    final codecId = _readUint32(data, 0);
    final width = _readUint32(data, 4);
    final height = _readUint32(data, 8);

    final codec = _parseVideoCodec(codecId);
    _videoMetadata = VideoMetadata(codec: codec, width: width, height: height);

    debugPrint('📹 视频元数据: 编解码器=$codec, 分辨率=${width}x$height');
  }

  /// 解析音频元数据
  void _parseAudioMetadata(Uint8List data) {
    if (data.length < 4) return;

    final codecId = _readUint32(data, 0);
    final codec = _parseAudioCodec(codecId);
    _audioMetadata = AudioMetadata(codec: codec);

    debugPrint('🎵 音频元数据: 编解码器=$codec');
  }

  /// 解析帧头
  FrameHeader? _parseFrameHeader(Uint8List data) {
    if (data.length < 12) {
      debugPrint('⚠️ 数据长度不足12字节，无法解析帧头: ${data.length} 字节');
      return null;
    }

    final first8Bytes = _readUint64(data, 0);
    final isConfigPacket = (first8Bytes & 0x8000000000000000) != 0;
    final isKeyFrame = (first8Bytes & 0x4000000000000000) != 0;
    final pts = first8Bytes & 0x3FFFFFFFFFFFFFFF;
    final packetSize = _readUint32(data, 8);

    debugPrint(
      '🔍 帧头解析: 配置包=$isConfigPacket, 关键帧=$isKeyFrame, PTS=$pts, 大小=$packetSize',
    );

    return FrameHeader(
      isConfigPacket: isConfigPacket,
      isKeyFrame: isKeyFrame,
      pts: pts,
      packetSize: packetSize,
    );
  }

  /// 检查是否是视频数据
  bool _isVideoData(Uint8List data) {
    return data.length > 1000 && _videoMetadata != null;
  }

  /// 检查是否是音频数据
  bool _isAudioData(Uint8List data) {
    return data.length > 10 && data.length < 1000 && _audioMetadata != null;
  }

  /// 解析视频编解码器
  VideoCodec _parseVideoCodec(int codecId) {
    switch (codecId) {
      case 1:
        return VideoCodec.h264;
      case 2:
        return VideoCodec.h265;
      case 3:
        return VideoCodec.av1;
      default:
        debugPrint('⚠️ 未知视频编解码器ID: $codecId，使用默认H.264');
        return VideoCodec.h264;
    }
  }

  /// 解析音频编解码器
  AudioCodec _parseAudioCodec(int codecId) {
    switch (codecId) {
      case 1:
        return AudioCodec.opus;
      case 2:
        return AudioCodec.aac;
      case 3:
        return AudioCodec.raw;
      default:
        debugPrint('⚠️ 未知音频编解码器ID: $codecId，使用默认Opus');
        return AudioCodec.opus;
    }
  }

  /// 读取Uint32
  int _readUint32(Uint8List data, int offset) {
    return (data[offset] & 0xff) |
        ((data[offset + 1] & 0xff) << 8) |
        ((data[offset + 2] & 0xff) << 16) |
        ((data[offset + 3] & 0xff) << 24);
  }

  /// 读取Uint64
  int _readUint64(Uint8List data, int offset) {
    final low = _readUint32(data, offset);
    final high = _readUint32(data, offset + 4);
    return (high << 32) | low;
  }

  Future<void> _pushScrcpyServer(AdbConnection connection) async {
    try {
      final serverFile = await _copyAssetToFile(_assetPath);
      await KadbDart.push(
        connection,
        serverFile.path,
        _serverPath,
        mode: _filePermissions,
      );
      debugPrint('✅ scrcpy-server推送成功');
    } catch (e) {
      debugPrint('❌ 推送scrcpy-server失败: $e');
      rethrow;
    }
  }

  Future<File> _copyAssetToFile(String assetPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = assetPath.split('/').last;
      final tempFile = File('${tempDir.path}/$fileName');

      final byteData = await rootBundle.load(assetPath);
      await tempFile.writeAsBytes(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
      );

      return tempFile;
    } catch (e) {
      debugPrint('❌ 复制资源文件失败: $e');
      rethrow;
    }
  }

  Future<void> _startScrcpyServer(AdbConnection connection) async {
    try {
      final shellCommand = _buildScrcpyCommand();
      debugPrint('🔧 Scrcpy命令: $shellCommand');

      final shellStream = await KadbDart.executeShell(
        connection,
        'sh',
        args: ['-c', shellCommand],
        debug: false,
      );

      await _handleScrcpyOutput(shellStream);
      debugPrint('✅ scrcpy服务器启动完成');
    } catch (e) {
      debugPrint('❌ 启动scrcpy服务器失败: $e');
      rethrow;
    }
  }

  String _buildScrcpyCommand() {
    return 'CLASSPATH=$_serverPath app_process / '
        'com.genymobile.scrcpy.Server 3.3.3 '
        'tunnel_forward=true '
        'audio=true '
        'control=false '
        'cleanup=false '
        'max_size=1080';
  }

  Future<void> _handleScrcpyOutput(AdbShellStream shellStream) async {
    bool serverReady = false;
    int lineCount = 0;

    try {
      await for (final line in shellStream.stdout) {
        lineCount++;
        debugPrint('📟 Scrcpy输出($lineCount): $line');

        if (!serverReady) {
          serverReady = true;
          debugPrint('✅ scrcpy服务器启动成功！');
          break;
        }

        if (_isErrorLine(line)) {
          throw Exception('Scrcpy服务器启动失败: $line');
        }
      }

      if (!serverReady) {
        throw Exception('未能确认scrcpy服务器成功启动');
      }
    } catch (e) {
      debugPrint('❌ 处理scrcpy输出失败: $e');
      rethrow;
    }
  }

  bool _isErrorLine(String line) {
    return line.contains('ERROR') ||
        line.contains('Exception') ||
        line.contains('FATAL');
  }

  Future<void> _cleanupOnFailure() async {
    try {
      await _directConnection?.disconnect();
      await _server?.close();
    } catch (e) {
      debugPrint('❌ 清理资源时出错: $e');
    } finally {
      _directConnection = null;
      _server = null;
    }
  }

  void _updateStatus(String status, {bool? isStarting, bool? isStreaming}) {
    _streamStatus = status;
    if (isStarting != null) _isStarting = isStarting;
    if (isStreaming != null) _isStreaming = isStreaming;
    notifyListeners();
  }

  Future<void> stopStream() async {
    try {
      await _directConnection?.disconnect();
      await _server?.close();

      // 关闭所有客户端连接
      for (final client in _videoClients) {
        await client.close();
      }
      for (final client in _audioClients) {
        await client.close();
      }
    } catch (e) {
      debugPrint('停止流时出错: $e');
    } finally {
      _resetState();
    }
  }

  void _resetState() {
    _directConnection = null;
    _server = null;
    _isStreaming = false;
    _streamStatus = '已停止';
    _videoPort = 0;
    _audioPort = 0;
    _videoClients.clear();
    _audioClients.clear();
    _videoMetadata = null;
    _audioMetadata = null;
    _dataCount = 0;
    _videoFrameCount = 0;
    _audioFrameCount = 0;
    _metadataCount = 0;
    _bufferedDataCount = 0;
    _dataBuffer.clear();
    notifyListeners();
  }
}
