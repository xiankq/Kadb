import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:kadb_dart/kadb_dart.dart';

/// scrcpy流解析器 - 统计流数据而不解码
class ScrcpyStreamParser {
  static const int PACKET_HEADER_SIZE = 12; // 8字节时间戳 + 4字节大小
  static const int VIDEO_HEADER_SIZE = 12; // 4字节编码器ID + 4字节宽 + 4字节高
  static const int AUDIO_HEADER_SIZE = 4; // 4字节编码器ID

  // 统计数据结构
  final Map<String, StreamStats> _stats = {
    'video': StreamStats(),
    'audio': StreamStats(),
    'control': StreamStats(),
  };

  Timer? _reportTimer;

  // 流类型检测状态
  final Map<String, bool> _headerReceived = {'video': false, 'audio': false};

  /// 解析视频头信息
  void parseVideoHeader(Uint8List data) {
    if (data.length < VIDEO_HEADER_SIZE) return;

    try {
      final header = ByteData.view(data.buffer);
      
      // 尝试两种字节序
      final codecIdLittle = header.getUint32(0, Endian.little);
      final widthLittle = header.getUint32(4, Endian.little);
      final heightLittle = header.getUint32(8, Endian.little);
      
      final codecIdBig = header.getUint32(0, Endian.big);
      final widthBig = header.getUint32(4, Endian.big);
      final heightBig = header.getUint32(8, Endian.big);

      // 选择有效的解析结果
      int codecId;
      int width;
      int height;
      
      if (widthLittle > 0 && heightLittle > 0 && widthLittle < 10000 && heightLittle < 10000) {
        codecId = codecIdLittle;
        width = widthLittle;
        height = heightLittle;
      } else if (widthBig > 0 && heightBig > 0 && widthBig < 10000 && heightBig < 10000) {
        codecId = codecIdBig;
        width = widthBig;
        height = heightBig;
      } else {
        print('⚠️ 无法解析有效的分辨率');
        return;
      }

      // 根据scrcpy文档，codecId是32位无符号整数，需要转换为对应的解码器名称
      String codecName;
      switch (codecId) {
        case 0x68323634: // 'h264' in ASCII
          codecName = 'H264';
          break;
        case 0x68323635: // 'h265' in ASCII
          codecName = 'H265';
          break;
        case 0x61763031: // 'av01' in ASCII 
          codecName = 'AV1';
          break;
        default:
          // 尝试解析为ASCII字符串
          final codecBytes = Uint8List(4);
          final codecData = ByteData.view(codecBytes.buffer);
          codecData.setUint32(0, codecId, Endian.little);
          codecName = String.fromCharCodes(codecBytes).trim();
          if (codecName.isEmpty || codecName.codeUnits.any((c) => c < 32 || c > 126)) {
            codecName = '0x${codecId.toRadixString(16).toUpperCase()}';
          }
      }

      // 调试信息：显示解析结果
      print('📺 检测到视频头: ${width}x$height, 解码器: $codecName');

      // 检查是否是有效的分辨率
      if (width > 0 && height > 0 && width < 10000 && height < 10000) {
        _stats['video']!.resolution = '${width}x$height';
        _stats['video']!.codec = codecName;
        _headerReceived['video'] = true;
      } else {
        print('⚠️ 无效的分辨率: ${width}x$height');
      }
    } catch (e) {
      print('⚠️ 解析视频头信息时出错: $e');
    }
  }

  /// 解析音频头信息
  void parseAudioHeader(Uint8List data) {
    if (data.length < AUDIO_HEADER_SIZE) return;

    try {
      final codecId = ByteData.view(data.buffer).getUint32(0, Endian.little);

      if (codecId != 0) {
        // 根据scrcpy文档，音频解码器ID也是32位无符号整数
        String codecName;
        switch (codecId) {
          case 0x6f707573: // 'opus' in ASCII
            codecName = 'OPUS';
            break;
          case 0x00000000: // AAC
            codecName = 'AAC';
            break;
          case 0x00000001: // RAW
            codecName = 'RAW';
            break;
          default:
            // 尝试解析为ASCII字符串
            final codecBytes = Uint8List(4);
            final codecData = ByteData.view(codecBytes.buffer);
            codecData.setUint32(0, codecId, Endian.little);
            codecName = String.fromCharCodes(codecBytes).trim();
            if (codecName.isEmpty ||
                codecName.codeUnits.any((c) => c < 32 || c > 126)) {
              codecName = '0x${codecId.toRadixString(16).toUpperCase()}';
            }
        }

        _stats['audio']!.codec = codecName;
        _headerReceived['audio'] = true;
        print('🎵 检测到音频头: 解码器: ${_stats['audio']!.codec}');
      }
    } catch (e) {
      print('⚠️ 解析音频头信息时出错: $e');
    }
  }

  /// 尝试从数据包中识别解码器
  void tryDetectCodec(String streamType, Uint8List data) {
    final stats = _stats[streamType]!;

    // 如果已经识别到解码器，不再重复识别
    if (stats.codec.isNotEmpty && stats.codec != '未识别') return;

    if (data.length >= 4) {
      // 检查是否是有效的ASCII字符（可打印字符）
      final codecBytes = data.sublist(0, 4);
      final isPrintable = codecBytes.every((byte) => byte >= 32 && byte <= 126);

      if (isPrintable) {
        // 如果是可打印字符，解析为字符串
        final codecString = String.fromCharCodes(codecBytes);
        final cleanCodec = codecString.trim();

        if (cleanCodec.isNotEmpty) {
          stats.codec = cleanCodec;
          print('🔍 识别到$streamType流解码器: $cleanCodec');
        }
      } else {
        // 如果不是可打印字符，可能是二进制数据，解析为十六进制
        final codecId = ByteData.view(data.buffer).getUint32(0, Endian.little);
        if (codecId != 0) {
          stats.codec = '0x${codecId.toRadixString(16).toUpperCase()}';
          print('🔍 识别到$streamType流解码器ID: ${stats.codec}');
        }
      }
    }
  }

  /// 解析数据包
  void parsePacket(String streamType, Uint8List data) {
    String actualStreamType = streamType;

    // 检查是否是帧元数据（12字节，包含时间戳、标志位和包大小）
    // 只在已经收到头信息后才处理帧元数据
    if (data.length == PACKET_HEADER_SIZE && _headerReceived[streamType]!) {
      try {
        final ptsAndFlags = ByteData.view(data.buffer).getUint64(0, Endian.little);
        final packetSize = ByteData.view(data.buffer).getUint32(8, Endian.little);
        
        // 检查是否是有效的包元数据（包大小应该合理）
        if (packetSize > 0 && packetSize < 10 * 1024 * 1024) { // 小于10MB
          // 检查是否是配置包或关键帧
          final isConfig = (ptsAndFlags & (1 << 63)) != 0;
          final isKeyFrame = (ptsAndFlags & (1 << 62)) != 0;
          
          if (isConfig) {
            _stats[actualStreamType]!.configPackets++;
          }
          if (isKeyFrame) {
            _stats[actualStreamType]!.keyFrames++;
          }
          
          // 这是包元数据，不进行常规统计
          return;
        }
      } catch (e) {
        // 不是有效的包元数据，继续处理
      }
    }

    // 首先检查是否是设备元数据（通常是设备名称，以null结尾的字符串）
    if (!_headerReceived[streamType]! && data.isNotEmpty) {
      // 检查数据是否看起来像UTF-8字符串（设备元数据）
      final isLikelyDeviceName = data
          .take(64)
          .every((byte) => byte >= 32 && byte <= 126 || byte == 0);
      if (isLikelyDeviceName) {
        try {
          final deviceName = String.fromCharCodes(
            data.takeWhile((byte) => byte != 0),
          );
          if (deviceName.isNotEmpty) {
            print('📱 设备元数据: "$deviceName" (${data.length}字节)');
            // 设备元数据后应该是代码元数据，继续处理下一个数据包
            return;
          }
        } catch (e) {
          // 忽略解析错误，继续处理
        }
      }
    }

    // 首先检查是否是视频头信息（12字节，包含分辨率）
    if (data.length == VIDEO_HEADER_SIZE && !_headerReceived['video']!) {
      try {
        final header = ByteData.view(data.buffer);
        final codecId = header.getUint32(0, Endian.little);
        final width = header.getUint32(4, Endian.little);
        final height = header.getUint32(8, Endian.little);

        // 检查是否是有效的分辨率和解码器ID
        final isValidResolution = width > 0 && height > 0 && width < 10000 && height < 10000;
        final isValidCodec = codecId == 0x68323634 || codecId == 0x68323635 || codecId == 0x61763031;

        if (isValidResolution && isValidCodec) {
          // 这是视频头信息，强制设置为视频流
          actualStreamType = 'video';
          parseVideoHeader(data);
          return;
        }
      } catch (e) {
        // 不是有效的视频头，继续处理
      }
    }

    // 检查是否是音频头信息（4字节）
    if (data.length == AUDIO_HEADER_SIZE && !_headerReceived['audio']!) {
      try {
        final header = ByteData.view(data.buffer);
        final codecId = header.getUint32(0, Endian.little);

        // 检查是否是有效的音频解码器ID
        final isValidCodec =
            codecId == 0x6f707573 ||
            codecId == 0x00000000 ||
            codecId == 0x00000001; // opus, AAC, RAW

        if (isValidCodec) {
          // 这是音频头信息，强制设置为音频流
          actualStreamType = 'audio';
          parseAudioHeader(data);
          return;
        }
      } catch (e) {
        // 不是有效的音频头，继续处理
      }
    }

    // 获取正确的统计对象
    final stats = _stats[actualStreamType]!;

    // 如果还没有收到头信息，尝试从数据包中检测
    if (!_headerReceived[actualStreamType]! && data.length >= 4) {
      tryDetectCodec(actualStreamType, data);
    }

    // 统计数据包（排除头信息包）
    if (data.length != VIDEO_HEADER_SIZE && data.length != AUDIO_HEADER_SIZE) {
      stats.packetCount++;
      stats.totalBytes += data.length;
      stats.updateStats(data.length);

      // 检查是否是帧头（12字节的包元数据）
      if (data.length == PACKET_HEADER_SIZE) {
        final ptsAndFlags = ByteData.view(
          data.buffer,
        ).getUint64(0, Endian.little);
        final packetSize = ByteData.view(
          data.buffer,
        ).getUint32(8, Endian.little);

        final isConfig = (ptsAndFlags & (1 << 63)) != 0;
        final isKeyFrame = (ptsAndFlags & (1 << 62)) != 0;

        if (isConfig) stats.configPackets++;
        if (isKeyFrame) stats.keyFrames++;
      }
    }
  }

  /// 开始统计报告
  void startReporting() {
    _reportTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      _printStats();
      _resetStats();
    });
  }

  /// 打印统计信息
  void _printStats() {
    print('\n📊 5秒统计报告:');
    print('─' * 60);

    _stats.forEach((type, stats) {
      if (stats.packetCount > 0) {
        stats.calculateRates();

        final totalSpeedKB = (stats.totalBytes / 1024).toStringAsFixed(1);
        final avgSpeedKB = (stats.bytesPerSecond / 1024).toStringAsFixed(1);
        final avgPacketSizeKB = (stats.averagePacketSize / 1024)
            .toStringAsFixed(2);

        // 计算码率（kbps）
        final bitrateKbps = (stats.bytesPerSecond * 8 / 1000).toStringAsFixed(
          1,
        );

        print('🎯 $type流统计:');
        print(
          '   📦 包数量: ${stats.packetCount}包 (${stats.packetsPerSecond.toStringAsFixed(1)}包/秒)',
        );
        print('   💾 总数据: ${stats.totalBytes}字节 (${totalSpeedKB}KB)');
        print('   🚀 平均速率: ${avgSpeedKB}KB/s');
        print('   📡 码率: ${bitrateKbps}kbps');
        print('   📏 平均包大小: ${avgPacketSizeKB}KB');

        // 强制打印解码器信息
        print('   🔧 解码器: ${stats.codec.isNotEmpty ? stats.codec : "未识别"}');

        // 分辨率信息
        if (stats.resolution.isNotEmpty) {
          print('   📺 分辨率: ${stats.resolution}');

          // 如果是视频流，计算像素总数
          if (type == 'video' && stats.resolution.contains('x')) {
            final parts = stats.resolution.split('x');
            if (parts.length == 2) {
              try {
                final width = int.parse(parts[0]);
                final height = int.parse(parts[1]);
                final totalPixels = width * height;
                print(
                  '   🖼️  总像素: ${totalPixels.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                );
              } catch (e) {
                // 忽略解析错误
              }
            }
          }
        }

        // 帧信息
        if (stats.keyFrames > 0) {
          print('   🔑 关键帧: ${stats.keyFrames}');
          final keyFrameRate = (stats.keyFrames / 5.0).toStringAsFixed(
            1,
          ); // 5秒内的关键帧率
          print('   📊 关键帧率: $keyFrameRate帧/秒');
        }

        if (stats.configPackets > 0) {
          print('   ⚙️  配置包: ${stats.configPackets}');
        }

        print('');
      }
    });

    // 汇总信息
    final totalPackets = _stats.values
        .map((s) => s.packetCount)
        .reduce((a, b) => a + b);
    final totalBytes = _stats.values
        .map((s) => s.totalBytes)
        .reduce((a, b) => a + b);
    final totalSpeedKB = (totalBytes / 1024).toStringAsFixed(1);
    final totalBitrateKbps = (totalBytes * 8 / 5000).toStringAsFixed(
      1,
    ); // 5秒总码率

    print('📈 汇总统计:');
    print('   总包数: $totalPackets包');
    print('   总数据: $totalBytes字节 (${totalSpeedKB}KB)');
    print('   总码率: ${totalBitrateKbps}kbps');
    print('─' * 60);
  }

  /// 重置统计
  void _resetStats() {
    _stats.forEach((_, stats) => stats.reset());
  }

  /// 停止报告
  void stop() {
    _reportTimer?.cancel();
    _printStats(); // 最终报告
  }
}

/// 流统计数据结构
class StreamStats {
  int packetCount = 0;
  int totalBytes = 0;
  int configPackets = 0;
  int keyFrames = 0;
  String codec = '';
  String resolution = '';

  // 新增统计字段
  int lastPacketCount = 0;
  int lastTotalBytes = 0;
  double averagePacketSize = 0.0;
  double packetsPerSecond = 0.0;
  double bytesPerSecond = 0.0;
  DateTime? lastReportTime;
  DateTime? startTime;

  // 包大小分布
  final Map<String, int> packetSizeDistribution = {
    '0-100B': 0,
    '100B-1KB': 0,
    '1KB-10KB': 0,
    '10KB-100KB': 0,
    '100KB+': 0,
  };

  void reset() {
    lastPacketCount = packetCount;
    lastTotalBytes = totalBytes;

    packetCount = 0;
    totalBytes = 0;
    configPackets = 0;
    keyFrames = 0;

    // 重置包大小分布
    packetSizeDistribution.forEach((key, value) {
      packetSizeDistribution[key] = 0;
    });

    // 保持codec和resolution不变
  }

  /// 更新统计信息
  void updateStats(int packetSize) {
    // 更新包大小分布
    if (packetSize <= 100) {
      packetSizeDistribution['0-100B'] = packetSizeDistribution['0-100B']! + 1;
    } else if (packetSize <= 1024) {
      packetSizeDistribution['100B-1KB'] =
          packetSizeDistribution['100B-1KB']! + 1;
    } else if (packetSize <= 10240) {
      packetSizeDistribution['1KB-10KB'] =
          packetSizeDistribution['1KB-10KB']! + 1;
    } else if (packetSize <= 102400) {
      packetSizeDistribution['10KB-100KB'] =
          packetSizeDistribution['10KB-100KB']! + 1;
    } else {
      packetSizeDistribution['100KB+'] = packetSizeDistribution['100KB+']! + 1;
    }

    // 计算平均值
    if (packetCount > 0) {
      averagePacketSize = totalBytes / packetCount;
    }
  }

  /// 计算速率
  void calculateRates() {
    final now = DateTime.now();

    if (lastReportTime != null) {
      final elapsedSeconds =
          now.difference(lastReportTime!).inMilliseconds / 1000.0;
      if (elapsedSeconds > 0) {
        final packetDiff = packetCount - lastPacketCount;
        final byteDiff = totalBytes - lastTotalBytes;

        // 确保速率不为负数
        packetsPerSecond = packetDiff >= 0 ? packetDiff / elapsedSeconds : 0.0;
        bytesPerSecond = byteDiff >= 0 ? byteDiff / elapsedSeconds : 0.0;
      }
    } else {
      // 第一次计算，使用真实的时间间隔
      if (startTime != null) {
        final elapsedSeconds =
            now.difference(startTime!).inMilliseconds / 1000.0;
        if (elapsedSeconds > 0) {
          packetsPerSecond = packetCount / elapsedSeconds;
          bytesPerSecond = totalBytes / elapsedSeconds;
        } else {
          packetsPerSecond = 0.0;
          bytesPerSecond = 0.0;
        }
      } else {
        packetsPerSecond = 0.0;
        bytesPerSecond = 0.0;
      }
    }

    lastReportTime = now;
  }
}

void main() async {
  print('🚀 启动scrcpy流解析示例...');

  AdbConnection? connection;
  TcpForwarder? forwarder;
  final List<Socket> sockets = [];
  ScrcpyStreamParser? parser;

  try {
    // 1. 连接设备
    print('📱 连接到设备 192.168.2.148:5555...');
    final keyPair = await CertUtils.loadKeyPair();
    connection = await KadbDart.create(
      host: '192.168.2.148',
      port: 5555,
      keyPair: keyPair,
      debug: false,
    );
    print('✅ 设备连接成功');

    // 2. 检查并推送scrcpy-server
    print('📤 检查并推送scrcpy-server到设备...');
    final scrcpyServerFile = File('assets/scrcpy-server');
    if (!await scrcpyServerFile.exists()) {
      print('❌ scrcpy-server文件不存在，请确保assets/scrcpy-server文件存在');
      return;
    }

    await KadbDart.push(
      connection,
      'assets/scrcpy-server',
      '/data/local/tmp/scrcpy-server.jar',
      mode: 33261,
    );
    print('✅ scrcpy-server已推送');

    // 3. 启动TCP转发
    final port = 12345;
    print('🔌 启动TCP转发: 端口 $port -> localabstract:scrcpy');

    forwarder = TcpForwarder(
      connection,
      port,
      'localabstract:scrcpy',
      debug: false,
    );
    await forwarder.start();
    print('✅ TCP转发已启动');

    // 4. 启动scrcpy-server进程
    print('🔧 启动scrcpy-server进程...');

    // 5. 启动scrcpy-server进程
    print('🔧 启动scrcpy-server进程...');

    final shellCommand =
        'CLASSPATH=/data/local/tmp/scrcpy-server.jar '
        'app_process / com.genymobile.scrcpy.Server 3.3.3 '
        'tunnel_forward=true audio=true control=true cleanup=false max_size=720 send_codec_meta=true send_frame_meta=true log_level=debug';

    final shellStream = await KadbDart.executeShell(
      connection,
      'sh',
      args: ['-c', shellCommand],
    );

    // 等待服务器启动和连接
    print('⏳ 等待scrcpy-server启动并连接到隧道...');
    await Future.delayed(Duration(seconds: 3));

    // 5. 创建3个本地Socket连接
    print('🎯 创建3个本地Socket连接（视频、音频、控制）...');

    parser = ScrcpyStreamParser();

    // 创建连接并处理数据流
    for (int i = 0; i < 3; i++) {
      final streamTypes = ['video', 'audio', 'control'];
      final streamType = streamTypes[i];

      try {
        final socket = await Socket.connect(
          'localhost',
          port,
        ).timeout(Duration(seconds: 10));
        sockets.add(socket);

        print('✅ $streamType流连接已建立');

        // 监听数据流
        socket.listen(
          (data) {
            parser!.parsePacket(streamType, Uint8List.fromList(data));
          },
          onError: (error) {
            print('❌ $streamType流错误: $error');
          },
          onDone: () {
            print('📴 $streamType流连接已关闭');
          },
        );
      } catch (e) {
        print('❌ 无法建立$streamType流连接: $e');
      }
    }

    // 检查是否成功建立了连接
    if (sockets.isEmpty) {
      print('❌ 无法建立任何流连接，请检查scrcpy-server是否正常运行');
      return;
    }

    // 监听shell输出
    shellStream.stdout.listen((output) {
      if (output.trim().isNotEmpty) {
        print('📝 scrcpy-server: $output');
      }
    });

    shellStream.stderr.listen((error) {
      if (error.trim().isNotEmpty) {
        print('❌ scrcpy-server错误: $error');
      }
    });

    print('✅ scrcpy-server进程已启动，等待数据流...');

    // 6. 启动统计报告
    parser.startReporting();
    print('📈 统计报告已启动（每5秒输出一次）');

    // 7. 保持运行
    print('\n⏳ 解析器持续运行中，按Ctrl+C停止...\n');

    // 使用Completer来保持程序运行
    final completer = Completer<void>();

    // 监听Ctrl+C信号
    ProcessSignal.sigint.watch().listen((signal) {
      print('\n🛑 收到停止信号，正在清理资源...');
      completer.complete();
    });

    // 等待程序被手动停止
    await completer.future;
  } catch (e) {
    print('❌ 错误: $e');
    print('\n💡 可能的原因:');
    print('   - 设备未连接或IP地址错误');
    print('   - 设备未开启USB调试');
    print('   - 网络连接问题');
    print('   - scrcpy-server文件不存在');
  } finally {
    print('\n🛑 正在清理资源...');

    // 停止解析器
    parser?.stop();

    // 关闭所有Socket连接
    for (final socket in sockets) {
      try {
        await socket.close();
      } catch (e) {
        print('⚠️ 关闭Socket时出错: $e');
      }
    }

    // 关闭转发器
    try {
      await forwarder?.stop();
    } catch (e) {
      print('⚠️ 关闭转发器时出错: $e');
    }

    // 关闭连接
    try {
      await connection?.close();
    } catch (e) {
      print('⚠️ 关闭连接时出错: $e');
    }

    print('✅ 清理完成');
  }
}
