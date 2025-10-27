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

    // 使用正确的Shell数据包解析
    final packet = AdbShellPacketFactory.parseFromData(data);
    if (packet == null) {
      print('无法解析shell数据包');
      return;
    }

    print('解析到数据包: ${packet.runtimeType}');

    switch (packet.id) {
      case AdbShellPacketV2.idStdout:
        if (packet is StdOutPacket) {
          final payloadStr = String.fromCharCodes(packet.payload);
          print('STDOUT: $payloadStr');
          if (!_stdoutController.isClosed) {
            _stdoutController.add(payloadStr);
          }
        }
        break;
      case AdbShellPacketV2.idStderr:
        if (packet is StdErrorPacket) {
          final payloadStr = String.fromCharCodes(packet.payload);
          print('STDERR: $payloadStr');
          if (!_stderrController.isClosed) {
            _stderrController.add(payloadStr);
          }
        }
        break;
      case AdbShellPacketV2.idExit:
        if (packet is ExitPacket) {
          print('EXIT: ${packet.exitCode}');
          if (!_exitCodeCompleter.isCompleted) {
            _exitCodeCompleter.complete(packet.exitCode);
          }
        }
        break;
      case AdbShellPacketV2.idCloseStdin:
        print('CLOSE_STDIN');
        break;
      case AdbShellPacketV2.idWindowSizeChange:
        if (packet is WindowSizeChangePacket) {
          print('WINDOW_SIZE_CHANGE: ${packet.width}x${packet.height}');
        }
        break;
      default:
        print('未知的Shell数据包类型：${packet.id}');
        break;
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

  /// 写入数据到shell（如果支持）
  Future<void> write(String data) async {
    if (_stream.isClosed) {
      throw StateError('Shell流已关闭');
    }

    // 创建标准输入数据包
    final packet = AdbShellPacketFactory.createStdin(data);
    final packetData = Uint8List(packet.payload.length + 1);
    packetData[0] = packet.id;
    packetData.setAll(1, packet.payload);

    await _stream.write(packetData);
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
