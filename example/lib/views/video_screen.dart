import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../connection_provider.dart';
import '../stream_provider.dart';
import 'connection_screen.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  VideoPlayerController? _videoController;
  bool _isPlayerReady = false;
  bool _isPlaying = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      debugPrint('🎬 初始化FVP播放器...');

      // 延迟启动播放，确保TCP端口准备就绪
      await _startVideoPlayback();
    } catch (e) {
      _handleError('播放器初始化失败: $e');
    }
  }

  Future<void> _startVideoPlayback() async {
    if (!mounted) return;

    final streamProvider = context.read<VideoStreamProvider>();
    if (!streamProvider.isStreaming || streamProvider.httpPort == 0) {
      debugPrint('视频流未准备好');
      return;
    }

    final httpPort = streamProvider.httpPort;
    final httpUrl = streamProvider.httpConverter?.httpUrl ?? 'http://127.0.0.1:$httpPort';

    debugPrint('准备连接HTTP端口: $httpPort');
    debugPrint('HTTP URL: $httpUrl');

    try {
      // 等待HTTP转换器连接成功
      debugPrint('等待HTTP转换器连接TCP流...');
      int waitCount = 0;
      const maxWait = 10; // 最多等待10秒
      
      while (!streamProvider.httpConverter!.isConnected && waitCount < maxWait) {
        await Future.delayed(Duration(seconds: 1));
        waitCount++;
        debugPrint('等待HTTP转换器连接... (${waitCount}/${maxWait})');
      }
      
      if (!streamProvider.httpConverter!.isConnected) {
        throw Exception('HTTP转换器无法连接到TCP流');
      }
      
      debugPrint('HTTP转换器连接成功，等待更长时间让视频流稳定...');

      // 延迟更长时间给视频流更多时间稳定
      await Future.delayed(Duration(seconds: 3));
      debugPrint('等待完成，开始播放');

      // 创建视频控制器并连接到HTTP流
      debugPrint('🎯 开始播放HTTP流: $httpUrl');
      _videoController = VideoPlayerController.networkUrl(Uri.parse(httpUrl));

      // 设置监听器
      _videoController!.addListener(_onPlayerStateChanged);

      // 初始化播放器
      await _videoController!.initialize();

      setState(() {
        _isPlayerReady = true;
      });

      debugPrint('✅ 视频播放器初始化成功');
      debugPrint('🎯 播放器状态: 准备就绪=$_isPlayerReady, 播放中=$_isPlaying');

      // 开始播放
      await _videoController!.play();

      // 添加状态检查定时器
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _isPlayerReady && !_isPlaying) {
          debugPrint('⚠️ 播放器已就绪但未开始播放，尝试重新连接');
          _scheduleReconnect();
        } else if (mounted && _isPlaying) {
          debugPrint('🎉 播放器正常播放中');
        } else if (mounted && !_isPlayerReady) {
          debugPrint('⚠️ 播放器未就绪，尝试自动重连');
          _scheduleReconnect();
        }
      });
    } catch (e) {
      debugPrint('视频播放器启动失败: $e');

      // 如果是连接超时或无效媒体错误，尝试重连
      if (e.toString().contains('TimeoutException') ||
          e.toString().contains('invalid or unsupported media') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('NetworkException')) {
        debugPrint('检测到连接问题，尝试自动重连...');
        _scheduleReconnect();
      } else {
        _showPlaybackError('播放失败: $e');
      }
    }
  }

  void _onPlayerStateChanged() {
    if (!mounted || _videoController == null) return;

    final wasPlaying = _isPlaying;
    _isPlaying = _videoController!.value.isPlaying;

    if (wasPlaying != _isPlaying) {
      debugPrint('🎬 播放状态变更: $_isPlaying');
      setState(() {});
    }

    // 检查是否有错误
    if (_videoController!.value.hasError) {
      debugPrint('播放器错误: ${_videoController!.value.errorDescription}');
      _handleError('播放器错误: ${_videoController!.value.errorDescription}');
    }

    // 检查视频尺寸
    if (_videoController!.value.isInitialized &&
        (_videoController!.value.size.width > 0 ||
            _videoController!.value.size.height > 0)) {
      debugPrint(
        '📺 视频尺寸: ${_videoController!.value.size.width}x${_videoController!.value.size.height}',
      );
    }
  }

  void _handleError(String message) {
    if (!mounted) return;

    debugPrint('播放器错误: $message');

    setState(() {
      _hasError = true;
      _errorMessage = message;
    });
  }

  void _showPlaybackError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
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

  Future<void> _play() async {
    try {
      await _videoController?.play();
    } catch (e) {
      _handleError('播放失败: $e');
    }
  }

  Future<void> _pause() async {
    try {
      await _videoController?.pause();
    } catch (e) {
      _handleError('暂停失败: $e');
    }
  }

  Future<void> _stop() async {
    try {
      await _videoController?.pause();
    } catch (e) {
      _handleError('停止失败: $e');
    }
  }

  Future<void> _reconnect() async {
    if (!mounted) return;

    debugPrint('🔄 开始手动重连...');
    setState(() {
      _hasError = false;
      _errorMessage = '';
    });

    try {
      await _stop();
      await _videoController?.dispose();
      _videoController = null;
      _isPlayerReady = false;

      // 等待一段时间再重连，给scrcpy服务器时间
      await Future.delayed(Duration(seconds: 2));

      await _startVideoPlayback();
      debugPrint('✅ 手动重连成功');
    } catch (e) {
      debugPrint('❌ 手动重连失败: $e');
      _handleError('重连失败: $e');
    }
  }

  /// 调度自动重连
  void _scheduleReconnect() {
    if (!mounted) return;

    debugPrint('🔄 调度自动重连...');

    // 延迟3秒后自动重连
    Future.delayed(Duration(seconds: 3), () {
      if (mounted && (_hasError || !_isPlayerReady)) {
        debugPrint('🔄 执行自动重连...');
        _reconnect();
      }
    });
  }

  Future<void> _disconnect() async {
    // 停止播放器
    try {
      await _videoController?.pause();
      await _videoController?.dispose();
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
      MaterialPageRoute(builder: (context) => const ConnectionScreen()),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            const Text(
              '播放错误',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.white60),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _reconnect, child: const Text('重新连接')),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Color.fromRGBO(0, 0, 0, 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: _isPlaying ? _pause : _play,
            ),
            IconButton(
              icon: const Icon(Icons.stop, color: Colors.white),
              onPressed: _stop,
            ),
            IconButton(
              icon: const Icon(Icons.replay, color: Colors.white),
              onPressed: _reconnect,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onPlayerStateChanged);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('设备投屏'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            IconButton(icon: const Icon(Icons.close), onPressed: _disconnect),
          ],
        ),
        body: _buildErrorWidget(),
      );
    }

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
            child: _isPlayerReady && _videoController != null
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
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
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
          _buildControls(),
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
            Text('HTTP端口: ${streamProvider.httpPort}'),
            Text('HTTP URL: ${streamProvider.httpConverter?.httpUrl ?? "未知"}'),
            Text('是否流式传输: ${streamProvider.isStreaming ? "是" : "否"}'),
            Text('HTTP转换器状态: ${streamProvider.httpConverter?.isConnected == true ? "已连接" : "未连接"}'),
            Text('播放器状态: ${_isPlaying ? "播放中" : "暂停/停止"}'),
            if (_videoController != null)
              Text(
                '视频尺寸: ${_videoController!.value.size.width}x${_videoController!.value.size.height}',
              ),
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
