import 'dart:async';
import 'dart:io';
import 'direct_forwarder.dart';
import '../core/adb_connection.dart';

/// TCP转发器，基于DirectForwarder实现端口转发功能
class TcpForwarder {
  final AdbConnection _connection;
  final int _hostPort;
  final String _destination;
  final bool _debug;

  ConnectionState _state = ConnectionState.disconnected;
  ServerSocket? _server;
  final Map<Socket, DirectForwarder> _clientConnections = {};

  TcpForwarder(
    this._connection,
    this._hostPort,
    this._destination, {
    bool debug = false,
  }) : _debug = debug;

  /// 启动转发
  Future<void> start() async {
    if (_state != ConnectionState.disconnected) {
      throw StateError('转发器已启动');
    }

    _state = ConnectionState.connecting;

    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _hostPort);
      _state = ConnectionState.connected;

      _server!.listen(_handleClient, onError: _handleError);

      if (_debug) {
        print('TCP转发已启动: $_hostPort -> $_destination');
      }
    } catch (e) {
      _state = ConnectionState.disconnected;
      rethrow;
    }
  }

  /// 停止转发
  Future<void> stop() async {
    if (_state == ConnectionState.disconnected) return;

    _state = ConnectionState.disconnecting;

    // 关闭所有客户端连接
    final futures = _clientConnections.values.map((client) => client.disconnect());
    await Future.wait(futures, eagerError: false);
    _clientConnections.clear();

    await _server?.close();
    _server = null;
    _state = ConnectionState.disconnected;

    if (_debug) {
      print('TCP转发已停止: $_hostPort');
    }
  }

  /// 处理客户端连接
  Future<void> _handleClient(Socket client) async {
    try {
      // 为每个客户端连接创建一个DirectForwarder
      final forwarder = DirectForwarder(_connection, _destination, debug: _debug);
      await forwarder.connect();
      
      _clientConnections[client] = forwarder;

      // 设置双向数据转发
      _setupBidirectionalForwarding(client, forwarder);

      // 监听连接关闭
      forwarder.closeStream.listen((_) {
        _clientConnections.remove(client);
        client.close();
      });

      client.done.then((_) {
        forwarder.disconnect();
        _clientConnections.remove(client);
      });
    } catch (e) {
      if (_debug) {
        print('客户端连接处理失败: $e');
      }
      await client.close();
    }
  }

  /// 建立双向数据转发
  void _setupBidirectionalForwarding(Socket client, DirectForwarder forwarder) {
    // 从客户端转发到ADB设备
    client.listen(
      (data) {
        forwarder.write(data);
      },
      onError: (error) {
        if (_debug) {
          print('客户端到ADB转发错误: $error');
        }
        forwarder.disconnect();
      },
      onDone: () {
        forwarder.disconnect();
      },
    );

    // 从ADB设备转发到客户端
    forwarder.dataStream.listen(
      (data) {
        client.add(data);
      },
      onError: (error) {
        if (_debug) {
          print('ADB到客户端转发错误: $error');
        }
        client.close();
      },
      onDone: () {
        client.close();
      },
    );
  }

  /// 处理错误
  void _handleError(Object error) {
    if (_debug) {
      print('转发器错误: $error');
    }
    if (_state == ConnectionState.connected) {
      _state = ConnectionState.disconnected;
    }
  }

  /// 检查是否正在运行
  bool get isRunning => _state == ConnectionState.connected;

  /// 获取本地端口
  int get hostPort => _hostPort;

  /// 获取目标服务
  String get destination => _destination;

  /// 获取活跃连接数
  int get activeConnections => _clientConnections.length;
}