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
      // 启动TCP转发
      _forwarder = TcpForwarder(
        connection,
        _tcpPort,
        'localabstract:scrcpy',
        debug: kDebugMode,
      );
      await _forwarder!.start();
      debugPrint('TCP转发启动成功');

      debugPrint('启动scrcpy服务器...');
      // 启动scrcpy服务器
      await _startScrcpyServer(connection);
      debugPrint('scrcpy服务器启动成功');

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
        mode: 33261,
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
    // 使用最基本的scrcpy参数，避免版本兼容问题
    final shellCommand =
        'CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / '
        'com.genymobile.scrcpy.Server 3.3.3 '
        'tunnel_forward=true max_size=720 raw_stream=true video_codec=h264';

    debugPrint('简化的Scrcpy命令: $shellCommand');

    try {
      // 执行shell命令并启用调试输出
      final shellStream = await KadbDart.executeShell(
        connection,
        shellCommand,
        debug: true, // 启用调试模式，会自动打印输出
      );

      // 读取前几行输出来获取设备信息
      final lines = <String>[];
      await for (final line in shellStream.stdout) {
        debugPrint('应用层Scrcpy输出: $line');
        lines.add(line);

        // 如果找到设备信息行，就停止读取（避免阻塞）
        if (line.contains('Device:') || line.contains('INFO:')) {
          debugPrint('✅ 找到设备信息: $line');
          // 可以在这里解析设备信息并存储
          break;
        }

        // 只读取前几行，避免阻塞
        if (lines.length > 10) {
          debugPrint('⚠️ 已读取10行输出，停止读取以避免阻塞');
          break;
        }
      }

      debugPrint('scrcpy服务器启动成功');
    } catch (e) {
      debugPrint('启动scrcpy服务器时出错: $e');
      rethrow;
    }
  }

  Future<void> stopStream() async {
    try {
      await _forwarder?.stop();
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
