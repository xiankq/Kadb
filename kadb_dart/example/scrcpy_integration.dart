import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:kadb_dart/kadb_dart.dart';


/// Scrcpy选项类 - 类型安全的配置选项
class ScrcpyOptions {
  final double version;
  final bool tunnelForward;
  final bool audio;
  final bool control;
  final bool cleanup;
  final bool rawStream;
  final int maxSize;

  const ScrcpyOptions({
    this.version = 3.1,
    this.tunnelForward = true,
    this.audio = false,
    this.control = false,
    this.cleanup = false,
    this.rawStream = true,
    this.maxSize = 1920,
  });

  /// 生成命令行参数
  List<String> toCommandLineArgs() {
    return [
      version.toString(),
      'tunnel_forward=$tunnelForward',
      'audio=$audio',
      'control=$control',
      'cleanup=$cleanup',
      'raw_stream=$rawStream',
      'max_size=$maxSize',
    ];
  }

  /// 创建默认配置（仅显示）
  static const ScrcpyOptions displayOnly = ScrcpyOptions(
    audio: false,
    control: false,
  );

  /// 创建完整功能配置
  static const ScrcpyOptions fullFeatures = ScrcpyOptions(
    audio: true,
    control: true,
  );

  /// 创建高质量配置
  static const ScrcpyOptions highQuality = ScrcpyOptions(
    audio: false,
    control: false,
    maxSize: 2560,
  );

  /// 从配置创建新的配置实例
  ScrcpyOptions copyWith({
    double? version,
    bool? tunnelForward,
    bool? audio,
    bool? control,
    bool? cleanup,
    bool? rawStream,
    int? maxSize,
  }) {
    return ScrcpyOptions(
      version: version ?? this.version,
      tunnelForward: tunnelForward ?? this.tunnelForward,
      audio: audio ?? this.audio,
      control: control ?? this.control,
      cleanup: cleanup ?? this.cleanup,
      rawStream: rawStream ?? this.rawStream,
      maxSize: maxSize ?? this.maxSize,
    );
  }

  @override
  String toString() {
    return 'ScrcpyOptions(version: $version, tunnelForward: $tunnelForward, audio: $audio, control: $control, cleanup: $cleanup, rawStream: $rawStream, maxSize: $maxSize)';
  }
}

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
    _connection = await KadbDart.create(host: host, port: port, debug: false);
    print('设备连接成功！');
  }

  /// 推送scrcpy-server到设备
  Future<void> pushScrcpyServer() async {
    print('正在推送scrcpy-server到设备...');

    try {
      final file = File(_scrcpyServerPath);
      if (!await file.exists()) {
        throw Exception('scrcpy-server文件不存在: $_scrcpyServerPath');
      }

      await KadbDart.push(
        _connection,
        _scrcpyServerPath,
        _devicePath,
        mode: 33261,
      );

      print('scrcpy-server已成功推送到设备: $_devicePath');
    } catch (e) {
      print('推送scrcpy-server失败: $e');
      rethrow;
    }
  }

  /// 设置端口转发
  Future<void> setupPortForwarding({int localPort = 1234}) async {
    print('正在设置端口转发: 本地端口 $localPort -> 设备 scrcpy');

    try {
      _forwarder = TcpForwarder(_connection, localPort, 'localabstract:scrcpy');
      await _forwarder!.start();

      print('✅ ADB转发已启动: tcp:$localPort -> localabstract:scrcpy');
      print('💡 现在可以通过 localhost:$localPort 连接到scrcpy服务');
    } catch (e) {
      print('设置端口转发失败: $e');
      // 不抛出异常，继续执行
    }
  }

  /// 启动scrcpy服务器
  Future<void> startScrcpyServer(ScrcpyOptions options) async {
    print('正在启动scrcpy服务器...');
    print('配置: $options');

    try {
      final args = options.toCommandLineArgs();

      final shellCommand =
          'CLASSPATH=$_devicePath app_process / com.genymobile.scrcpy.Server ${args.join(' ')}';

      print('执行命令: $shellCommand');

      AdbShellStream shellStream;

      try {
        shellStream = await KadbDart.executeShell(_connection, shellCommand.split(' ')[0], shellCommand.split(' ').sublist(1));
      } catch (e) {
        print('直接执行失败，尝试使用shell -c: $e');
        shellStream = await KadbDart.executeShell(_connection, 'sh', [
          '-c',
          shellCommand,
        ]);
      }

      print('scrcpy服务器启动成功！');
      _readServerOutput(shellStream);
    } catch (e) {
      print('启动scrcpy服务器失败: $e');
      rethrow;
    }
  }

  /// 读取服务器输出
  void _readServerOutput(AdbShellStream shellStream) {
    print('开始读取服务器输出...');

    var outputBuffer = StringBuffer();
    var lastOutputTime = DateTime.now();

    shellStream.stdout.listen(
      (data) {
        outputBuffer.write(data);
        lastOutputTime = DateTime.now();

        if (data.contains('INFO:') || data.contains('WARN:') || data.contains('ERROR:') ||
            data.contains('[server]') || data.contains('[device]')) {
          print('服务器: $data.trim()');
        } else if (data.length > 100 && !data.contains(RegExp(r'[a-zA-Z]'))) {
          print('🎥 接收到视频数据 (${data.length} 字节)');
        }

        if (outputBuffer.length > 1000) {
          outputBuffer.clear();
        }
      },
      onError: (error) {
        if (!error.toString().contains('TimeoutException')) {
          print('⚠️ 服务器输出异常: $error');
        }
      },
      onDone: () {
        print('📡 服务器输出流结束');
        print('💡 注意：scrcpy服务器可能正在等待客户端连接，这是正常状态');
      },
    );

    shellStream.stderr.listen(
      (data) {
        print('❌ 服务器错误: $data');
      },
      onError: (error) {
        if (!error.toString().contains('TimeoutException')) {
          print('⚠️ 读取服务器错误时出错: $error');
        }
      },
      onDone: () {
        print('⚠️ 服务器错误输出流结束');
      },
    );

    shellStream.exitCode.listen((exitCode) {
      if (exitCode != 0) {
        print('❌ 服务器异常退出，退出码: $exitCode');
      } else {
        print('✅ 服务器正常退出，退出码: $exitCode');
      }
    });

    Timer.periodic(Duration(seconds: 30), (timer) {
      final now = DateTime.now();
      final timeSinceLastOutput = now.difference(lastOutputTime);

      if (timeSinceLastOutput.inMinutes > 2) {
        print('💡 scrcpy服务器正在运行中... (最后输出: ${timeSinceLastOutput.inMinutes} 分钟前)');
        lastOutputTime = now;
      }
    });

    print('✅ 服务器输出监控已启动');
  }

  /// 完整的scrcpy启动流程
  Future<void> startScrcpy({
    String host = '100.123.66.1',
    int port = 5555,
    int localPort = 1234,
    ScrcpyOptions options = ScrcpyOptions.displayOnly,
    bool skipServerPush = false,
  }) async {
    try {
      print('开始scrcpy启动流程...');
      print('连接配置: $host:$port, 本地端口: $localPort');
      print('scrcpy配置: $options');

      // 1. 连接设备
      await connect(host: host, port: port);

      // 2. 推送scrcpy-server（可选）
      if (!skipServerPush) {
        await pushScrcpyServer();
      } else {
        print('⏭️ 跳过scrcpy-server推送步骤（测试模式）');
      }

      // 3. 设置端口转发
      await setupPortForwarding(localPort: localPort);

      // 4. 启动scrcpy服务器（可选）
      if (!skipServerPush) {
        await startScrcpyServer(options);

        print('🎉 scrcpy启动完成！');
        print('现在可以通过本地端口 $localPort 连接到scrcpy服务');
      } else {
        print('🎉 TCP转发测试完成！');
        print('端口 $localPort 已启动，可以测试连接');
      }
    } catch (e) {
      print('❌ 启动scrcpy失败: $e');
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

      // 直接关闭ADB连接（close()方法是同步的，不会造成阻塞）
      print('正在关闭ADB连接...');
      _connection.close();
      print('ADB连接已关闭');
    } catch (e) {
      print('关闭连接时出错: $e');
    }
  }
}

/// 主函数示例
Future<void> main() async {
  final scrcpy = ScrcpyIntegration('scrcpy/scrcpy-server');

  try {
    // 使用类型安全的配置选项
    const options = ScrcpyOptions(
      version: 3.1,
      tunnelForward: true,
      audio: false,
      control: false,
      cleanup: false,
      rawStream: true,
      maxSize: 1920,
    );

    // 启动scrcpy（完整模式：包含服务器推送）
    await scrcpy.startScrcpy(
      options: options,
      skipServerPush: false, // 完整模式，启动scrcpy服务器
    );

    // 等待用户测试端口转发
    print('\n🎉 TCP转发运行中，按 Ctrl+C 或 Enter键退出...');
    print('💡 提示：现在可以测试端口转发功能...\n');
    print('测试命令：');
    print('  - telnet localhost 1234');
    print('  - nc localhost 1234');
    print('  - curl localhost:1234');

    // 等待用户输入
    try {
      await for (String _ in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
        break; // 读取一行后退出
      }
    } catch (e) {
      // 如果输入处理失败，等待一段时间再退出
      print('输入处理异常，等待5秒后退出: $e');
      await Future.delayed(Duration(seconds: 5));
    }
  } catch (e) {
    print('错误: $e');
  } finally {
    print('\n🛑 正在关闭scrcpy连接...');
    await scrcpy.close();
    print('✅ scrcpy已退出');
  }
}


