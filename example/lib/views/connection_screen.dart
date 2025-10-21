import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../connection_provider.dart';
import '../stream_provider.dart';
import 'video_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  @override
  void initState() {
    super.initState();
    debugPrint('ConnectionScreen 初始化');
    _ipController.text = '192.168.2.32';
    _portController.text = '5556';
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    debugPrint('用户点击连接按钮');
    final host = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 5555;

    debugPrint('连接参数 - Host: $host, Port: $port');

    if (host.isEmpty) {
      debugPrint('IP地址为空');
      _showError('请输入设备IP地址');
      return;
    }

    try {
      final connectionProvider = context.read<ConnectionProvider>();
      debugPrint('开始连接设备...');
      final success = await connectionProvider.connectToDevice(host, port);

      if (success && mounted) {
        debugPrint('设备连接成功，启动视频流...');
        // 自动启动视频流
        final streamProvider = context.read<VideoStreamProvider>();
        final streamStarted = await streamProvider.startStream(
          connectionProvider.connection!,
        );

        if (streamStarted && mounted) {
          debugPrint('视频流启动成功，导航到视频页面');
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const VideoScreen()),
          );
        } else {
          debugPrint('视频流启动失败');
          _showError('启动视频流失败');
        }
      } else {
        debugPrint('设备连接失败');
      }
    } catch (e, stackTrace) {
      debugPrint('连接过程中发生异常: $e');
      debugPrint('错误堆栈: $stackTrace');
      _showError('连接错误: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scrcpy 连接'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer2<ConnectionProvider, VideoStreamProvider>(
        builder: (context, connectionProvider, streamProvider, child) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo或标题区域
                Icon(
                  Icons.phone_android,
                  size: 80,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(height: 32),

                const Text(
                  '连接到Android设备',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // 连接表单
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _ipController,
                          decoration: const InputDecoration(
                            labelText: '设备IP地址',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lan),
                            hintText: '例如: 192.168.1.100',
                          ),
                          keyboardType: TextInputType.text,
                          enabled: !connectionProvider.isConnecting,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _portController,
                          decoration: const InputDecoration(
                            labelText: '端口',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.settings_ethernet),
                            hintText: '默认: 5555',
                          ),
                          keyboardType: TextInputType.number,
                          enabled: !connectionProvider.isConnecting,
                        ),
                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed:
                                (connectionProvider.isConnecting ||
                                    connectionProvider.isConnected ||
                                    streamProvider.isStarting)
                                ? null
                                : _connect,
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child:
                                (connectionProvider.isConnecting ||
                                    streamProvider.isStarting)
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Text('连接中...'),
                                    ],
                                  )
                                : const Text(
                                    '连接设备',
                                    style: TextStyle(fontSize: 16),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 状态信息
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              connectionProvider.isConnected
                                  ? Icons.check_circle
                                  : connectionProvider.isConnecting
                                  ? Icons.pending
                                  : Icons.info,
                              color: connectionProvider.isConnected
                                  ? Colors.green
                                  : connectionProvider.isConnecting
                                  ? Colors.orange
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                connectionProvider.statusMessage,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        if (streamProvider.streamStatus.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                streamProvider.isStreaming
                                    ? Icons.play_circle
                                    : streamProvider.isStarting
                                    ? Icons.pending
                                    : Icons.info,
                                color: streamProvider.isStreaming
                                    ? Colors.green
                                    : streamProvider.isStarting
                                    ? Colors.orange
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  streamProvider.streamStatus,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                          if (streamProvider.isStreaming) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.http,
                                  color: Colors.blue,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'HTTP端口: ${streamProvider.httpPort}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  streamProvider.httpConverter?.isConnected ==
                                          true
                                      ? Icons.link
                                      : Icons.link_off,
                                  color:
                                      streamProvider
                                              .httpConverter
                                              ?.isConnected ==
                                          true
                                      ? Colors.green
                                      : Colors.orange,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'HTTP转换器: ${streamProvider.httpConverter?.isConnected == true ? "已连接" : "连接中"}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
