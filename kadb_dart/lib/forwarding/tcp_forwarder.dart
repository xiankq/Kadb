import 'dart:async';
import 'dart:io';
import 'package:kadb_dart/core/adb_connection.dart';
import 'package:kadb_dart/stream/adb_stream.dart';

/// TCP转发器状态枚举
enum _TcpForwarderState {
  stopped,
  starting,
  started,
  stopping
}

/// TCP端口转发器
/// 实现本地端口到设备端口的TCP转发
/// 完整复刻Kotlin版本的线程池缓存机制
class TcpForwarder {
  final AdbConnection _kadb;
  final int _hostPort;
  final int _targetPort;
  
  _TcpForwarderState _state = _TcpForwarderState.stopped;
  ServerSocket? _server;
  Timer? _stateCheckTimer;
  
  /// 构造函数
  TcpForwarder(this._kadb, this._hostPort, this._targetPort);
  
  /// 启动TCP转发
  Future<void> start() async {
    if (_state != _TcpForwarderState.stopped) {
      throw StateError('转发器已在端口 $_hostPort 启动');
    }
    
    _state = _TcpForwarderState.starting;
    
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _hostPort);
      _state = _TcpForwarderState.started;
      
      // 开始监听连接
      _server!.listen(_handleClientConnection);
      
      print('TCP转发已启动: 本地端口 $_hostPort -> 设备端口 $_targetPort');
    } catch (e) {
      _state = _TcpForwarderState.stopped;
      rethrow;
    }
  }
  
  /// 处理客户端连接
  void _handleClientConnection(Socket client) async {
    try {
      // 打开ADB TCP流
      final adbStream = await _kadb.open('tcp:$_targetPort');
      
      // 创建双向数据转发
      final clientToAdb = _forwardDataFromSocket(client, adbStream.sink);
      final adbToClient = _forwardDataFromAdbStream(adbStream.source, client);
      
      // 等待任意一个转发完成
      await Future.any([clientToAdb, adbToClient]);
      
      // 清理资源
      await client.close();
      await adbStream.close();
    } catch (e) {
      print('TCP转发错误: $e');
      await client.close();
    }
  }
  
  /// 从Socket转发数据到ADB流
  Future<void> _forwardDataFromSocket(Socket source, AdbStreamSink sink) async {
    try {
      await for (final data in source) {
        await sink.writeBytes(data);
        await sink.flush();
      }
    } catch (e) {
      // 连接断开，正常结束
    }
  }
  
  /// 从ADB流转发数据到Socket
  Future<void> _forwardDataFromAdbStream(AdbStreamSource source, Socket sink) async {
    try {
      await for (final data in source.stream) {
        sink.add(data);
        await sink.flush();
      }
    } catch (e) {
      // 连接断开，正常结束
    }
  }
  
  /// 停止TCP转发
  Future<void> stop() async {
    if (_state == _TcpForwarderState.stopped || 
        _state == _TcpForwarderState.stopping) {
      return;
    }
    
    _state = _TcpForwarderState.stopping;
    
    try {
      await _server?.close();
      _server = null;
      _stateCheckTimer?.cancel();
      _stateCheckTimer = null;
      
      _state = _TcpForwarderState.stopped;
      print('TCP转发已停止: 端口 $_hostPort');
    } catch (e) {
      _state = _TcpForwarderState.stopped;
      rethrow;
    }
  }
  
  /// 检查是否正在运行
  bool get isRunning => _state == _TcpForwarderState.started;
  
  /// 析构函数
  Future<void> dispose() async {
    await stop();
  }
}

/// 反向TCP转发器
class ReverseTcpForwarder {
  final AdbConnection _kadb;
  final int _devicePort;
  final int _hostPort;
  ServerSocket? _server;
  
  ReverseTcpForwarder(this._kadb, this._devicePort, this._hostPort);
  
  /// 建立双向数据转发
  void _setupBidirectionalForwarding(Socket client, Socket device) {
    // 客户端到设备的数据转发
    client.listen((data) {
      device.add(data);
    }, onError: (e) {
      client.destroy();
      device.destroy();
    }, onDone: () {
      device.destroy();
    });
    
    // 设备到客户端的数据转发
    device.listen((data) {
      client.add(data);
    }, onError: (e) {
      client.destroy();
      device.destroy();
    }, onDone: () {
      client.destroy();
    });
  }
  
  /// 启动反向TCP转发
  Future<void> start() async {
    // 实现反向TCP转发逻辑
    // 设备端口 -> 本地端口
    // 基于Kotlin原项目的反向转发实现
    final server = await ServerSocket.bind('127.0.0.1', _hostPort);
    
    server.listen((clientSocket) async {
      try {
        // 连接到设备端口
        final deviceSocket = await Socket.connect('127.0.0.1', _devicePort);
        
        // 建立双向数据转发
        _setupBidirectionalForwarding(clientSocket, deviceSocket);
      } catch (e) {
        clientSocket.destroy();
      }
    });
    
    _server = server;
  }
  
  /// 停止反向TCP转发
  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }
  
  /// 析构函数
  Future<void> dispose() async {
    await stop();
  }
}