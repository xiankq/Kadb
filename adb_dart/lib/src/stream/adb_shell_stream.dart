/// Shell流实现
///
/// 实现ADB Shell v2协议，支持标准输入、标准输出、标准错误和退出码
library;

import 'dart:async';
import 'dart:typed_data';

import 'adb_stream.dart';
import '../shell/adb_shell_response.dart';

/// Shell v2协议包类型
class AdbShellPacketType {
  /// 标准输入
  static const int stdin = 0;

  /// 标准输出
  static const int stdout = 1;

  /// 标准错误
  static const int stderr = 2;

  /// 退出码
  static const int exit = 3;

  /// 关闭标准输入
  static const int closeStdin = 4;

  /// 窗口大小变更
  static const int windowSizeChange = 5;

  /// 无效包
  static const int invalid = 6;
}

/// Shell数据包
abstract class AdbShellPacket {
  /// 包类型
  int get type;

  /// 载荷数据
  Uint8List get payload;

  /// 标准输出包
  factory AdbShellPacket.stdout(Uint8List data) => _StdoutPacket(data);

  /// 标准错误包
  factory AdbShellPacket.stderr(Uint8List data) => _StderrPacket(data);

  /// 退出码包
  factory AdbShellPacket.exit(int exitCode) => _ExitPacket(exitCode);

  /// 标准输入包
  factory AdbShellPacket.stdin(Uint8List data) => _StdinPacket(data);

  /// 从字节数据解析包
  factory AdbShellPacket.fromBytes(Uint8List data) {
    if (data.length < 5) {
      throw ArgumentError('Shell包数据长度不足');
    }

    final type = data[0] & 0xFF;
    final length = _readInt32(data, 1);

    if (data.length < 5 + length) {
      throw ArgumentError('Shell包数据长度不匹配');
    }

    final payload = data.sublist(5, 5 + length);

    switch (type) {
      case AdbShellPacketType.stdout:
        return AdbShellPacket.stdout(payload);
      case AdbShellPacketType.stderr:
        return AdbShellPacket.stderr(payload);
      case AdbShellPacketType.exit:
        if (payload.length != 1) {
          throw ArgumentError('退出码包载荷长度必须为1');
        }
        return AdbShellPacket.exit(payload[0] & 0xFF);
      case AdbShellPacketType.stdin:
        return AdbShellPacket.stdin(payload);
      default:
        throw ArgumentError('不支持的Shell包类型: $type');
    }
  }

  /// 转换为字节数据
  Uint8List toBytes() {
    final result = BytesBuilder();
    result.addByte(type);
    result.add(_writeInt32(payload.length));
    result.add(payload);
    return result.toBytes();
  }
}

/// 标准输出包
class _StdoutPacket implements AdbShellPacket {
  @override
  final Uint8List payload;

  _StdoutPacket(this.payload);

  @override
  int get type => AdbShellPacketType.stdout;
}

/// 标准错误包
class _StderrPacket implements AdbShellPacket {
  @override
  final Uint8List payload;

  _StderrPacket(this.payload);

  @override
  int get type => AdbShellPacketType.stderr;
}

/// 退出码包
class _ExitPacket implements AdbShellPacket {
  final int exitCode;

  _ExitPacket(this.exitCode);

  @override
  int get type => AdbShellPacketType.exit;

  @override
  Uint8List get payload => Uint8List.fromList([exitCode]);
}

/// 标准输入包
class _StdinPacket implements AdbShellPacket {
  @override
  final Uint8List payload;

  _StdinPacket(this.payload);

  @override
  int get type => AdbShellPacketType.stdin;
}

/// Shell流实现
class AdbShellStream {
  final AdbStream _stream;
  final StreamController<AdbShellPacket> _packetController =
      StreamController<AdbShellPacket>();
  final StreamController<String> _stdoutController = StreamController<String>();
  final StreamController<String> _stderrController = StreamController<String>();

  bool _isClosed = false;
  int? _exitCode;
  final StringBuffer _stdoutBuffer = StringBuffer();
  final StringBuffer _stderrBuffer = StringBuffer();

  /// 构造函数
  AdbShellStream(this._stream) {
    _setupPacketHandling();
  }

  /// 设置包处理
  void _setupPacketHandling() {
    _stream.inputStream.listen(
      (data) {
        _handleIncomingData(data);
      },
      onError: (error) {
        _packetController.addError(error);
        _stdoutController.addError(error);
        _stderrController.addError(error);
      },
      onDone: () {
        _handleStreamClosed();
      },
    );
  }

  /// 处理输入数据
  void _handleIncomingData(Uint8List data) {
    try {
      final packet = AdbShellPacket.fromBytes(data);
      _handlePacket(packet);
    } catch (e) {
      // 忽略解析错误，可能是其他格式的数据
    }
  }

  /// 处理Shell包
  void _handlePacket(AdbShellPacket packet) {
    _packetController.add(packet);

    switch (packet.type) {
      case AdbShellPacketType.stdout:
        final text = String.fromCharCodes(packet.payload);
        _stdoutBuffer.write(text);
        _stdoutController.add(text);
        break;

      case AdbShellPacketType.stderr:
        final text = String.fromCharCodes(packet.payload);
        _stderrBuffer.write(text);
        _stderrController.add(text);
        break;

      case AdbShellPacketType.exit:
        _exitCode = packet.payload[0] & 0xFF;
        _handleStreamClosed();
        break;

      case AdbShellPacketType.stdin:
        // 通常不会收到stdin包
        break;

      default:
        // 忽略其他类型的包
        break;
    }
  }

  /// 处理流关闭
  void _handleStreamClosed() {
    if (_isClosed) return;
    _isClosed = true;

    _packetController.close();
    _stdoutController.close();
    _stderrController.close();
  }

  /// 写入标准输入
  Future<void> writeInput(String input) async {
    if (_isClosed) {
      throw StateError('Shell流已关闭');
    }

    final packet = AdbShellPacket.stdin(Uint8List.fromList(input.codeUnits));
    await _stream.write(packet.toBytes());
  }

  /// 写入字节数据到标准输入
  Future<void> writeInputBytes(Uint8List data) async {
    if (_isClosed) {
      throw StateError('Shell流已关闭');
    }

    final packet = AdbShellPacket.stdin(data);
    await _stream.write(packet.toBytes());
  }

  /// 关闭标准输入
  Future<void> closeInput() async {
    // 发送空数据包表示EOF
    await writeInputBytes(Uint8List(0));
  }

  /// 读取所有输出直到退出
  Future<AdbShellResponse> readAll() async {
    await for (final packet in _packetController.stream) {
      if (packet.type == AdbShellPacketType.exit) {
        break;
      }
    }

    return AdbShellResponse(
      output: _stdoutBuffer.toString(),
      errorOutput: _stderrBuffer.toString(),
      exitCode: _exitCode ?? -1,
    );
  }

  /// 读取单个包
  Future<AdbShellPacket?> readPacket() async {
    try {
      return await _packetController.stream.first;
    } catch (e) {
      return null;
    }
  }

  /// 读取标准输出流
  Stream<String> get stdoutStream => _stdoutController.stream;

  /// 读取标准错误流
  Stream<String> get stderrStream => _stderrController.stream;

  /// 读取包流
  Stream<AdbShellPacket> get packetStream => _packetController.stream;

  /// 获取当前的标准输出内容
  String get stdoutContent => _stdoutBuffer.toString();

  /// 获取当前的标准错误内容
  String get stderrContent => _stderrBuffer.toString();

  /// 获取退出码
  int? get exitCode => _exitCode;

  /// 检查是否已退出
  bool get hasExited => _exitCode != null;

  /// 检查是否已关闭
  bool get isClosed => _isClosed;

  /// 关闭Shell流
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    await _stream.close();
    await _packetController.close();
    await _stdoutController.close();
    await _stderrController.close();
  }

  /// 清除缓冲区
  void clearBuffers() {
    _stdoutBuffer.clear();
    _stderrBuffer.clear();
  }
}

/// 读取32位整数（小端格式）
int _readInt32(Uint8List data, int offset) {
  return (data[offset] & 0xFF) |
      ((data[offset + 1] & 0xFF) << 8) |
      ((data[offset + 2] & 0xFF) << 16) |
      ((data[offset + 3] & 0xFF) << 24);
}

/// 写入32位整数（小端格式）
Uint8List _writeInt32(int value) {
  return Uint8List(4)
    ..[0] = value & 0xFF
    ..[1] = (value >> 8) & 0xFF
    ..[2] = (value >> 16) & 0xFF
    ..[3] = (value >> 24) & 0xFF;
}
