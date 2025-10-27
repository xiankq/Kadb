/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:async';
import 'dart:io';
import '../adb_client.dart';
import '../stream/adb_stream.dart';

/// TCP端口转发器
class TcpForwarder {
  final AdbClient _client;
  final int _hostPort;
  final int _targetPort;
  ServerSocket? _serverSocket;
  final List<ForwardingConnection> _connections = [];
  bool _isRunning = false;

  TcpForwarder(this._client, this._hostPort, this._targetPort);

  /// 启动端口转发
  Future<void> start() async {
    if (_isRunning) return;

    try {
      // 创建本地服务器
      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _hostPort,
      );
      _isRunning = true;

      print('TCP转发已启动：本地端口 $_hostPort -> 设备端口 $_targetPort');

      // 监听本地连接
      _serverSocket!.listen(
        (socket) {
          _handleLocalConnection(socket);
        },
        onError: (error) {
          print('本地服务器错误：$error');
        },
        onDone: () {
          print('本地服务器已关闭');
          _isRunning = false;
        },
      );

      // 向ADB服务器请求端口转发
      await _setupAdbForwarding();
    } catch (e) {
      _isRunning = false;
      throw Exception('启动TCP转发失败：$e');
    }
  }

  /// 设置ADB端口转发
  Future<void> _setupAdbForwarding() async {
    try {
      // 使用ADB的forward命令
      final result = await _client.shell(
        'forward tcp:$_hostPort tcp:$_targetPort',
      );

      if (!result.isSuccess) {
        throw Exception('ADB端口转发设置失败：${result.allOutput}');
      }

      print('ADB端口转发设置成功');
    } catch (e) {
      throw Exception('设置ADB端口转发失败：$e');
    }
  }

  /// 处理本地连接
  Future<void> _handleLocalConnection(Socket localSocket) async {
    print('接收到本地连接：${localSocket.remoteAddress}:${localSocket.remotePort}');

    try {
      // 打开到设备的连接
      final deviceStream = await _client.openStream('tcp:$_targetPort');

      final connection = ForwardingConnection(localSocket, deviceStream);
      _connections.add(connection);

      // 开始转发数据
      connection
          .startForwarding()
          .then((_) {
            _connections.remove(connection);
          })
          .catchError((error) {
            print('连接转发错误：$error');
            _connections.remove(connection);
          });
    } catch (e) {
      print('处理本地连接失败：$e');
      localSocket.close();
    }
  }

  /// 停止端口转发
  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;

    // 关闭所有活动连接
    for (final connection in List.from(_connections)) {
      await connection.close();
    }
    _connections.clear();

    // 关闭本地服务器
    await _serverSocket?.close();
    _serverSocket = null;

    // 移除ADB端口转发
    try {
      await _client.shell('forward --remove tcp:$_hostPort');
      print('ADB端口转发已移除');
    } catch (e) {
      print('移除ADB端口转发失败：$e');
    }

    print('TCP转发已停止');
  }

  /// 检查是否在运行
  bool get isRunning => _isRunning;

  /// 获取活动连接数
  int get activeConnections => _connections.length;
}

/// 转发连接
class ForwardingConnection {
  final Socket _localSocket;
  final AdbStream _deviceStream;
  bool _isRunning = false;

  ForwardingConnection(this._localSocket, this._deviceStream);

  /// 开始转发数据
  Future<void> startForwarding() async {
    _isRunning = true;

    try {
      // 本地到设备的转发
      final localToDevice = _forwardLocalToDevice();

      // 设备到本地的转发
      final deviceToLocal = _forwardDeviceToLocal();

      // 等待任意一个方向完成
      await Future.any([localToDevice, deviceToLocal]);
    } catch (e) {
      print('转发错误：$e');
    } finally {
      await close();
    }
  }

  /// 本地到设备的数据转发
  Future<void> _forwardLocalToDevice() async {
    try {
      await for (final data in _localSocket) {
        if (!_isRunning) break;

        await _deviceStream.write(data);
      }
    } catch (e) {
      if (_isRunning) {
        print('本地到设备转发错误：$e');
      }
    }
  }

  /// 设备到本地的数据转发
  Future<void> _forwardDeviceToLocal() async {
    try {
      await for (final data in _deviceStream.dataStream) {
        if (!_isRunning) break;

        _localSocket.add(data);
        await _localSocket.flush();
      }
    } catch (e) {
      if (_isRunning) {
        print('设备到本地转发错误：$e');
      }
    }
  }

  /// 关闭连接
  Future<void> close() async {
    _isRunning = false;

    try {
      await _localSocket.close();
    } catch (e) {
      // 忽略关闭错误
    }

    try {
      await _deviceStream.close();
    } catch (e) {
      // 忽略关闭错误
    }
  }
}
