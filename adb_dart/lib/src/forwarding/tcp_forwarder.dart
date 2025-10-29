/// TCP端口转发实现
///
/// 提供本地端口到设备端口的转发功能
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb_dart/adb_dart.dart';

import '../debug/logging.dart';
import '../stream/adb_stream.dart';

/// TCP转发器状态
enum TcpForwarderState {
  starting,
  started,
  stopping,
  stopped,
}

/// TCP端口转发器
class TcpForwarder implements AutoCloseable {
  final Kadb _kadb;
  final int _hostPort;
  final int _targetPort;

  TcpForwarderState _state = TcpForwarderState.stopped;
  ServerSocket? _server;
  final List<Socket> _clientSockets = [];
  final List<AdbStream> _adbStreams = [];
  Timer? _cleanupTimer;

  TcpForwarder({
    required Kadb kadb,
    required int hostPort,
    required int targetPort,
  })  : _kadb = kadb,
        _hostPort = hostPort,
        _targetPort = targetPort;

  /// 启动端口转发
  Future<void> start() async {
    if (_state != TcpForwarderState.stopped) {
      throw StateError('转发器已在端口$_hostPort上启动');
    }

    _transitionState(TcpForwarderState.starting);

    try {
      // 创建本地服务器
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _hostPort);
      _transitionState(TcpForwarderState.started);

      print('TCP端口转发已启动: 本地端口$_hostPort -> 设备端口$_targetPort');

      // 监听客户端连接
      _server!.listen(
        _handleClientConnection,
        onError: (error) {
          print('服务器错误: $error');
          if (_state != TcpForwarderState.stopping) {
            _transitionState(TcpForwarderState.stopped);
          }
        },
        onDone: () {
          if (_state != TcpForwarderState.stopping) {
            _transitionState(TcpForwarderState.stopped);
          }
        },
      );

      // 启动清理定时器
      _startCleanupTimer();
    } catch (e) {
      _transitionState(TcpForwarderState.stopped);
      throw StateError('启动TCP端口转发失败: $e');
    }
  }

  /// 处理客户端连接
  Future<void> _handleClientConnection(Socket client) async {
    if (_state != TcpForwarderState.started) {
      client.close();
      return;
    }

    _clientSockets.add(client);
    print('新客户端连接: ${client.remoteAddress.address}:${client.remotePort}');

    try {
      // 打开到设备的ADB流
      final adbStream = await _kadb.openStream('tcp:$_targetPort');
      _adbStreams.add(adbStream);

      // 创建双向转发任务
      final forwardTasks = [
        _forwardClientToDevice(client, adbStream),
        _forwardDeviceToClient(client, adbStream),
      ];

      // 等待任一任务完成或出错
      try {
        await Future.any(forwardTasks);
      } catch (e) {
        print('转发错误: $e');
      } finally {
        // 关闭连接
        await _closeConnection(client, adbStream);
      }
    } catch (e) {
      print('打开ADB流失败: $e');
      client.close();
      _clientSockets.remove(client);
    }
  }

  /// 转发客户端数据到设备
  Future<void> _forwardClientToDevice(
      Socket client, AdbStream adbStream) async {
    try {
      await for (final data in client) {
        if (data.isNotEmpty) {
          await adbStream.write(data);
        }
      }
    } catch (e) {
      if (e is! SocketException) {
        print('客户端到设备转发错误: $e');
      }
    }
  }

  /// 转发设备数据到客户端
  Future<void> _forwardDeviceToClient(
      Socket client, AdbStream adbStream) async {
    try {
      while (true) {
        final data = await adbStream.read();
        if (data == null || data.isEmpty) {
          break;
        }

        client.add(data);
        await client.flush();
      }
    } catch (e) {
      if (e is! SocketException) {
        print('设备到客户端转发错误: $e');
      }
    }
  }

  /// 关闭单个连接
  Future<void> _closeConnection(Socket client, AdbStream adbStream) async {
    try {
      await adbStream.close();
    } catch (e) {
      print('关闭ADB流错误: $e');
    }

    try {
      client.close();
    } catch (e) {
      print('关闭客户端连接错误: $e');
    }

    _clientSockets.remove(client);
    _adbStreams.remove(adbStream);

    print('连接已关闭');
  }

  /// 启动清理定时器
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _cleanupClosedConnections();
    });
  }

  /// 清理已关闭的连接
  void _cleanupClosedConnections() {
    // 移除已关闭的客户端连接
    _clientSockets.removeWhere((socket) {
      if (socket.isBroadcast || socket.isClosed) {
        return true;
      }
      return false;
    });

    // 移除已关闭的ADB流
    _adbStreams.removeWhere((stream) {
      try {
        // 检查流是否还可用
        return stream.isClosed;
      } catch (e) {
        return true; // 如果检查出错，认为流已关闭
      }
    });

    print('清理完成 - 活跃连接: ${_clientSockets.length}, ADB流: ${_adbStreams.length}');
  }

  /// 转换状态
  void _transitionState(TcpForwarderState newState) {
    print('状态转换: ${_state.name} -> ${newState.name}');
    _state = newState;
  }

  /// 等待指定状态
  Future<void> _waitForState(
    TcpForwarderState targetState, {
    Duration timeout = const Duration(seconds: 5),
    Duration checkInterval = const Duration(milliseconds: 100),
  }) async {
    final stopwatch = Stopwatch()..start();

    while (_state != targetState) {
      if (stopwatch.elapsed > timeout) {
        throw TimeoutException('等待状态$targetState超时');
      }

      await Future.delayed(checkInterval);
    }
  }

  @override
  void close() async {
    if (_state == TcpForwarderState.stopping ||
        _state == TcpForwarderState.stopped) {
      return;
    }

    print('正在停止TCP端口转发...');
    _transitionState(TcpForwarderState.stopping);

    try {
      // 停止清理定时器
      _cleanupTimer?.cancel();
      _cleanupTimer = null;

      // 关闭服务器
      await _server?.close();
      _server = null;

      // 关闭所有客户端连接
      for (final client in _clientSockets.toList()) {
        try {
          client.close();
        } catch (e) {
          print('关闭客户端连接错误: $e');
        }
      }
      _clientSockets.clear();

      // 关闭所有ADB流
      for (final stream in _adbStreams.toList()) {
        try {
          await stream.close();
        } catch (e) {
          print('关闭ADB流错误: $e');
        }
      }
      _adbStreams.clear();

      // 等待状态转换完成
      await _waitForState(TcpForwarderState.stopped,
          timeout: Duration(seconds: 10));

      print('TCP端口转发已停止');
    } catch (e) {
      print('停止TCP端口转发时出错: $e');
      _transitionState(TcpForwarderState.stopped);
    }
  }

  /// 获取当前状态
  TcpForwarderState get state => _state;

  /// 获取本地端口
  int get hostPort => _hostPort;

  /// 获取目标端口
  int get targetPort => _targetPort;

  /// 获取活跃连接数
  int get activeConnections => _clientSockets.length;

  /// 检查是否正在运行
  bool get isRunning => _state == TcpForwarderState.started;
}

/// 自动关闭接口
abstract class AutoCloseable {
  void close();
}
