import 'dart:io';
import 'dart:async';
import 'package:kadb_dart/kadb_dart.dart';

/// Scrcpy集成示例
///
/// 此示例展示如何使用KadbDart实现完整的scrcpy服务器启动流程：
/// 1. 推送scrcpy-server到设备
/// 2. 设置端口转发
/// 3. 启动scrcpy服务器
class ScrcpyIntegration {
  late AdbConnection _connection;
  final String _scrcpyServerPath;
  final String _devicePath = '/data/local/tmp/scrcpy-server-manual.jar';
  TcpForwarder? _forwarder;

  ScrcpyIntegration(this._scrcpyServerPath);

  /// 初始化ADB连接
  Future<void> connect({String host = '100.123.66.1', int port = 5555}) async {
    print('正在连接到设备 $host:$port...');
    final keyPair = await CertUtils.loadKeyPair();

    _connection = await KadbDart.connect(
      host: host,
      port: port,
      keyPair: keyPair,
      debug: true,
    );
    print('设备连接成功！');
  }

  /// 推送scrcpy-server到设备
  Future<void> pushScrcpyServer() async {
    print('正在推送scrcpy-server到设备...');

    try {
      // 检查本地文件是否存在
      final file = File(_scrcpyServerPath);
      if (!await file.exists()) {
        throw Exception('scrcpy-server文件不存在: $_scrcpyServerPath');
      }

      // 打开同步流
      final syncStream = await KadbDart.openSync(_connection);

      // 读取本地文件
      final fileBytes = await file.readAsBytes();
      final fileSize = fileBytes.length;

      print('文件大小: $fileSize 字节');

      // 发送文件
      final fileStream = Stream.value(fileBytes);
      final currentTime = DateTime.now().millisecondsSinceEpoch;

      await syncStream.send(fileStream, _devicePath, 33261, currentTime);

      print('scrcpy-server已成功推送到设备: $_devicePath');

      // 验证文件是否存在
      final shellStream = await KadbDart.executeShell(_connection, 'ls', [
        '-la',
        _devicePath,
      ]);
      final result = await shellStream.readAll();
      print('设备上的文件信息: $result');
    } catch (e) {
      print('推送scrcpy-server失败: $e');
      rethrow;
    }
  }

  /// 设置端口转发
  Future<void> setupPortForwarding({int localPort = 1234}) async {
    print('正在设置端口转发: 本地端口 $localPort -> 设备 scrcpy');

    try {
      // 注意：KadbDart.startTcpForward 需要整数端口，不是字符串
      // 对于 localabstract:scrcpy，我们需要使用不同的方法

      // 首先尝试使用ADB命令设置端口转发
      final shellStream = await KadbDart.executeShell(_connection, 'adb', [
        'forward',
        'tcp:$localPort',
        'localabstract:scrcpy',
      ]);

      final result = await shellStream.readAll();
      print('端口转发设置结果: $result');

      // 创建本地TCP转发器来监听端口
      _forwarder = TcpForwarder(
        _connection,
        localPort,
        27183,
      ); // 27183是scrcpy默认端口
      await _forwarder!.start();

      print('端口转发设置成功！');
    } catch (e) {
      print('设置端口转发失败: $e');
      rethrow;
    }
  }

  /// 启动scrcpy服务器
  Future<void> startScrcpyServer({
    int version = 3,
    bool tunnelForward = true,
    bool audio = false,
    bool control = false,
    bool cleanup = false,
    bool rawStream = true,
    int maxSize = 1920,
  }) async {
    print('正在启动scrcpy服务器...');

    try {
      // 构建命令参数
      final args = <String>[
        version.toString(),
        if (tunnelForward) 'tunnel_forward=true' else 'tunnel_forward=false',
        if (audio) 'audio=true' else 'audio=false',
        if (control) 'control=true' else 'control=false',
        if (cleanup) 'cleanup=true' else 'cleanup=false',
        if (rawStream) 'raw_stream=true' else 'raw_stream=false',
        'max_size=$maxSize',
      ];

      // 构建完整的shell命令
      final shellCommand =
          'CLASSPATH=$_devicePath app_process / com.genymobile.scrcpy.Server ${args.join(' ')}';

      print('执行命令: $shellCommand');

      // 执行命令
      final shellStream = await KadbDart.executeShell(_connection, 'sh', [
        '-c',
        shellCommand,
      ]);

      print('scrcpy服务器启动成功！');

      // 读取输出（可选）
      _readServerOutput(shellStream);
    } catch (e) {
      print('启动scrcpy服务器失败: $e');
      rethrow;
    }
  }

  /// 读取服务器输出
  void _readServerOutput(AdbShellStream shellStream) {
    print('开始读取服务器输出...');

    // 异步读取标准输出
    shellStream.stdout.listen(
      (data) {
        print('服务器输出: $data');
      },
      onError: (error) {
        print('读取服务器输出时出错: $error');
      },
      onDone: () {
        print('服务器标准输出流结束');
      },
    );

    // 异步读取标准错误
    shellStream.stderr.listen(
      (data) {
        print('服务器错误: $data');
      },
      onError: (error) {
        print('读取服务器错误时出错: $error');
      },
      onDone: () {
        print('服务器错误输出流结束');
      },
    );

    // 监听退出码
    shellStream.exitCode.listen((exitCode) {
      print('服务器退出，退出码: $exitCode');
    });
  }

  /// 完整的scrcpy启动流程
  Future<void> startScrcpy({
    String host = '100.123.66.1',
    int port = 5555,
    int localPort = 1234,
    Map<String, dynamic> options = const {},
  }) async {
    try {
      // 1. 连接设备
      await connect(host: host, port: port);

      // 2. 推送scrcpy-server
      await pushScrcpyServer();

      // 3. 设置端口转发
      await setupPortForwarding(localPort: localPort);

      // 4. 启动scrcpy服务器
      await startScrcpyServer(
        version: options['version'] ?? 3,
        tunnelForward: options['tunnelForward'] ?? true,
        audio: options['audio'] ?? false,
        control: options['control'] ?? false,
        cleanup: options['cleanup'] ?? false,
        rawStream: options['rawStream'] ?? true,
        maxSize: options['maxSize'] ?? 1920,
      );

      print('scrcpy启动完成！');
      print('现在可以通过本地端口 $localPort 连接到scrcpy服务');
    } catch (e) {
      print('启动scrcpy失败: $e');
      rethrow;
    }
  }

  /// 关闭连接和清理资源
  Future<void> close() async {
    try {
      // 停止TCP转发器
      if (_forwarder != null) {
        await _forwarder!.stop();
        _forwarder = null;
      }

      // 关闭ADB连接
      _connection.close();
      print('ADB连接已关闭');
    } catch (e) {
      print('关闭连接时出错: $e');
    }
  }
}

/// 主函数示例
Future<void> main() async {
  final scrcpy = ScrcpyIntegration('../scrcpy/scrcpy-server');

  try {
    await scrcpy.startScrcpy(
      options: {
        'version': 3,
        'tunnelForward': true,
        'audio': false,
        'control': false,
        'cleanup': false,
        'rawStream': true,
        'maxSize': 1920,
      },
    );

    // 保持运行，等待用户输入
    print('按任意键退出...');
    await stdin.first;
  } catch (e) {
    print('错误: $e');
  } finally {
    scrcpy.close();
  }
}
