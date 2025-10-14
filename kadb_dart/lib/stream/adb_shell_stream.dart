import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:kadb_dart/core/adb_connection.dart';
import 'package:kadb_dart/stream/adb_stream.dart';

/// ADB Shell流类
/// 管理ADB协议的Shell命令执行
class AdbShellStream {
  final AdbStream _adbStream;
  final StreamController<String> _stdoutController = StreamController<String>.broadcast();
  final StreamController<String> _stderrController = StreamController<String>.broadcast();
  final StreamController<int> _exitCodeController = StreamController<int>.broadcast();
  final bool _debug;

  bool _isClosed = false;
  
  AdbShellStream._(this._adbStream, {bool debug = false}) : _debug = debug {
    _startReading();
  }
  
  /// 获取标准输出流
  Stream<String> get stdout => _stdoutController.stream;
  
  /// 获取标准错误流
  Stream<String> get stderr => _stderrController.stream;
  
  /// 获取退出码流
  Stream<int> get exitCode => _exitCodeController.stream;
  
  /// 执行Shell命令
  /// [command] Shell命令字符串
  /// [args] 命令参数列表
  /// [debug] 是否启用调试模式
  /// 返回AdbShellStream实例
  static Future<AdbShellStream> execute(
    AdbConnection connection,
    String command, [
    List<String> args = const [],
    bool debug = false,
  ]) async {
    final fullCommand = _buildCommandString(command, args);
    final stream = await connection.open('shell,v2,raw:$fullCommand');
    return AdbShellStream._(stream, debug: debug);
  }
  
  /// 写入数据到Shell输入
  /// [data] 要写入的数据
  Future<void> write(String data) async {
    if (_isClosed) {
      throw StateError('Shell流已关闭');
    }
    
    final bytes = utf8.encode(data);
    await _adbStream.write(Uint8List.fromList(bytes));
  }
  
  /// 读取所有标准输出内容
  /// 返回完整的输出字符串
  Future<String> readAll({Duration timeout = const Duration(seconds: 10)}) async {
    final output = StringBuffer();
    final completer = Completer<String>();

    // 监听输出流
    late StreamSubscription<String> subscription;
    subscription = stdout.listen(
      (data) {
        output.write(data);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(output.toString());
        }
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
    );

    // 设置超时
    Timer(timeout, () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.complete(output.toString());
      }
    });

    return completer.future;
  }

  /// 关闭Shell流
  Future<void> close() async {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    await _adbStream.close();
    await _stdoutController.close();
    await _stderrController.close();
    await _exitCodeController.close();
  }
  
  /// 开始读取Shell输出
  void _startReading() {
    _adbStream.dataStream.listen((data) {
      _processShellData(data);
    }, onError: (error) {
      if (!_isClosed) {
        _stdoutController.addError(error);
        _stderrController.addError(error);
        _close();
      }
    }, onDone: () {
      if (!_isClosed) {
        _close();
      }
    });
  }
  
  /// 处理Shell数据
  void _processShellData(Uint8List data) {
    if (data.isEmpty) {
      return;
    }

    // Shell v2协议格式（与Kotlin版本一致）：
    // 第一个字节表示数据类型：
    // 0: stdin
    // 1: stdout
    // 2: stderr
    // 3: exit code
    final type = data[0];
    final payload = data.sublist(1);

    try {
      switch (type) {
        case 0: // stdin（通常不接收）
          // 忽略stdin数据
          break;
        case 1: // stdout
          // 清理输出中的空字符和控制字符
          final decoded = utf8.decode(payload);
          final cleaned = decoded.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
          _stdoutController.add(cleaned);
          break;
        case 2: // stderr
          final decoded = utf8.decode(payload);
          final cleaned = decoded.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
          _stderrController.add(cleaned);
          break;
        case 3: // exit code
          if (payload.isNotEmpty) {
            final exitCode = payload[0]; // exit code是单个字节
            _exitCodeController.add(exitCode);
          }
          break;
        default:
          // 忽略未知类型的数据
          break;
      }
    } catch (e) {
      // 忽略处理数据时的错误
    }
  }
  
  /// 构建命令字符串
  static String _buildCommandString(String command, List<String> args) {
    final escapedArgs = args.map((arg) => _escapeShellArgument(arg)).toList();
    return '$command ${escapedArgs.join(' ')}'.trim();
  }
  
  /// 转义Shell参数
  static String _escapeShellArgument(String arg) {
    // 如果参数包含空格或特殊字符，需要转义
    if (arg.contains(' ') || arg.contains('\'') || arg.contains('"')) {
      return "'${arg.replaceAll("'", "'\\''")}'";
    }
    return arg;
  }
  
  /// 内部关闭方法
  void _close() {
    if (!_isClosed) {
      _isClosed = true;
      _stdoutController.close();
      _stderrController.close();
      _exitCodeController.close();
    }
  }
}