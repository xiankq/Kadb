/// Shell v2流实现
/// 支持交互式Shell和标准I/O分离
library shell_stream;

import 'dart:async';
import 'dart:typed_data';
import 'adb_shell_packet_v2.dart';
import 'adb_shell_response.dart';
import '../stream/adb_stream.dart';
import '../exception/adb_exceptions.dart';

/// Shell流控制器
class AdbShellStream {
  final AdbStream _stream;
  final StreamController<AdbShellPacket> _packetController =
      StreamController<AdbShellPacket>();
  final StreamController<String> _stdoutController = StreamController<String>();
  final StreamController<String> _stderrController = StreamController<String>();
  final Completer<int> _exitCodeCompleter = Completer<int>();

  bool _isClosed = false;
  final AdbShellResponseBuilder _responseBuilder = AdbShellResponseBuilder();

  AdbShellStream(this._stream) {
    _startPacketListening();
  }

  /// 标准输出流
  Stream<String> get stdoutStream => _stdoutController.stream;

  /// 标准错误流
  Stream<String> get stderrStream => _stderrController.stream;

  /// 退出码Future
  Future<int> get exitCode => _exitCodeCompleter.future;

  /// 是否已关闭
  bool get isClosed => _isClosed;

  /// 写入标准输入
  Future<void> writeInput(String input) async {
    if (_isClosed) {
      throw AdbStreamClosed();
    }

    final data = Uint8List.fromList(input.codeUnits);
    await _writePacket(AdbShellPacketV2.idStdin, data);
  }

  /// 写入字节数据到标准输入
  Future<void> writeInputBytes(Uint8List data) async {
    if (_isClosed) {
      throw AdbStreamClosed();
    }

    await _writePacket(AdbShellPacketV2.idStdin, data);
  }

  /// 关闭标准输入
  Future<void> closeStdin() async {
    if (_isClosed) {
      return;
    }

    await _writePacket(AdbShellPacketV2.idCloseStdin, null);
  }

  /// 发送窗口大小改变
  Future<void> sendWindowSizeChange(
      int rows, int cols, int xpixel, int ypixel) async {
    if (_isClosed) {
      throw AdbStreamClosed();
    }

    final buffer = ByteData(16);
    buffer.setUint32(0, rows, Endian.little);
    buffer.setUint32(4, cols, Endian.little);
    buffer.setUint32(8, xpixel, Endian.little);
    buffer.setUint32(12, ypixel, Endian.little);

    await _writePacket(
        AdbShellPacketV2.idWindowSizeChange, buffer.buffer.asUint8List());
  }

  /// 读取所有输出（阻塞直到命令完成）
  Future<AdbShellResponse> readAll() async {
    // 等待退出码
    final exitCode = await _exitCodeCompleter.future;
    return _responseBuilder.build();
  }

  /// 读取单个包
  Future<AdbShellPacket?> readPacket() async {
    try {
      final packetData = await _stream.dataStream.first;
      return _parsePacket(packetData);
    } catch (e) {
      if (_isClosed) {
        return null;
      }
      throw AdbStreamException('读取包失败: $e');
    }
  }

  /// 写入数据包
  Future<void> _writePacket(int id, Uint8List? data) async {
    final packet = Uint8List(5 + (data?.length ?? 0));
    final buffer = ByteData.view(packet.buffer);

    // 包ID (1字节)
    buffer.setUint8(0, id);

    // 数据长度 (4字节，小端序)
    buffer.setUint32(1, data?.length ?? 0, Endian.little);

    // 数据内容
    if (data != null) {
      packet.setAll(5, data);
    }

    await _stream.write(packet);
  }

  /// 解析数据包
  AdbShellPacket? _parsePacket(Uint8List data) {
    if (data.length < 5) {
      return null;
    }

    final buffer = ByteData.view(data.buffer);
    final id = buffer.getUint8(0);
    final length = buffer.getUint32(1, Endian.little);

    Uint8List? payload;
    if (length > 0) {
      if (data.length < 5 + length) {
        return null;
      }
      payload = data.sublist(5, 5 + length);
    }

    switch (id) {
      case AdbShellPacketV2.idStdout:
        return StdOutPacket(payload ?? Uint8List(0));

      case AdbShellPacketV2.idStderr:
        return StdErrPacket(payload ?? Uint8List(0));

      case AdbShellPacketV2.idExit:
        return ExitPacket(payload ?? Uint8List(0));

      case AdbShellPacketV2.idStdin:
        return StdInPacket(payload ?? Uint8List(0));

      case AdbShellPacketV2.idCloseStdin:
        return CloseStdInPacket();

      case AdbShellPacketV2.idWindowSizeChange:
        return WindowSizeChangePacket(payload ?? Uint8List(0));

      default:
        return null;
    }
  }

  /// 开始监听数据包
  void _startPacketListening() {
    _stream.dataStream.listen(
      (data) {
        final packet = _parsePacket(data);
        if (packet != null) {
          _handlePacket(packet);
        }
      },
      onError: (error) {
        if (!_isClosed) {
          _packetController.addError(error);
        }
      },
      onDone: () {
        if (!_isClosed) {
          _packetController.close();
        }
      },
    );
  }

  /// 处理接收到的包
  void _handlePacket(AdbShellPacket packet) {
    _packetController.add(packet);

    switch (packet.id) {
      case AdbShellPacketV2.idStdout:
        if (packet is StdOutPacket) {
          _responseBuilder.addOutput(packet.content);
          _stdoutController.add(packet.content);
        }
        break;

      case AdbShellPacketV2.idStderr:
        if (packet is StdErrPacket) {
          _responseBuilder.addErrorOutput(packet.content);
          _stderrController.add(packet.content);
        }
        break;

      case AdbShellPacketV2.idExit:
        if (packet is ExitPacket) {
          final exitCode = packet.exitCode;
          _responseBuilder.setExitCode(exitCode);
          if (!_exitCodeCompleter.isCompleted) {
            _exitCodeCompleter.complete(exitCode);
          }
        }
        break;
    }
  }

  /// 关闭流
  Future<void> close() async {
    if (_isClosed) {
      return;
    }

    _isClosed = true;

    // 关闭控制器
    await _packetController.close();
    await _stdoutController.close();
    await _stderrController.close();

    // 如果还没有设置退出码，设置一个默认值
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(-1);
    }

    // 关闭底层流
    await _stream.close();
  }
}
