import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../connection_provider.dart';
import '../stream_provider.dart';
import 'connection_screen.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final Player _player;
  late final VideoController _videoController;
  bool _isPlayerReady = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    // 创建播放器，配置允许加载不安全的URL
    _player = Player(
      configuration: PlayerConfiguration(
        title: "Scrcpy Video Stream",
      ),
    );
    _videoController = VideoController(_player);

    // 尝试设置播放器选项以允许不安全的URL
    try {
      // 这些是media_kit的全局选项，需要在初始化时设置
      debugPrint('播放器配置完成');
    } catch (e) {
      debugPrint('播放器配置失败: $e');
    }

    // 监听播放器状态
    _player.stream.error.listen((error) {
      debugPrint('播放器错误: $error');
    });

    _player.stream.buffering.listen((buffering) {
      debugPrint('缓冲状态: $buffering');
    });

    _player.stream.playing.listen((playing) {
      debugPrint('播放状态: $playing');
    });

    setState(() {
      _isPlayerReady = true;
    });

    // 延迟启动播放，确保TCP端口准备就绪
    await _startVideoPlayback();
  }

  Future<void> _startVideoPlayback() async {
    if (!mounted) return;

    final streamProvider = context.read<VideoStreamProvider>();
    if (!streamProvider.isStreaming || streamProvider.tcpPort == 0) {
      debugPrint('视频流未准备好');
      return;
    }

    final tcpPort = streamProvider.tcpPort;

    // 尝试多种URL格式和方法
    final attempts = [
      // 方法1: 标准TCP URL
      () async {
        debugPrint('尝试标准TCP URL: tcp://127.0.0.1:$tcpPort');
        final media = Media('tcp://127.0.0.1:$tcpPort');
        await _player.open(media, play: true);
      },

      // 方法2: 先打开后播放
      () async {
        debugPrint('尝试先打开后播放: tcp://127.0.0.1:$tcpPort');
        final media = Media('tcp://127.0.0.1:$tcpPort');
        await _player.open(media, play: false);
        await Future.delayed(const Duration(milliseconds: 500));
        await _player.play();
      },

      // 方法3: 使用localhost
      () async {
        debugPrint('尝试localhost: tcp://localhost:$tcpPort');
        final media = Media('tcp://localhost:$tcpPort');
        await _player.open(media, play: true);
      },
    ];

    for (int i = 0; i < attempts.length; i++) {
      try {
        await attempts[i]();
        debugPrint('播放器方法 ${i + 1} 启动成功');
        return;
      } catch (e) {
        debugPrint('播放器方法 ${i + 1} 失败: $e');
        if (i < attempts.length - 1) {
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      }
    }

    debugPrint('所有播放尝试都失败了，显示错误信息');
    _showPlaybackError();
  }

  void _showPlaybackError() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('视频播放失败，TCP流可能需要特殊配置'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '重试',
          onPressed: () {
            _startVideoPlayback();
          },
        ),
      ),
    );
  }

  Future<void> _disconnect() async {
    // 停止播放器
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('停止播放器失败: $e');
    }

    if (!mounted) return;

    // 停止流和连接
    final streamProvider = context.read<VideoStreamProvider>();
    final connectionProvider = context.read<ConnectionProvider>();

    await streamProvider.stopStream();
    await connectionProvider.disconnect();

    if (!mounted) return;

    // 返回连接屏幕
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const ConnectionScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('设备投屏'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          Consumer<VideoStreamProvider>(
            builder: (context, streamProvider, child) {
              return IconButton(
                icon: Icon(
                  streamProvider.isStreaming ? Icons.cast_connected : Icons.cast,
                ),
                onPressed: () {
                  _showStreamInfo(context, streamProvider);
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _disconnect,
          ),
        ],
      ),
      body: Center(
        child: _isPlayerReady
            ? Consumer<VideoStreamProvider>(
                builder: (context, streamProvider, child) {
                  if (!streamProvider.isStreaming) {
                    return const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text(
                          '等待视频流...',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    );
                  }

                  return AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Video(controller: _videoController),
                  );
                },
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    '初始化播放器...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
      ),
    );
  }

  void _showStreamInfo(BuildContext context, VideoStreamProvider streamProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('流信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('状态: ${streamProvider.streamStatus}'),
            Text('TCP端口: ${streamProvider.tcpPort}'),
            Text('是否流式传输: ${streamProvider.isStreaming ? "是" : "否"}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}