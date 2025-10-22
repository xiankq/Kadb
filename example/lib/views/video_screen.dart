import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fvp/mdk.dart';
import '../connection_provider.dart';
import '../stream_provider.dart';
import 'connection_screen.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final Player _player = Player();
  bool _isInitialized = false;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      debugPrint('🎬 初始化FVP播放器...');

      // 极致低延迟优化：接近零缓冲
      _player.setBufferRange(min: 0, max: 0, drop: true);

      // 设置TCP协议支持和H264流优化
      // _player.setProperty('demux.buffer.protocols', 'tcp');

      // 硬件解码器绝对优先
      _player.setDecoders(MediaType.video, [
        'AMediaCodec',
        'FFmpeg',
        'h264_mmal',
        'h264_cuvid',
      ]);
      _player.setDecoders(MediaType.audio, [
        'AMediaCodec',
        'FFmpeg',
        'h264_mmal',
        'h264_cuvid',
      ]);

      // _player.setProperty('rtsp_transport', 'tcp'); // 强制TCP传输

      // 极致低延迟模式设置

      // 解码器优化，平衡性能和质量

      // 添加媒体状态回调
      _player.onMediaStatus((oldValue, newValue) {
        // 只在出错时打印
        if (newValue.test(MediaStatus.invalid)) debugPrint('❌ 媒体无效');
        return true;
      });

      // 添加播放器状态回调
      _player.onStateChanged((oldValue, newValue) {});

      debugPrint('✅ MDK播放器参数设置完成');

      // 延迟启动播放，确保TCP端口准备就绪
      await Future.delayed(const Duration(seconds: 2));
      await _startVideoPlayback();
    } catch (e) {
      debugPrint('❌ 播放器初始化失败: $e');
      _showError('播放器初始化失败: $e');
    }
  }

  Future<void> _startVideoPlayback() async {
    if (!mounted) return;

    final streamProvider = context.read<VideoStreamProvider>();
    debugPrint(
      '🔍 检查流状态: isStreaming=${streamProvider.isStreaming}, status=${streamProvider.streamStatus}',
    );

    if (!streamProvider.isStreaming) {
      debugPrint('⚠️ 视频流未准备好，状态: ${streamProvider.streamStatus}');
      _showError('视频流未准备好: ${streamProvider.streamStatus}');
      return;
    }

    // 检查TCP端口
    if (streamProvider.tcpPort == 0) {
      debugPrint('❌ TCP端口不可用');
      _showError('TCP端口不可用');
      return;
    }

    final tcpUrl = streamProvider.tcpUrl;
    debugPrint('🌐 使用TCP流: $tcpUrl');

    // 设置播放器参数
    try {
      _player.loop = -1; // 无限循环
      debugPrint('🎛️ 播放器参数设置完成');

      // 尝试播放TCP流
      debugPrint('🎥 尝试播放TCP流: $tcpUrl');
      bool success = await _tryPlayUrl(tcpUrl);

      if (success) {
        setState(() {
          _currentUrl = tcpUrl;
          _isInitialized = true;
        });
        debugPrint('✅ TCP流播放成功，当前URL: $_currentUrl');
      } else {
        debugPrint('❌ 无法播放HTTP视频流');
        _showError('无法播放HTTP视频流');
      }
    } catch (e) {
      debugPrint('❌ 播放器设置失败: $e');
      _showError('播放器设置失败: $e');
    }
  }

  Future<bool> _tryPlayUrl(String url) async {
    try {
      debugPrint('🎬 开始设置播放器媒体: $url');

      // 从URL中提取端口号
      final portRegex = RegExp(r':(\d+)');
      final match = portRegex.firstMatch(url);
      final port = match?.group(1) ?? '0';

      // 尝试多种URL格式，确保兼容性
      final urls = [
        url, // 原始URL
        'tcp://127.0.0.1:$port', // 简化格式
        'tcp://localhost:$port', // localhost格式
      ];

      for (int attempt = 0; attempt < urls.length; attempt++) {
        final testUrl = urls[attempt];
        debugPrint('🔄 尝试URL格式 ${attempt + 1}/${urls.length}: $testUrl');

        _player.media = testUrl;
        debugPrint('✅ 媒体设置完成');

        // 先准备媒体，然后再播放
        debugPrint('🔄 准备媒体...');
        final prepareResult = await _player.prepare();
        debugPrint('📊 媒体准备结果: $prepareResult');

        if (prepareResult >= 0) {
          debugPrint('✅ 媒体准备成功');
          break;
        } else {
          debugPrint('⚠️ 媒体准备失败，错误码: $prepareResult，尝试下一种URL格式');
          if (attempt == urls.length - 1) {
            return false;
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      debugPrint('▶️ 设置播放状态为播放');
      _player.state = PlaybackState.playing;

      debugPrint('🔄 更新纹理');
      await _player.updateTexture();

      // 等待更长时间检查是否播放成功，但增加更详细的状态检查
      debugPrint('⏳ 等待播放器初始化...');
      bool hasData = false;
      int stallCount = 0;

      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final textureId = _player.textureId.value;
        final mediaStatus = _player.mediaStatus;
        final playerState = _player.state;
        final buffered = _player.buffered();

        debugPrint('🔍 检查播放状态 (第${i + 1}次):');
        debugPrint('   纹理ID: $textureId');
        debugPrint('   媒体状态: $mediaStatus');
        debugPrint('   播放器状态: $playerState');
        debugPrint('   缓冲数据: ${buffered}ms');

        // 检查媒体状态
        if (mediaStatus.test(MediaStatus.loaded)) {
          debugPrint('✅ 媒体已加载');
          hasData = true;
          stallCount = 0;
        } else if (mediaStatus.test(MediaStatus.loading)) {
          debugPrint('⏳ 媒体正在加载...');
          stallCount = 0;
        } else if (mediaStatus.test(MediaStatus.stalled)) {
          debugPrint('⚠️ 媒体加载停滞');
          stallCount++;
          if (stallCount > 5) {
            debugPrint('❌ 媒体停滞时间过长，尝试重新准备');
            final retryResult = await _player.prepare();
            if (retryResult >= 0) {
              stallCount = 0;
            }
          }
        } else if (mediaStatus.test(MediaStatus.invalid)) {
          debugPrint('❌ 媒体无效');
          return false;
        }

        // 检查是否有缓冲数据
        if (buffered > 0) {
          debugPrint('✅ 检测到缓冲数据: ${buffered}ms');
          hasData = true;
        }

        if (textureId != null) {
          debugPrint('✅ 播放器纹理ID已生成: $textureId');
          return true;
        }

        // 如果超过10秒没有任何进展，尝试重新设置播放器
        if (i > 10 && !hasData) {
          debugPrint('⚠️ 10秒内无进展，尝试重新设置媒体');
          _player.media = url;
          await _player.prepare();
          _player.state = PlaybackState.playing;
        }
      }

      debugPrint('❌ 播放器未能生成纹理ID');
      debugPrint('📊 最终媒体状态: ${_player.mediaStatus}');
      debugPrint('🎮 最终播放器状态: ${_player.state}');
      debugPrint('📊 最终缓冲数据: ${_player.buffered()}ms');
      return false;
    } catch (e) {
      debugPrint('❌ 播放URL失败: $url');
      debugPrint('❌ 错误详情: $e');
      debugPrint('❌ 播放器状态: ${_player.state}');
      debugPrint('❌ 纹理ID: ${_player.textureId.value}');
      debugPrint('❌ 媒体状态: ${_player.mediaStatus}');

      // 尝试获取更详细的错误信息
      try {
        final mediaInfo = _player.mediaInfo;
        debugPrint('📊 媒体信息: $mediaInfo');
      } catch (_) {
        debugPrint('📊 无法获取媒体信息');
      }

      return false;
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '重试',
          onPressed: () {
            _reconnect();
          },
        ),
      ),
    );
  }

  Future<void> _reconnect() async {
    debugPrint('🔄 重新连接...');
    _player.state = PlaybackState.stopped;
    await _startVideoPlayback();
  }

  /// 切换解码器
  void _switchDecoder() {
    final currentDecoders = _player.videoDecoders;
    debugPrint('🔄 当前解码器: $currentDecoders');

    // 尝试不同的解码器组合
    if (currentDecoders.contains('AMediaCodec')) {
      // 如果当前使用硬件解码，切换到软件解码
      _player.setDecoders(MediaType.video, ['FFmpeg', 'dav1d']);
      debugPrint('🔄 切换到软件解码器');
    } else if (currentDecoders.contains('FFmpeg')) {
      // 如果当前使用FFmpeg，尝试其他软件解码器
      _player.setDecoders(MediaType.video, ['dav1d', 'FFmpeg']);
      debugPrint('🔄 切换到dav1d解码器');
    } else {
      // 最后尝试所有可用的解码器
      _player.setDecoders(MediaType.video, [
        'AMediaCodec',
        'h264_mmal',
        'h264_cuvid',
        'FFmpeg',
        'dav1d',
      ]);
      debugPrint('🔄 重置为所有可用解码器');
    }
  }

  Future<void> _disconnect() async {
    // 停止播放器
    _player.state = PlaybackState.stopped;

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
      MaterialPageRoute(builder: (context) => const ConnectionScreen()),
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
        title: const Text('设备投屏 - TCP'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          Consumer<VideoStreamProvider>(
            builder: (context, streamProvider, child) {
              return IconButton(
                icon: Icon(
                  streamProvider.isStreaming
                      ? Icons.cast_connected
                      : Icons.cast,
                ),
                onPressed: () {
                  _showStreamInfo(context, streamProvider);
                },
              );
            },
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: _disconnect),
        ],
      ),
      body: Stack(
        children: [
          // 视频播放器
          Center(
            child: _isInitialized
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

                      return ValueListenableBuilder<int?>(
                        valueListenable: _player.textureId,
                        builder: (context, textureId, _) {
                          if (textureId == null) {
                            return const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(color: Colors.white),
                                SizedBox(height: 16),
                                Text(
                                  '初始化播放器...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            );
                          }

                          return Texture(textureId: textureId);
                        },
                      );
                    },
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text('初始化播放器...', style: TextStyle(color: Colors.white)),
                    ],
                  ),
          ),

          // 播放控制
        ],
      ),
    );
  }

  void _showStreamInfo(
    BuildContext context,
    VideoStreamProvider streamProvider,
  ) {
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
            Text('TCP端口: ${streamProvider.tcpPort}'),
            Text('TCP URL: ${streamProvider.tcpUrl}'),
            Text('是否流式传输: ${streamProvider.isStreaming ? "是" : "否"}'),
            Text('播放方式: TCP直接连接'),
            Text('当前URL: $_currentUrl'),
            Text('播放器状态: ${_player.state.toString()}'),
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
