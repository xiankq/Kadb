import 'dart:async';
import 'dart:io';
import '../core/adb_connection.dart';
import '../stream/adb_stream.dart';

/// TCP转发器状态枚举
enum ForwarderState { starting, started, stopping, stopped }

/// 转发管理器，统一管理TCP转发功能
class ForwardingManager {
  final AdbConnection _connection;
  final Map<int, TcpForwarder> _forwarders = {};
  final bool _debug;

  ForwardingManager(this._connection, {bool debug = false}) : _debug = debug;

  /// 启动TCP转发
  Future<TcpForwarder> startForwarding(int hostPort, String destination) async {
    if (_forwarders.containsKey(hostPort)) {
      throw StateError('端口 $hostPort 已被占用');
    }

    final forwarder = TcpForwarder(
      _connection,
      hostPort,
      destination,
      debug: _debug,
    );
    await forwarder.start();
    _forwarders[hostPort] = forwarder;
    return forwarder;
  }

  /// 停止TCP转发
  Future<void> stopForwarding(int hostPort) async {
    final forwarder = _forwarders.remove(hostPort);
    if (forwarder != null) {
      await forwarder.stop();
    }
  }

  /// 停止所有转发
  Future<void> stopAll() async {
    final futures = _forwarders.values.map((f) => f.stop()).toList();
    await Future.wait(futures, eagerError: false);
    _forwarders.clear();
  }

  /// 获取活跃的转发器数量
  int get activeCount => _forwarders.length;

  /// 获取所有活跃的转发器端口
  List<int> get activePorts => _forwarders.keys.toList();
}

/// 简化的TCP转发器
class TcpForwarder {
  final AdbConnection _connection;
  final int _hostPort;
  final String _destination;
  final bool _debug;

  ForwarderState _state = ForwarderState.stopped;
  ServerSocket? _server;

  TcpForwarder(
    this._connection,
    this._hostPort,
    this._destination, {
    bool debug = false,
  }) : _debug = debug;

  /// 启动转发
  Future<void> start() async {
    if (_state != ForwarderState.stopped) {
      throw StateError('转发器已启动');
    }

    _state = ForwarderState.starting;

    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _hostPort);
      _state = ForwarderState.started;

      _server!.listen(_handleClient, onError: _handleError);

      if (_debug) {
        print('TCP转发已启动: $_hostPort -> $_destination');
      }
    } catch (e) {
      _state = ForwarderState.stopped;
      rethrow;
    }
  }

  /// 停止转发
  Future<void> stop() async {
    if (_state == ForwarderState.stopped) return;

    _state = ForwarderState.stopping;
    await _server?.close();
    _server = null;
    _state = ForwarderState.stopped;

    if (_debug) {
      print('TCP转发已停止: $_hostPort');
    }
  }

  /// 处理客户端连接
  Future<void> _handleClient(Socket client) async {
    AdbStream? stream;
    try {
      stream = await _connection.open(_destination);
      await stream.waitForRemoteId();

      await _setupForwarding(client, stream);
    } catch (e) {
      if (_debug) {
        print('连接处理失败: $e');
      }
      await client.close();
      await stream?.close();
    }
  }

  /// 建立双向转发
  Future<void> _setupForwarding(Socket client, AdbStream stream) async {
    final clientToAdb = _forwardToStream(client, stream.sink);
    final adbToClient = _forwardFromStream(stream.source, client);

    await Future.any([clientToAdb, adbToClient]);
    await client.close();
    await stream.close();
  }

  /// 从Socket转发到ADB流
  Future<void> _forwardToStream(Socket source, dynamic sink) async {
    try {
      await for (final data in source) {
        await sink.writeBytes(data);
        await sink.flush();
      }
    } catch (e) {
      // 连接正常关闭
    }
  }

  /// 从ADB流转发的Socket
  Future<void> _forwardFromStream(dynamic source, Socket sink) async {
    try {
      await for (final data in source.stream) {
        sink.add(data);
        await sink.flush();
      }
    } catch (e) {
      // 连接正常关闭
    }
  }

  /// 处理错误
  void _handleError(Object error) {
    if (_debug) {
      print('转发器错误: $error');
    }
    if (_state == ForwarderState.started) {
      _state = ForwarderState.stopped;
    }
  }

  /// 检查是否正在运行
  bool get isRunning => _state == ForwarderState.started;

  /// 获取本地端口
  int get hostPort => _hostPort;

  /// 获取目标服务
  String get destination => _destination;
}
