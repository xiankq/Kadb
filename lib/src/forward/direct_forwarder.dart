import 'dart:async';
import 'dart:typed_data';
import '../core/adb_connection.dart';
import '../stream/adb_stream.dart';

/// 连接状态枚举
enum ConnectionState { connecting, connected, disconnecting, disconnected }

/// 直接TCP连接器，直接连接到ADB设备的端口
class DirectForwarder {
  final AdbConnection _connection;
  final String _destination;
  final bool _debug;

  ConnectionState _state = ConnectionState.disconnected;
  AdbStream? _stream;
  final StreamController<Uint8List> _dataController =
      StreamController.broadcast();
  final StreamController<void> _closeController = StreamController.broadcast();

  DirectForwarder(this._connection, this._destination, {bool debug = false})
    : _debug = debug;

  /// 连接到目标端口
  Future<void> connect() async {
    if (_state != ConnectionState.disconnected) {
      throw StateError('连接已存在');
    }

    _state = ConnectionState.connecting;

    try {
      _stream = await _connection.open(_destination);
      await _stream!.waitForRemoteId();
      _state = ConnectionState.connected;

      _startReading();

      if (_debug) {
        print('直接TCP连接已建立: $_destination');
      }
    } catch (e) {
      _state = ConnectionState.disconnected;
      rethrow;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    if (_state == ConnectionState.disconnected) return;

    _state = ConnectionState.disconnecting;

    try {
      await _stream?.close();
      _stream = null;
    } catch (e) {
      if (_debug) {
        print('断开连接时出错: $e');
      }
    } finally {
      _state = ConnectionState.disconnected;
      _closeController.add(null);
      await _closeController.close();
    }

    if (_debug) {
      print('直接TCP连接已断开: $_destination');
    }
  }

  /// 写入数据
  Future<void> write(List<int> data) async {
    if (_state != ConnectionState.connected || _stream == null) {
      throw StateError('连接未建立');
    }

    try {
      await _stream!.sink.writeBytes(Uint8List.fromList(data));
      await _stream!.sink.flush();
    } catch (e) {
      if (_debug) {
        print('写入数据失败: $e');
      }
      rethrow;
    }
  }

  /// 写入字符串数据
  Future<void> writeString(String data) async {
    write(data.codeUnits);
  }

  /// 开始读取数据
  void _startReading() {
    if (_stream == null) return;

    _stream!.source.stream.listen(
      (data) {
        _dataController.add(Uint8List.fromList(data));
        if (_debug) {
          print('接收到数据: ${data.length} 字节');
        }
      },
      onError: (error) {
        if (_debug) {
          print('读取数据时出错: $error');
        }
        _dataController.addError(error);
        disconnect();
      },
      onDone: () {
        if (_debug) {
          print('数据流已结束');
        }
        _dataController.close();
        disconnect();
      },
    );
  }

  /// 获取数据流
  Stream<Uint8List> get dataStream => _dataController.stream;

  /// 获取连接关闭事件流
  Stream<void> get closeStream => _closeController.stream;

  /// 检查是否已连接
  bool get isConnected => _state == ConnectionState.connected;

  /// 获取连接状态
  ConnectionState get state => _state;

  /// 获取目标地址
  String get destination => _destination;

  /// 获取底层ADB流（用于扩展功能）
  AdbStream? get adbStream => _stream;
}
