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
  
  bool _isClosed = false;
  
  AdbShellStream._(this._adbStream) {
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
  /// 返回AdbShellStream实例
  static Future<AdbShellStream> execute(
    AdbConnection connection,
    String command, [
    List<String> args = const [],
  ]) async {
    final fullCommand = _buildCommandString(command, args);
    final stream = await connection.open('shell,v2,raw:$fullCommand');
    return AdbShellStream._(stream);
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
    
    // Shell v2协议格式：
    // 第一个字节表示数据类型：
    // 0: stdout
    // 1: stderr  
    // 2: exit code
    final type = data[0];
    final payload = data.sublist(1);
    
    try {
      switch (type) {
        case 0: // stdout
          _stdoutController.add(utf8.decode(payload));
          break;
        case 1: // stderr
          _stderrController.add(utf8.decode(payload));
          break;
        case 2: // exit code
          if (payload.isNotEmpty) {
            final exitCode = int.parse(utf8.decode(payload));
            _exitCodeController.add(exitCode);
          }
          break;
        default:
          print('警告：未知的Shell数据类型: $type');
      }
    } catch (e) {
      print('处理Shell数据时出错: $e');
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