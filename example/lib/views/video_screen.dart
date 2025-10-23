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
  String _videoUrl = '';
  String _audioUrl = '';

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _setupPlayer();
      await _startPlayback();
    } catch (e) {
      debugPrint('❌ 播放器初始化失败: $e');
      _showError('播放器初始化失败: $e');
    }
  }

  void _setupPlayer() {
    debugPrint('🔧 设置播放器参数');

    // 低延迟优化
    _player.setBufferRange(min: 0, max: 0, drop: true);

    // 设置解码器
    _player.setDecoders(MediaType.video, [
      'AMediaCodec',
      'FFmpeg',
      'h264_mmal',
      'h264_cuvid',
    ]);
    _player.setDecoders(MediaType.audio, ['AMediaCodec', 'FFmpeg']);

    // 状态回调
    _player.onMediaStatus((oldValue, newValue) {
      debugPrint('📊 媒体状态变化: $oldValue -> $newValue');
      if (newValue.test(MediaStatus.invalid)) {
        debugPrint('❌ 媒体无效');
      }
      if (newValue.test(MediaStatus.loaded)) {
        debugPrint('✅ 媒体已加载');
      }
      return true;
    });

    _player.onStateChanged((oldValue, newValue) {
      debugPrint('🎮 播放器状态变化: $oldValue -> $newValue');
    });

    debugPrint('✅ 播放器参数设置完成');
  }

  Future<void> _startPlayback() async {
    if (!mounted) return;

    final streamProvider = context.read<VideoStreamProvider>();
    if (!_isStreamReady(streamProvider)) return;

    _videoUrl = streamProvider.videoUrl;
    _audioUrl = streamProvider.audioUrl;
    _player.loop = -1;

    debugPrint('🎬 开始播放: 视频=$_videoUrl, 音频=$_audioUrl');

    // 等待端口准备就绪
    await Future.delayed(const Duration(seconds: 2));

    // 设置音视频媒体
    bool success = await _setMedia();

    if (success) {
      setState(() => _isInitialized = true);
      debugPrint('✅ 音视频播放成功');
    } else {
      _showError('无法播放音视频流');
    }
  }

  Future<bool> _setMedia() async {
    try {
      debugPrint('🎬 设置音视频媒体');

      // 先停止播放器
      _player.state = PlaybackState.stopped;

      // 设置视频和音频
      _player.setMedia(_videoUrl, MediaType.video);
      _player.setMedia(_audioUrl, MediaType.audio);

      debugPrint('🔄 准备播放器...');
      final result = await _player.prepare();
      debugPrint('📊 播放器准备结果: $result');

      if (result >= 0) {
        debugPrint('▶️ 开始播放');
        _player.state = PlaybackState.playing;
        await _player.updateTexture();
        return await _waitForPlayerReady();
      }

      // 如果失败，不切换播放方案，继续等待
      debugPrint('⚠️ 播放器准备失败，继续等待数据流...');
      return false;
    } catch (e) {
      debugPrint('❌ 设置媒体失败: $e');
      return false;
    }
  }

  Future<bool> _waitForPlayerReady() async {
    debugPrint('⏳ 等待播放器就绪...');

    for (int i = 0; i < 60; i++) {
      // 增加等待时间到60秒
      await Future.delayed(const Duration(seconds: 1));

      final textureId = _player.textureId.value;
      final mediaStatus = _player.mediaStatus;
      final playerState = _player.state;

      debugPrint('🔍 检查播放器状态 (第${i + 1}次):');
      debugPrint('   纹理ID: $textureId');
      debugPrint('   媒体状态: $mediaStatus');
      debugPrint('   播放器状态: $playerState');

      if (mediaStatus.test(MediaStatus.loaded) && textureId != null) {
        debugPrint('✅ 播放器就绪');
        return true;
      }

      if (mediaStatus.test(MediaStatus.invalid)) {
        debugPrint('❌ 媒体无效');
        // 不立即返回false，继续等待
      }

      // 每15秒重试一次设置媒体
      if (i > 0 && i % 15 == 0) {
        debugPrint('🔄 重试设置媒体');
        _player.setMedia(_videoUrl, MediaType.video);
        if (_audioUrl.isNotEmpty) {
          _player.setMedia(_audioUrl, MediaType.audio);
        }
        await _player.prepare();
        _player.state = PlaybackState.playing;
      }
    }

    debugPrint('❌ 播放器未能就绪');
    return false;
  }

  bool _isStreamReady(VideoStreamProvider streamProvider) {
    debugPrint(
      '🔍 检查流状态: isStreaming=${streamProvider.isStreaming}, status=${streamProvider.streamStatus}',
    );

    if (!streamProvider.isStreaming) {
      _showError('视频流未准备好: ${streamProvider.streamStatus}');
      return false;
    }

    if (streamProvider.videoPort == 0) {
      _showError('视频端口不可用');
      return false;
    }

    return true;
  }

  void _showError(String message) {
    debugPrint('❌ 错误: $message');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        action: SnackBarAction(label: '重试', onPressed: _reconnect),
      ),
    );
  }

  Future<void> _reconnect() async {
    debugPrint('🔄 重新连接...');
    _player.state = PlaybackState.stopped;
    await _startPlayback();
  }

  void _switchDecoder() {
    final decoders = _player.videoDecoders;
    debugPrint('🔄 当前解码器: $decoders');

    if (decoders.contains('AMediaCodec')) {
      _player.setDecoders(MediaType.video, ['FFmpeg', 'dav1d']);
      debugPrint('🔄 切换到软件解码器');
    } else {
      _player.setDecoders(MediaType.video, [
        'AMediaCodec',
        'FFmpeg',
        'h264_mmal',
        'h264_cuvid',
      ]);
      debugPrint('🔄 切换到硬件解码器');
    }
  }

  Future<void> _disconnect() async {
    debugPrint('🔌 断开连接...');
    _player.state = PlaybackState.stopped;

    if (!mounted) return;

    final streamProvider = context.read<VideoStreamProvider>();
    final connectionProvider = context.read<ConnectionProvider>();

    await streamProvider.stopStream();
    await connectionProvider.disconnect();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const ConnectionScreen()),
    );
  }

  @override
  void dispose() {
    debugPrint('🧹 清理播放器资源');
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('设备投屏 - 音视频同步'),
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
                onPressed: () => _showStreamInfo(context, streamProvider),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _switchDecoder,
            tooltip: '切换解码器',
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: _disconnect),
        ],
      ),
      body: Center(child: _buildPlayer()),
    );
  }

  Widget _buildPlayer() {
    if (!_isInitialized) {
      return _buildLoadingIndicator();
    }

    return Consumer<VideoStreamProvider>(
      builder: (context, streamProvider, child) {
        if (!streamProvider.isStreaming) {
          return _buildLoadingIndicator();
        }

        return ValueListenableBuilder<int?>(
          valueListenable: _player.textureId,
          builder: (context, textureId, _) {
            if (textureId == null) {
              return _buildLoadingIndicator();
            }

            return Stack(
              children: [
                Texture(textureId: textureId),
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.audiotrack,
                          color: _player.state == PlaybackState.playing
                              ? Colors.green
                              : Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _player.state == PlaybackState.playing
                              ? '音视频'
                              : '无信号',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLoadingIndicator() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: Colors.white),
        SizedBox(height: 16),
        Text('初始化播放器...', style: TextStyle(color: Colors.white)),
      ],
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
            Text('视频端口: ${streamProvider.videoPort}'),
            Text('音频端口: ${streamProvider.audioPort}'),
            Text('视频URL: ${streamProvider.videoUrl}'),
            Text('音频URL: ${streamProvider.audioUrl}'),
            Text('播放器状态: ${_player.state.toString()}'),
            if (streamProvider.videoMetadata != null)
              Text(
                '视频元数据: ${streamProvider.videoMetadata!.codec} ${streamProvider.videoMetadata!.width}x${streamProvider.videoMetadata!.height}',
              ),
            if (streamProvider.audioMetadata != null)
              Text('音频元数据: ${streamProvider.audioMetadata!.codec}'),
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
