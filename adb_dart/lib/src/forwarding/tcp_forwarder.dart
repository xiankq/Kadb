/// TCP端口转发实现
/// 实现ADB的端口转发功能
library tcp_forwarder;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../stream/adb_stream.dart';
import '../exception/adb_exceptions.dart';

/// TCP端口转发器状态
enum TcpForwarderState {
  stopped,
  starting,
  started,
  stopping,
}

/// TCP端口转发器
class TcpForwarder {
  final int _hostPort;
  final int _targetPort;

  TcpForwarderState _state = TcpForwarderState.stopped;
  ServerSocket? _serverSocket;
  Timer? _acceptTimer;
  final List<Socket> _clientSockets = [];
  final Future<AdbStream> Function()? _streamCreator; // 流创建函数

  TcpForwarder({
    required int hostPort,
    required int targetPort,
    Future<AdbStream> Function()? streamCreator,
  })  : _hostPort = hostPort,
        _targetPort = targetPort,
        _streamCreator = streamCreator;

  /// 获取当前状态
  TcpForwarderState get state => _state;

  /// 是否已启动
  bool get isStarted => _state == TcpForwarderState.started;

  /// 是否已停止
  bool get isStopped => _state == TcpForwarderState.stopped;

  /// 启动端口转发
  Future<void> start() async {
    if (_state != TcpForwarderState.stopped) {
      throw AdbException('端口转发器已在端口 $_hostPort 上启动');
    }

    _state = TcpForwarderState.starting;

    try {
      // 创建本地服务器套接字
      _serverSocket =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, _hostPort);
      _serverSocket!.listen(_handleClient, onError: _handleError);

      _state = TcpForwarderState.started;
      print('TCP端口转发已启动: localhost:$_hostPort -> device:$_targetPort');

      // 定期检查连接状态
      _startHealthCheck();
    } catch (e) {
      _state = TcpForwarderState.stopped;
      throw AdbConnectionException('无法启动端口转发: $e');
    }
  }

  /// 停止端口转发
  Future<void> stop() async {
    if (_state == TcpForwarderState.stopped ||
        _state == TcpForwarderState.stopping) {
      return;
    }

    _state = TcpForwarderState.stopping;

    try {
      // 停止接受新连接
      _acceptTimer?.cancel();

      // 关闭所有客户端连接
      for (final client in _clientSockets) {
        try {
          await client.close();
        } catch (e) {
          // 忽略关闭错误
        }
      }
      _clientSockets.clear();

      // 关闭服务器套接字
      await _serverSocket?.close();
      _serverSocket = null;

      _state = TcpForwarderState.stopped;
      print('TCP端口转发已停止');
    } catch (e) {
      _state = TcpForwarderState.stopped;
      throw AdbException('停止端口转发时出错: $e');
    }
  }

  /// 处理新的客户端连接
  void _handleClient(Socket client) {
    if (_state != TcpForwarderState.started) {
      client.close();
      return;
    }

    _clientSockets.add(client);
    print('新的客户端连接: ${client.remoteAddress}:${client.remotePort}');

    // 创建到ADB设备的新流
    _createAdbStream().then((adbStream) {
      _setupBidirectionalForwarding(client, adbStream);
    }).catchError((error) {
      print('创建ADB流失败: $error');
      client.close();
      _clientSockets.remove(client);
    });
  }

  /// 创建ADB流（打开tcp连接）
  Future<AdbStream> _createAdbStream() async {
    // 使用外部注入的流创建函数
    if (_streamCreator != null) {
      return await _streamCreator!();
    }
    // 这里需要访问AdbConnection来打开新的流
    throw UnimplementedError('创建ADB流功能需要AdbConnection支持');
  }

  /// 设置双向转发
  void _setupBidirectionalForwarding(Socket client, AdbStream adbStream) {
    // 客户端 -> ADB设备
    client.listen(
      (data) async {
        try {
          await adbStream.write(data);
        } catch (e) {
          print('转发到ADB设备失败: $e');
          await _closeConnection(client, adbStream);
        }
      },
      onError: (error) async {
        print('客户端连接错误: $error');
        await _closeConnection(client, adbStream);
      },
      onDone: () async {
        print('客户端连接关闭');
        await _closeConnection(client, adbStream);
      },
    );

    // ADB设备 -> 客户端
    adbStream.dataStream.listen(
      (data) async {
        try {
          client.add(data);
          await client.flush();
        } catch (e) {
          print('转发到客户端失败: $e');
          await _closeConnection(client, adbStream);
        }
      },
      onError: (error) async {
        print('ADB流错误: $error');
        await _closeConnection(client, adbStream);
      },
      onDone: () async {
        print('ADB流关闭');
        await _closeConnection(client, adbStream);
      },
    );
  }

  /// 关闭连接
  Future<void> _closeConnection(Socket client, AdbStream adbStream) async {
    if (!_clientSockets.contains(client)) {
      return;
    }

    _clientSockets.remove(client);

    try {
      await client.close();
    } catch (e) {
      // 忽略关闭错误
    }

    try {
      await adbStream.close();
    } catch (e) {
      // 忽略关闭错误
    }
  }

  /// 开始健康检查
  void _startHealthCheck() {
    _acceptTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_state != TcpForwarderState.started) {
        timer.cancel();
        return;
      }

      // 清理断开的连接 - 简单地维护连接列表
      _clientSockets.removeWhere((client) {
        try {
          // 尝试写入空数据来检查连接状态
          client.add(Uint8List(0));
          return false; // 连接正常
        } catch (e) {
          return true; // 连接已断开
        }
      });
    });
  }

  /// 处理错误
  void _handleError(error) {
    print('端口转发错误: $error');
    // 在出现错误时尝试重新启动
    if (_state == TcpForwarderState.started) {
      Future.delayed(const Duration(seconds: 5), () async {
        try {
          await stop();
          await start();
        } catch (e) {
          print('自动重启失败: $e');
        }
      });
    }
  }
}

/// 端口转发管理器
class TcpForwarderManager {
  final Map<String, TcpForwarder> _forwarders = {};

  /// 创建新的端口转发
  Future<TcpForwarder> createForwarder({
    Future<AdbStream> Function()? streamCreator,
    required int hostPort,
    required int targetPort,
  }) async {
    final key = '${hostPort}_$targetPort';

    if (_forwarders.containsKey(key)) {
      throw AdbException('端口转发已存在: $hostPort -> $targetPort');
    }

    final forwarder = TcpForwarder(
      hostPort: hostPort,
      targetPort: targetPort,
      streamCreator: streamCreator,
    );

    _forwarders[key] = forwarder;
    return forwarder;
  }

  /// 停止端口转发
  Future<void> removeForwarder(int hostPort, int targetPort) async {
    final key = '${hostPort}_$targetPort';
    final forwarder = _forwarders.remove(key);

    if (forwarder != null) {
      await forwarder.stop();
    }
  }

  /// 停止所有端口转发
  Future<void> stopAll() async {
    final futures = _forwarders.values.map((f) => f.stop());
    await Future.wait(futures);
    _forwarders.clear();
  }

  /// 获取活动转发器数量
  int get activeForwarderCount => _forwarders.length;

  /// 获取转发器列表
  List<TcpForwarder> get forwarders => _forwarders.values.toList();
}
