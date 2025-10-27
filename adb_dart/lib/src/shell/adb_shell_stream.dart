/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:async';
import 'dart:typed_data';
import '../stream/adb_stream.dart';
import 'adb_shell_response.dart';
import 'adb_shell_packet.dart';
import 'adb_shell_packet_v2.dart';

/// ADB Shell流，用于执行shell命令
class AdbShellStream {
  final AdbStream _stream;
  final StreamController<String> _stdoutController = StreamController<String>();
  final StreamController<String> _stderrController = StreamController<String>();
  final Completer<int> _exitCodeCompleter = Completer<int>();

  bool _isReading = false;

  AdbShellStream(this._stream) {
    _startReading();
  }

  /// 开始读取shell输出
  void _startReading() {
    _isReading = true;
    print('开始监听shell输出...');

    _stream.dataStream.listen(
      (data) {
        if (!_isReading) return;

        try {
          _processShellData(data);
        } catch (e) {
          print('处理shell数据时出错：$e');
          if (!_stderrController.isClosed) {
            _stderrController.addError(e);
          }
        }
      },
      onError: (error) {
        print('Shell流错误: $error');
        if (!_stdoutController.isClosed) {
          _stdoutController.addError(error);
        }
        if (!_stderrController.isClosed) {
          _stderrController.addError(error);
        }
        if (!_exitCodeCompleter.isCompleted) {
          _exitCodeCompleter.complete(-1);
        }
      },
      onDone: () {
        print('Shell流结束');
        _stopReading();
        if (!_exitCodeCompleter.isCompleted) {
          _exitCodeCompleter.complete(0);
        }
      },
    );

    _stream.closeStream.listen((_) {
      print('Shell流关闭');
      _stopReading();
    });
  }

  /// 处理shell数据
  void _processShellData(Uint8List data) {
    if (data.isEmpty) {
      print('收到空数据');
      return;
    }

    print('处理shell数据，长度: ${data.length}');

    try {
      // 使用标准Shell数据包格式解析
      if (data.length < 5) {
        print('数据长度不足，无法解析Shell数据包');
        return;
      }

      final buffer = ByteData.sublistView(data);
      final id = buffer.getUint8(0);
      final length = buffer.getUint32(1, Endian.little);

      print('Shell数据包 - ID: $id, 长度: $length');

      // 验证数据包长度
      if (data.length != 5 + length) {
        print('数据包长度不匹配：期望 ${5 + length}，实际 ${data.length}');
        return;
      }

      // 获取载荷数据
      final payload = length > 0 ? data.sublist(5) : Uint8List(0);

      switch (id) {
        case AdbShellPacketV2.idStdout:
          final payloadStr = String.fromCharCodes(payload);
          print('STDOUT: $payloadStr');
          if (!_stdoutController.isClosed) {
            _stdoutController.add(payloadStr);
          }
          break;
        case AdbShellPacketV2.idStderr:
          final payloadStr = String.fromCharCodes(payload);
          print('STDERR: $payloadStr');
          if (!_stderrController.isClosed) {
            _stderrController.add(payloadStr);
          }
          break;
        case AdbShellPacketV2.idExit:
          if (length == 1 && payload.length == 1) {
            final exitCode = payload[0];
            print('EXIT: $exitCode');
            if (!_exitCodeCompleter.isCompleted) {
              _exitCodeCompleter.complete(exitCode);
            }
          } else {
            print('无效的退出数据包格式');
          }
          break;
        case AdbShellPacketV2.idCloseStdin:
          print('CLOSE_STDIN');
          break;
        case AdbShellPacketV2.idWindowSizeChange:
          if (length == 4 && payload.length == 4) {
            final widthBuffer = ByteData.sublistView(payload, 0, 2);
            final heightBuffer = ByteData.sublistView(payload, 2, 4);
            final width = widthBuffer.getUint16(0, Endian.little);
            final height = heightBuffer.getUint16(0, Endian.little);
            print('WINDOW_SIZE_CHANGE: ${width}x${height}');
          } else {
            print('窗口大小变更数据包格式错误');
          }
          break;
        default:
          print('未知的Shell数据包类型：$id');
          break;
      }
    } catch (e) {
      print('解析Shell数据包时出错：$e');
      if (!_stderrController.isClosed) {
        _stderrController.addError(e);
      }
    }
  }

  /// 停止读取
  void _stopReading() {
    _isReading = false;

    if (!_stdoutController.isClosed) {
      _stdoutController.close();
    }

    if (!_stderrController.isClosed) {
      _stderrController.close();
    }
  }

  /// 写入数据到shell（标准输入）
  Future<void> write(String data) async {
    if (_stream.isClosed) {
      throw StateError('Shell流已关闭');
    }

    try {
      print('向shell写入数据: ${data.length} 字节');
      
      // 构建标准输入数据包
      final bytes = data.codeUnits;
      final packetData = Uint8List(5 + bytes.length);
      final buffer = ByteData.sublistView(packetData);
      
      buffer.setUint8(0, AdbShellPacketV2.idStdin);
      buffer.setUint32(1, bytes.length, Endian.little);
      packetData.setAll(5, bytes);
      
      await _stream.write(packetData);
      print('数据写入完成');
    } catch (e) {
      print('写入shell数据失败: $e');
      rethrow;
    }
  }

  /// 关闭shell流
  Future<void> close() async {
    await _stream.close();
  }

  /// 读取所有输出
  Future<AdbShellResponse> readAll() async {
    final stdout = StringBuffer();
    final stderr = StringBuffer();

    // 收集stdout
    final stdoutSub = _stdoutController.stream.listen((data) {
      stdout.write(data);
    });

    // 收集stderr
    final stderrSub = _stderrController.stream.listen((data) {
      stderr.write(data);
    });

    // 等待退出码
    final exitCode = await _exitCodeCompleter.future;

    // 取消订阅
    await stdoutSub.cancel();
    await stderrSub.cancel();

    return AdbShellResponse(
      stdout: stdout.toString(),
      stderr: stderr.toString(),
      exitCode: exitCode,
    );
  }

  /// 标准输出流
  Stream<String> get stdoutStream => _stdoutController.stream;

  /// 标准错误流
  Stream<String> get stderrStream => _stderrController.stream;

  /// 退出码Future
  Future<int> get exitCode => _exitCodeCompleter.future;
}
