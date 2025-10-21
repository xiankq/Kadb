import 'dart:ffi';

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

      _player.setBufferRange(min: 0, max: 0, drop: true);

      // 设置解码器

      // 添加媒体状态回调
      _player.onMediaStatus((oldValue, newValue) {
        debugPrint('📊 媒体状态变化: $oldValue -> $newValue');
        return true;
      });

      // 添加播放器状态回调
      _player.onStateChanged((oldValue, newValue) {
        debugPrint('🎮 播放器状态变化: $oldValue -> $newValue');
      });

      // 添加事件回调
      _player.onEvent((event) {
        debugPrint(
          '📢 播放器事件: 错误=${event.error}, 类别=${event.category}, 详情=${event.detail}',
        );
      });

      debugPrint('✅ MDK播放器参数设置完成');

      // 延迟启动播放，确保HTTP端口准备就绪
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

    // 只使用HTTP流
    if (streamProvider.httpPort == 0 || streamProvider.httpConverter == null) {
      debugPrint(
        '❌ HTTP转换器不可用: port=${streamProvider.httpPort}, converter=${streamProvider.httpConverter != null}',
      );
      _showError('HTTP转换器不可用');
      return;
    }

    final httpUrl = streamProvider.httpConverter!.httpUrl;
    debugPrint('🌐 使用HTTP流: $httpUrl');

    // 等待HTTP转换器连接
    int waitCount = 0;
    const maxWait = 20; // 增加等待时间

    debugPrint('⏳ 开始等待HTTP转换器连接...');
    while (!streamProvider.httpConverter!.isConnected && waitCount < maxWait) {
      await Future.delayed(const Duration(seconds: 1));
      waitCount++;
      debugPrint(
        '⏳ 等待HTTP转换器连接... (${waitCount}/${maxWait}) - 连接状态: ${streamProvider.httpConverter!.isConnected}',
      );

      // 检查流是否还在运行
      if (!streamProvider.isStreaming) {
        debugPrint('❌ 等待过程中视频流停止了');
        _showError('视频流在等待过程中停止了');
        return;
      }
    }

    if (!streamProvider.httpConverter!.isConnected) {
      debugPrint('❌ HTTP转换器无法连接到TCP流，等待超时');
      _showError('HTTP转换器无法连接到TCP流');
      return;
    }

    debugPrint('✅ HTTP转换器连接成功，开始设置播放器...');

    // 设置播放器参数
    try {
      _player.loop = -1; // 无限循环
      debugPrint('🎛️ 播放器参数设置完成');

      // 尝试播放HTTP流
      debugPrint('🎥 尝试播放HTTP流: $httpUrl');
      bool success = await _tryPlayUrl(httpUrl);

      if (success) {
        setState(() {
          _currentUrl = httpUrl;
          _isInitialized = true;
        });
        debugPrint('✅ HTTP流播放成功，当前URL: $_currentUrl');
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
      _player.media = url;
      debugPrint('✅ 媒体设置完成');

      // 先准备媒体，然后再播放
      debugPrint('🔄 准备媒体...');
      final prepareResult = await _player.prepare();
      debugPrint('📊 媒体准备结果: $prepareResult');

      if (prepareResult < 0) {
        debugPrint('❌ 媒体准备失败，错误码: $prepareResult');
        return false;
      }

      debugPrint('▶️ 设置播放状态为播放');
      _player.state = PlaybackState.playing;

      debugPrint('🔄 更新纹理');
      await _player.updateTexture();

      // 等待更长时间检查是否播放成功
      debugPrint('⏳ 等待播放器初始化...');
      for (int i = 0; i < 20; i++) {
        // 增加到20次检查，每次1秒
        await Future.delayed(const Duration(seconds: 1));
        final textureId = _player.textureId.value;
        final mediaStatus = _player.mediaStatus;
        final playerState = _player.state;

        debugPrint('🔍 检查纹理ID (第${i + 1}次): $textureId');
        debugPrint('📊 媒体状态: $mediaStatus');
        debugPrint('🎮 播放器状态: $playerState');

        // 检查媒体状态
        if (mediaStatus.test(MediaStatus.loaded)) {
          debugPrint('✅ 媒体已加载');
        } else if (mediaStatus.test(MediaStatus.loading)) {
          debugPrint('⏳ 媒体正在加载...');
        } else if (mediaStatus.test(MediaStatus.stalled)) {
          debugPrint('⚠️ 媒体加载停滞');
        } else if (mediaStatus.test(MediaStatus.invalid)) {
          debugPrint('❌ 媒体无效');
          return false;
        }

        if (textureId != null) {
          debugPrint('✅ 播放器纹理ID已生成: $textureId');
          return true;
        }
      }

      debugPrint('❌ 播放器未能生成纹理ID');
      debugPrint('📊 最终媒体状态: ${_player.mediaStatus}');
      debugPrint('🎮 最终播放器状态: ${_player.state}');
      return false;
    } catch (e) {
      debugPrint('❌ 播放URL失败: $url');
      debugPrint('❌ 错误详情: $e');
      debugPrint('❌ 播放器状态: ${_player.state}');
      debugPrint('❌ 纹理ID: ${_player.textureId.value}');
      debugPrint('❌ 媒体状态: ${_player.mediaStatus}');
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
        title: const Text('设备投屏 - HTTP'),
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

                          return AspectRatio(
                            aspectRatio: 16 / 9, // 默认比例
                            child: Texture(textureId: textureId),
                          );
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
            Text('HTTP端口: ${streamProvider.httpPort}'),
            Text('HTTP URL: ${streamProvider.httpConverter?.httpUrl ?? "未知"}'),
            Text('是否流式传输: ${streamProvider.isStreaming ? "是" : "否"}'),
            Text(
              'HTTP转换器状态: ${streamProvider.httpConverter?.isConnected == true ? "已连接" : "未连接"}',
            ),
            Text('播放方式: HTTP转发'),
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
