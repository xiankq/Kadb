import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kadb_dart/kadb_dart.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化MediaKit，配置允许加载不安全的URL
  MediaKit.ensureInitialized();

  runApp(const ScrcpyApp());
}

class ScrcpyApp extends StatelessWidget {
  const ScrcpyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Scrcpy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ConnectionPage(),
    );
  }
}

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  bool _isConnecting = false;
  String _statusMessage = '请输入设备IP和端口';

  @override
  void initState() {
    super.initState();
    _ipController.text = '192.168.2.32'; // 默认IP
    _portController.text = '5556'; // 默认端口
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  /// 从assets复制文件到临时目录
  Future<File> _copyAssetToFile(String assetPath) async {
    try {
      // 获取应用的临时目录
      final tempDir = await getTemporaryDirectory();
      final fileName = assetPath.split('/').last;
      final tempFile = File('${tempDir.path}/$fileName');

      // 从assets加载数据
      final byteData = await rootBundle.load(assetPath);
      final buffer = byteData.buffer;

      // 写入临时文件
      await tempFile.writeAsBytes(
        buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      );

      return tempFile;
    } catch (e) {
      throw Exception('无法从assets加载scrcpy-server文件: $e');
    }
  }

  Future<void> _connectToDevice() async {
    setState(() {
      _isConnecting = true;
      _statusMessage = '正在连接设备...';
    });

    try {
      // 创建ADB连接
      final applicationDocumentsDir = await getApplicationDocumentsDirectory();
      final cacheDir = '${applicationDocumentsDir.path}/kadb_cache';
      final keyPair = await CertUtils.loadKeyPair(cacheDir: cacheDir);
      final connection = await KadbDart.create(
        host: _ipController.text.trim(),
        port: int.parse(_portController.text.trim()),
        keyPair: keyPair,
        debug: false,
        ioTimeoutMs: 30000,
        connectTimeoutMs: 15000,
      );

      setState(() {
        _statusMessage = '设备连接成功！正在推送scrcpy-server...';
      });

      // 从assets中复制scrcpy-server到临时目录
      final serverFile = await _copyAssetToFile('assets/scrcpy-server');

      // 推送scrcpy-server到设备
      await KadbDart.push(
        connection,
        serverFile.path,
        '/data/local/tmp/scrcpy-server.jar',
        mode: 33261,
      );

      setState(() {
        _statusMessage = 'scrcpy-server已推送，启动转发...';
      });

      // 启动TCP转发
      final tcpPort = 11238; // 视频流端口
      final forwarder = TcpForwarder(
        connection,
        tcpPort,
        'localabstract:scrcpy',
        debug: false,
      );
      await forwarder.start();

      setState(() {
        _statusMessage = 'TCP转发已启动，启动scrcpy服务器...';
      });

      // 启动scrcpy服务器 - 优化视频流参数
      final shellCommand =
          'CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server 3.3.3 '
          'tunnel_forward=true audio=false control=false cleanup=false '
          'max_size=720 display_id=0 video_codec=h264 video_bit_rate=2000000 video_frame_rate=30';
      // 启动scrcpy服务器并保持运行
      print('正在启动scrcpy服务器...');
      print('Scrcpy命令: $shellCommand');

      final shellProcess = await KadbDart.executeShell(connection, 'sh', [
        '-c',
        '$shellCommand &',
      ]);

      print('scrcpy服务器已启动，流句柄: ${shellProcess.hashCode}');
      print('检查scrcpy服务器是否正在运行...');

      // 等待服务器启动
      print('等待scrcpy服务器启动...');
      await Future.delayed(const Duration(seconds: 3));

      // 检查scrcpy服务器进程是否在运行
      print('检查scrcpy服务器进程状态...');
      try {
        final psResult = await KadbDart.executeShell(connection, 'ps');
        print('设备进程列表:');
        print(psResult);
      } catch (e) {
        print('无法获取进程列表: $e');
      }

      // 检查是否有scrcpy相关进程
      try {
        final psScrcpy = await KadbDart.executeShell(connection, 'ps | grep scrcpy');
        print('Scrcpy相关进程:');
        print(psScrcpy);
      } catch (e) {
        print('未找到scrcpy进程: $e');
      }

      // 测试TCP端口是否可连接并读取一些数据
      print('测试TCP端口连接和数据流...');
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          tcpPort,
          timeout: const Duration(seconds: 2),
        );
        print('TCP端口 $tcpPort 连接成功');

        // 尝试读取一些数据来确认流已经存在
        int totalBytes = 0;
        try {
          await for (final data in socket) {
            totalBytes += data.length;
            print('接收到 ${data.length} 字节，总计 ${totalBytes} 字节');

            // 检查数据头部是否包含H.264或视频流标识
            if (totalBytes >= 4) {
              final firstBytes = data.take(4).toList();
              print('前4字节数据: $firstBytes');

              // H.264 NALU通常以0x00000001或0x000001开始
              if (firstBytes.length >= 4) {
                if ((firstBytes[0] == 0 && firstBytes[1] == 0 && firstBytes[2] == 0 && firstBytes[3] == 1) ||
                    (firstBytes[0] == 0 && firstBytes[1] == 0 && firstBytes[2] == 1)) {
                  print('✅ 检测到H.264 NALU起始码');
                }
              }
            }

            // 读取前几KB数据就停止，避免阻塞
            if (totalBytes > 2048) {
              print('数据流确认存在，停止读取');
              break;
            }
          }
          print('成功读取到 $totalBytes 字节的视频数据');
        } catch (e) {
          print('读取数据时出错: $e');
        }

        socket.close();
        print('TCP端口测试完成');
      } catch (e) {
        print('TCP端口 $tcpPort 连接失败: $e');
        throw Exception('无法连接到视频流端口');
      }

      // 导航到视频播放页面
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoStreamPage(
            tcpPort: tcpPort,
            forwarder: forwarder,
            connection: connection,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _statusMessage = '连接失败: $e';
        _isConnecting = false;
      });
      print('连接错误: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Scrcpy'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Scrcpy连接设置',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: '设备IP地址',
                border: OutlineInputBorder(),
                hintText: '例如: 192.168.2.32',
              ),
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: '端口',
                border: OutlineInputBorder(),
                hintText: '例如: 5556',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isConnecting ? null : _connectToDevice,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                textStyle: const TextStyle(fontSize: 16),
              ),
              child: _isConnecting
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('连接中...'),
                      ],
                    )
                  : const Text('连接设备'),
            ),
            const SizedBox(height: 24),
            Text(
              _statusMessage,
              style: TextStyle(
                fontSize: 14,
                color: _statusMessage.contains('失败') ? Colors.red : Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class VideoStreamPage extends StatefulWidget {
  final int tcpPort;
  final TcpForwarder forwarder;
  final AdbConnection connection;

  const VideoStreamPage({
    super.key,
    required this.tcpPort,
    required this.forwarder,
    required this.connection,
  });

  @override
  State<VideoStreamPage> createState() => _VideoStreamPageState();
}

class _VideoStreamPageState extends State<VideoStreamPage> {
  late final Player _player;
  late final VideoController _videoController;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();

    // 创建播放器，尝试不同的配置
    _player = Player();
    _videoController = VideoController(_player);

    // 添加状态监听
    _player.stream.error.listen((error) {
      print('播放器错误: $error');
    });

    _player.stream.buffering.listen((buffering) {
      print('缓冲状态: $buffering');
    });

    _player.stream.playing.listen((playing) {
      print('播放状态: $playing');
    });

    // 异步启动播放器
    _startPlayer();
  }

  Future<void> _startPlayer() async {
    // 尝试多种不同的播放器配置
    final urls = [
      'tcp://127.0.0.1:${widget.tcpPort}',
      'tcp://localhost:${widget.tcpPort}',
      'fd://0', // 尝试从标准输入读取
    ];

    for (int i = 0; i < urls.length; i++) {
      final url = urls[i];
      print('尝试播放器方法 ${i + 1}: $url');

      try {
        final media = Media(url);
        print('Media对象创建成功');

        // 使用不同的播放选项
        if (i == 0) {
          await _player.open(media, play: true);
        } else if (i == 1) {
          await _player.open(media, play: false);
          await Future.delayed(const Duration(milliseconds: 500));
          await _player.play();
        } else {
          await _player.open(media);
          await _player.play();
        }

        setState(() {
          _isPlaying = true;
        });

        print('播放器方法 ${i + 1} 启动成功，正在播放TCP流');

        // 监听播放状态
        _player.stream.playing.listen((playing) {
          print('播放状态变化: $playing');
          if (!playing && _isPlaying) {
            print('播放意外停止，尝试重新连接...');
            Future.delayed(const Duration(seconds: 1), () {
              _reconnect();
            });
          }
        });

        return; // 成功则退出循环
      } catch (e) {
        print('播放器方法 ${i + 1} 失败: $e');
        if (i == urls.length - 1) {
          print('所有播放器方法都失败了');
          tryAlternativePlayback();
        }
      }
    }
  }

  Future<void> _reconnect() async {
    try {
      await _player.open(
        Media('tcp://127.0.0.1:${widget.tcpPort}'),
        play: true,
      );
      print('重新连接成功');
    } catch (e) {
      print('重新连接失败: $e');
    }
  }

  Future<void> tryAlternativePlayback() async {
    // 方法1: 直接延迟重试
    try {
      print('替代播放方法1: 延迟重试');
      await Future.delayed(const Duration(seconds: 2));

      final media = Media('tcp://127.0.0.1:${widget.tcpPort}');
      await _player.open(media);

      setState(() {
        _isPlaying = true;
      });

      print('替代播放方式1成功');
      return;
    } catch (e) {
      print('替代播放方式1失败: $e');
    }

    // 方法2: 尝试不同的端口格式
    try {
      print('替代播放方法2: 使用IPV6格式');
      final media = Media('tcp://[::1]:${widget.tcpPort}');
      await _player.open(media);

      setState(() {
        _isPlaying = true;
      });

      print('替代播放方式2成功');
    } catch (e) {
      print('替代播放方式2失败: $e');
    }

    // 方法3: 如果所有方法都失败，显示错误信息
    print('所有播放器方法都失败了，可能需要检查视频流格式');
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频流'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () {
              if (_isPlaying) {
                _player.pause();
              } else {
                _player.play();
              }
              setState(() {
                _isPlaying = !_isPlaying;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            onPressed: () async {
              // 清理资源并返回
              try {
                _player.stop();
                await widget.forwarder.stop();
                widget.connection.close();
              } catch (e) {
                print('清理资源时出错: $e');
              }
              if (mounted) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Video(controller: _videoController),
        ),
      ),
    );
  }
}
