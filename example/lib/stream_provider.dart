import 'package:flutter/foundation.dart';
import 'package:kadb_dart/kadb_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class VideoStreamProvider with ChangeNotifier {
  TcpForwarder? _forwarder;
  bool _isStreaming = false;
  bool _isStarting = false;
  String _streamStatus = '准备就绪';
  int _tcpPort = 0;

  bool get isStreaming => _isStreaming;
  bool get isStarting => _isStarting;
  String get streamStatus => _streamStatus;
  int get tcpPort => _tcpPort;
  TcpForwarder? get forwarder => _forwarder;

  /// 获取TCP流URL - 使用FFmpeg格式，优化H264流播放
  String get tcpUrl => 'tcp://127.0.0.1:$_tcpPort';

  VideoStreamProvider() {
    debugPrint('VideoStreamProvider 初始化');
  }

  Future<bool> startStream(AdbConnection connection) async {
    debugPrint('开始启动视频流...');
    if (_isStarting || _isStreaming) return false;

    _isStarting = true;
    _streamStatus = '启动视频流...';
    notifyListeners();

    try {
      debugPrint('推送scrcpy-server到设备...');
      // 推送scrcpy-server到设备
      await _pushScrcpyServer(connection);
      debugPrint('scrcpy-server推送完成');

      // 随机选择端口
      _tcpPort = 11238 + DateTime.now().millisecond % 100;
      debugPrint('使用TCP端口: $_tcpPort');

      debugPrint('启动TCP转发...');
      // 先启动TCP转发，准备好接收scrcpy连接
      _forwarder = TcpForwarder(
        connection,
        _tcpPort,
        'localabstract:scrcpy',
        debug: false, // 关闭调试输出，提高性能
      );
      await _forwarder!.start();
      debugPrint('✅ TCP转发启动成功，端口: $_tcpPort');

      debugPrint('启动scrcpy服务器...');
      // 启动scrcpy服务器，它会自动连接到已准备好的TCP转发
      await _startScrcpyServer(connection);
      debugPrint('✅ scrcpy服务器启动完成');

      _streamStatus = '视频流已启动';
      _isStreaming = true;
      _isStarting = false;
      notifyListeners();

      return true;
    } catch (e, stackTrace) {
      debugPrint('视频流启动失败: $e');
      debugPrint('错误堆栈: $stackTrace');
      _streamStatus = '启动失败: $e';
      _isStarting = false;
      notifyListeners();

      // 清理资源
      await _forwarder?.stop();
      _forwarder = null;

      return false;
    }
  }

  Future<void> _pushScrcpyServer(AdbConnection connection) async {
    try {
      // 从assets复制scrcpy-server到临时目录
      final serverFile = await _copyAssetToFile('assets/scrcpy-server');

      // 推送到设备
      await KadbDart.push(
        connection,
        serverFile.path,
        '/data/local/tmp/scrcpy-server.jar',
        mode: 33261, // 0o644 in decimal
      );
    } catch (e) {
      throw Exception('推送scrcpy-server失败: $e');
    }
  }

  Future<File> _copyAssetToFile(String assetPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = assetPath.split('/').last;
      final tempFile = File('${tempDir.path}/$fileName');

      final byteData = await rootBundle.load(assetPath);
      final buffer = byteData.buffer;

      await tempFile.writeAsBytes(
        buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      );

      return tempFile;
    } catch (e) {
      throw Exception('无法从assets加载文件: $e');
    }
  }

  Future<void> _startScrcpyServer(AdbConnection connection) async {
    // 使用scrcpy参数，输出标准格式的视频流
    // 使用与示例代码相同的参数，确保兼容性
    final shellCommand =
        'CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / '
        'com.genymobile.scrcpy.Server 3.3.3 '
        'tunnel_forward=true '
        'audio=false '
        'control=false '
        'cleanup=false '
        'raw_stream=true ';
    // 'max_size=1920 ' // 恢复1920分辨率
    // 'bit_rate=1000000 ' // 提高到8Mbps码率，支持高分辨率高帧率
    // 'max_fps=60'; // 恢复60fps

    debugPrint('完整的Scrcpy命令: $shellCommand');

    try {
      // 执行shell命令
      final shellStream = await KadbDart.executeShell(
        connection,
        'sh',
        args: ['-c', shellCommand],
        debug: false, // 关闭调试输出
      );

      // 读取前几行输出来确认服务器启动
      final lines = <String>[];
      bool serverReady = false;

      await for (final line in shellStream.stdout) {
        debugPrint('📟 Scrcpy输出: $line');
        lines.add(line);

        // 一旦有任何输出就说明服务器启动成功
        if (!serverReady) {
          serverReady = true;
          debugPrint('✅ scrcpy服务器启动成功！');
          break; // 立即返回，开始播放
        }

        // 检查是否有错误
        if (line.contains('ERROR') ||
            line.contains('Exception') ||
            line.contains('FATAL')) {
          debugPrint('❌ Scrcpy服务器错误: $line');
          throw Exception('Scrcpy服务器启动失败: $line');
        }
      }

      if (!serverReady) {
        throw Exception('未能确认scrcpy服务器成功启动');
      }
    } catch (e) {
      debugPrint('启动scrcpy服务器时出错: $e');
      rethrow;
    }
  }

  Future<void> stopStream() async {
    try {
      debugPrint('停止视频流...');

      // 停止TCP转发
      await _forwarder?.stop();
      _forwarder = null;
      debugPrint('TCP转发已停止');
    } catch (e) {
      debugPrint('停止流时出错: $e');
    } finally {
      _forwarder = null;
      _isStreaming = false;
      _streamStatus = '已停止';
      _tcpPort = 0;
      notifyListeners();
    }
  }
}
