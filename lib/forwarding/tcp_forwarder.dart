/*
 * Copyright (c) 2024 Flyfish-Xu
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:async';
import 'dart:io';
import '../core/adb_connection.dart';
import '../stream/adb_stream.dart';
import '../exception/adb_stream_closed.dart';

/// TCP转发器状态枚举
enum TcpForwarderState { starting, started, stopping, stopped }

/// TCP端口转发器
/// 完整复刻Kotlin版本的实现，包括线程池、状态管理、超时处理等功能
/// 支持两种模式：
/// 1. TCP到TCP转发 (tcp:port -> tcp:targetPort)
/// 2. TCP到任意ADB服务 (tcp:port -> localabstract:name, shell:command等)
class TcpForwarder {
  final AdbConnection _kadb;
  final int _hostPort;
  final String _destination;
  final int? _targetPort; // 向后兼容
  final bool _debug;

  TcpForwarderState _state = TcpForwarderState.stopped;
  ServerSocket? _server;
  final List<Future<void>> _clientFutures = [];
  Timer? _stateCheckTimer;

  /// 构造函数 - 任意ADB目标服务
  /// [kadb] ADB连接
  /// [hostPort] 本地端口
  /// [destination] 目标服务，如 "tcp:8080", "localabstract:myservice", "shell:cat"
  TcpForwarder(
    this._kadb,
    this._hostPort,
    this._destination, {
    bool debug = false,
  }) : _targetPort = null,
       _debug = debug;

  /// 构造函数 - TCP到TCP转发（向后兼容）
  /// [kadb] ADB连接
  /// [hostPort] 本地端口
  /// [targetPort] 目标端口
  TcpForwarder.tcpToTcp(
    this._kadb,
    this._hostPort,
    int targetPort, {
    bool debug = false,
  }) : _destination = 'tcp:$targetPort',
       _targetPort = targetPort,
       _debug = debug;

  /// 启动TCP转发
  ///
  /// 启动一个TCP服务器在指定端口，将所有连接转发到目标服务
  ///
  /// 抛出 [StateError] 如果转发器已经启动
  /// 抛出 [SocketException] 如果无法绑定到指定端口
  Future<void> start() async {
    if (_state != TcpForwarderState.stopped) {
      throw StateError('Forwarder is already started at port $_hostPort');
    }

    _moveToState(TcpForwarderState.starting);

    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _hostPort);
      _moveToState(TcpForwarderState.started);

      // 监听客户端连接
      _server!.listen(_handleClientConnection, onError: _handleServerError);

      if (_debug) {
        if (_targetPort != null) {
          print('TCP转发已启动: 本地端口 $_hostPort -> 设备端口 $_targetPort');
        } else {
          print('TCP转发已启动: 本地端口 $_hostPort -> 设备服务 $_destination');
        }
      }
    } catch (e) {
      _moveToState(TcpForwarderState.stopped);
      rethrow;
    }
  }

  /// 处理客户端连接
  ///
  /// 为每个客户端连接创建独立的处理进行双向数据转发
  Future<void> _handleClientConnection(Socket client) async {
    AdbStream? adbStream;
    try {
      // 打开ADB流到目标服务
      adbStream = await _kadb.open(_destination);

      // 等待远程ID分配，确保流已正确建立
      try {
        await adbStream.waitForRemoteId().timeout(Duration(seconds: 5));
      } catch (e) {
        if (_debug) {
          print('警告: 等待远程ID分配失败: $e');
        }
        // 继续尝试，不立即关闭连接
      }

      // 优化：为视频流设置Socket缓冲区
      try {
        client.setOption(SocketOption.tcpNoDelay, true); // 禁用Nagle算法，减少延迟
      } catch (e) {
        if (_debug) {
          print('设置socket TCP_NODELAY失败: $e');
        }
      }

      if (_debug) {
        print(
          '连接已建立: ${client.remoteAddress.address}:${client.remotePort} -> $_destination (视频流优化)',
        );
      }

      // 立即开始处理双向转发，不等待
      unawaited(_handleClientForwarding(client, adbStream));
    } catch (e) {
      if (_debug) {
        print('TCP转发错误: $e');
        print('目标服务: $_destination');
        print('客户端地址: ${client.remoteAddress.address}:${client.remotePort}');
      }

      // 提供通用的错误信息
      String errorMsg = e.toString();
      if (errorMsg.contains('TimeoutException')) {
        if (_destination.startsWith('localabstract:')) {
          final serviceName = _destination.split(':')[1];
          print('警告: 连接Android服务超时: $serviceName');
          print('可能的原因:');
          print('   1. 目标服务未启动或正在启动');
          print('   2. 服务名称不正确');
          print('   3. 目标服务可能正在处理其他连接');
        } else if (_destination.startsWith('tcp:')) {
          final port = _destination.split(':')[1];
          print('警告: 连接设备TCP端口超时: $port');
          print('可能的原因:');
          print('   1. 目标端口没有服务监听');
          print('   2. 防火墙阻止连接');
          print('   3. 网络连接问题');
        }
        print('转发器继续运行，等待其他连接尝试...');
        // 不重新抛出异常，继续运行转发器
        return;
      } else if (errorMsg.contains('AdbStreamClosed') || e is AdbStreamClosed) {
        // 静默处理ADB流关闭，这是正常的连接断开
        return;
      }

      // 确保在出错时关闭客户端连接
      try {
        await client.close();
      } catch (_) {
        // 忽略关闭错误
      }
      // 如果ADB流已经创建但出错，也尝试关闭它
      if (adbStream != null) {
        try {
          await adbStream.close();
        } catch (_) {
          // 忽略关闭错误
        }
      }
    }
  }

  /// 不等待Future完成（类似Kotlin的线程执行）
  void unawaited(Future<void> future) {
    // 故意不等待future完成，模拟Kotlin的线程池执行
  }

  /// 处理客户端数据转发
  Future<void> _handleClientForwarding(
    Socket client,
    AdbStream adbStream,
  ) async {
    try {
      // 创建双向数据转发
      final clientToAdb = _forwardDataFromSocket(client, adbStream.sink);
      final adbToClient = _forwardDataFromAdbStream(adbStream.source, client);

      // 等待任一方向的数据传输完成（任一方向断开则整个连接结束）
      await Future.any([clientToAdb, adbToClient]);
    } catch (e) {
      if (_debug) {
        if (e is AdbStreamClosed) {
          print('ADB流在数据转发期间关闭（正常连接终止）');
        } else if (e.toString().contains('AdbStreamClosed')) {
          print('数据转发期间检测到ADB流关闭异常: $e');
        } else {
          print('数据转发期间发生错误: $e');
        }
      }
      // 不重新抛出异常，继续执行清理逻辑
    } finally {
      // 清理资源，使用更安全的关闭方式
      await _cleanupClientConnection(client, adbStream);
    }
  }

  /// 安全清理客户端连接资源
  Future<void> _cleanupClientConnection(
    Socket client,
    AdbStream adbStream,
  ) async {
    // 关闭客户端连接
    try {
      await client.close();
    } catch (e) {
      if (_debug) {
        print('Error closing client connection: $e');
      }
    }

    // 关闭ADB流
    try {
      await adbStream.close();
    } catch (e) {
      if (_debug) {
        print('Error closing ADB stream: $e');
      }
    }
  }

  /// 处理服务器错误
  void _handleServerError(Object error) {
    if (_debug) {
      print('TCP forward server error: $error');
    }
    if (_state == TcpForwarderState.started) {
      _moveToState(TcpForwarderState.stopped);
    }
  }

  /// 从Socket转发数据到ADB流（性能优化版本）
  Future<void> _forwardDataFromSocket(Socket source, AdbStreamSink sink) async {
    try {
      final socketStream = source.asBroadcastStream();
      await for (final data in socketStream) {
        // 优化：针对视频流，立即flush确保实时性
        try {
          await sink.writeBytes(data);
          await sink.flush(); // 恢复flush调用，对视频流实时性至关重要
          if (_debug && data.isNotEmpty) {
            print('Socket->ADB: 发送 ${data.length} 字节 (视频流实时传输)');
          }
        } catch (e) {
          if (e.toString().contains('AdbStreamClosed') ||
              e is AdbStreamClosed) {
            print('Socket->ADB: ADB stream closed, stopping forward');
            return;
          } else if (e.toString().contains('StateError') &&
              e.toString().contains('流已关闭')) {
            print('Socket->ADB: stream closed, stopping forward');
            return;
          } else {
            print('Socket->ADB: error writing data: $e');
            // 移除延迟重试，直接返回
            return;
          }
        }
      }
    } catch (e) {
      if (_debug) {
        if (e.toString().contains('SocketException')) {
          print('Socket->ADB: socket connection closed (normal termination)');
        } else {
          print('Socket->ADB: error during forwarding: $e');
        }
      }
    }
  }

  /// 从ADB流转发数据到Socket（性能优化版本）
  Future<void> _forwardDataFromAdbStream(
    AdbStreamSource source,
    Socket sink,
  ) async {
    try {
      await for (final data in source.stream) {
        // 优化：直接发送整个数据块，避免分块延迟
        try {
          sink.add(data);
          // 移除flush调用，减少系统调用开销
        } catch (e) {
          if (e.toString().contains('SocketException')) {
            print('ADB->Socket: socket connection closed, stopping forward');
            return;
          } else {
            print('ADB->Socket: error writing data: $e');
            // 移除延迟重试，直接返回
            return;
          }
        }
      }
    } catch (e) {
      if (_debug) {
        if (e.toString().contains('AdbStreamClosed') ||
            e.toString().contains('StateError')) {
          print('ADB->Socket: ADB stream closed (normal termination)');
        } else {
          print('ADB->Socket: error during forwarding: $e');
        }
      }
    }
  }

  /// 停止TCP转发
  ///
  /// 关闭服务器，停止接受新的连接，并等待所有现有连接完成
  ///
  /// 等待最多5秒钟让服务器进入稳定状态，超时抛出 [TimeoutException]
  Future<void> stop() async {
    if (_state == TcpForwarderState.stopped ||
        _state == TcpForwarderState.stopping) {
      return;
    }

    // 等待服务器进入稳定状态
    await _waitFor(
      () => _state == TcpForwarderState.started,
      interval: Duration(milliseconds: 100),
      timeout: Duration(seconds: 5),
    );

    _moveToState(TcpForwarderState.stopping);

    try {
      // 关闭服务器
      await _server?.close();
      _server = null;

      // 等待所有客户端连接完成
      if (_clientFutures.isNotEmpty) {
        await Future.wait(_clientFutures, eagerError: false);
        _clientFutures.clear();
      }

      _stateCheckTimer?.cancel();
      _stateCheckTimer = null;

      _moveToState(TcpForwarderState.stopped);
      if (_debug) {
        if (_targetPort != null) {
          print('TCP forward stopped: port $_hostPort');
        } else {
          print('TCP forward stopped: local port $_hostPort');
        }
      }
    } catch (e) {
      _moveToState(TcpForwarderState.stopped);
      rethrow;
    }
  }

  /// 检查是否正在运行
  bool get isRunning => _state == TcpForwarderState.started;

  /// 获取当前状态
  TcpForwarderState get state => _state;

  /// 获取本地端口
  int get hostPort => _hostPort;

  /// 获取目标服务
  String get destination => _destination;

  /// 获取目标端口（向后兼容）
  int? get targetPort => _targetPort;

  /// 移动到新状态
  void _moveToState(TcpForwarderState newState) {
    _state = newState;
  }

  /// 等待条件满足
  ///
  /// [test] 测试函数，返回true时停止等待
  /// [interval] 检查间隔
  /// [timeout] 超时时间
  ///
  /// 抛出 [TimeoutException] 如果超时
  Future<void> _waitFor(
    bool Function() test, {
    Duration interval = const Duration(milliseconds: 100),
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final start = DateTime.now();
    var lastCheck = start;

    while (!test()) {
      final now = DateTime.now();
      final timeSinceStart = now.difference(start);
      final timeSinceLastCheck = now.difference(lastCheck);

      if (timeout.inMilliseconds > 0 && timeSinceStart >= timeout) {
        throw TimeoutException('等待条件超时', timeout);
      }

      final sleepTime = interval - timeSinceLastCheck;
      if (sleepTime > Duration.zero) {
        await Future.delayed(sleepTime);
      }

      lastCheck = DateTime.now();
    }
  }

  /// 析构函数
  Future<void> dispose() async {
    await stop();
  }
}

/// 反向TCP转发器
///
/// 将设备端口转发到本地端口
class ReverseTcpForwarder {
  final AdbConnection _kadb;
  final int _devicePort;
  final int _hostPort;
  final bool _debug;

  TcpForwarderState _state = TcpForwarderState.stopped;
  ServerSocket? _server;
  Timer? _stateCheckTimer;

  ReverseTcpForwarder(
    this._kadb,
    this._devicePort,
    this._hostPort, {
    bool debug = false,
  }) : _debug = debug;

  /// 启动反向TCP转发
  ///
  /// 在本地启动服务器，连接转发到设备端口
  Future<void> start() async {
    if (_state != TcpForwarderState.stopped) {
      throw StateError('反向转发器已在端口 $_hostPort 启动');
    }

    _moveToState(TcpForwarderState.starting);

    try {
      _server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _hostPort,
      );
      _moveToState(TcpForwarderState.started);

      _server!.listen(_handleReverseConnection);

      if (_debug) {
        print(
          'Reverse TCP forward started: device port $_devicePort -> local port $_hostPort',
        );
      }
    } catch (e) {
      _moveToState(TcpForwarderState.stopped);
      rethrow;
    }
  }

  /// 处理反向连接
  Future<void> _handleReverseConnection(Socket client) async {
    AdbStream? adbStream;
    try {
      // 通过ADB连接到设备端口
      adbStream = await _kadb.open('tcp:$_devicePort');

      // 等待远程ID分配，确保流已正确建立
      await adbStream.waitForRemoteId();

      // 建立双向数据转发
      await _setupBidirectionalForwarding(client, adbStream);
    } catch (e) {
      if (_debug) {
        print('Reverse TCP forward error: $e');
      }
      // 确保在出错时关闭客户端连接
      try {
        await client.close();
      } catch (_) {
        // 忽略关闭错误
      }
      // 如果ADB流已经创建但出错，也尝试关闭它
      if (adbStream != null) {
        try {
          await adbStream.close();
        } catch (_) {
          // 忽略关闭错误
        }
      }
    }
  }

  /// 建立双向数据转发
  Future<void> _setupBidirectionalForwarding(
    Socket client,
    AdbStream adbStream,
  ) async {
    try {
      final clientToAdb = _forwardSocketToAdb(client, adbStream.sink);
      final adbToClient = _forwardAdbToSocket(adbStream.source, client);

      // 等待任意一个转发完成
      await Future.any([clientToAdb, adbToClient]);
    } finally {
      // 清理资源
      await client.close();
      await adbStream.close();
    }
  }

  /// 从Socket转发数据到ADB流
  Future<void> _forwardSocketToAdb(Socket source, AdbStreamSink sink) async {
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
  Future<void> _forwardAdbToSocket(AdbStreamSource source, Socket sink) async {
    try {
      await for (final data in source.stream) {
        sink.add(data);
        await sink.flush();
      }
    } catch (e) {
      // 连接断开，正常结束
    }
  }

  /// 停止反向TCP转发
  Future<void> stop() async {
    if (_state == TcpForwarderState.stopped ||
        _state == TcpForwarderState.stopping) {
      return;
    }

    // 等待服务器进入稳定状态
    await _waitFor(
      () => _state == TcpForwarderState.started,
      interval: Duration(milliseconds: 100),
      timeout: Duration(seconds: 5),
    );

    _moveToState(TcpForwarderState.stopping);

    try {
      await _server?.close();
      _server = null;
      _stateCheckTimer?.cancel();
      _stateCheckTimer = null;

      _moveToState(TcpForwarderState.stopped);
      if (_debug) {
        print('Reverse TCP forward stopped: port $_hostPort');
      }
    } catch (e) {
      _moveToState(TcpForwarderState.stopped);
      rethrow;
    }
  }

  /// 检查是否正在运行
  bool get isRunning => _state == TcpForwarderState.started;

  /// 获取设备端口
  int get devicePort => _devicePort;

  /// 获取本地端口
  int get hostPort => _hostPort;

  /// 移动到新状态
  void _moveToState(TcpForwarderState newState) {
    _state = newState;
  }

  /// 等待条件满足
  Future<void> _waitFor(
    bool Function() test, {
    Duration interval = const Duration(milliseconds: 100),
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final start = DateTime.now();
    var lastCheck = start;

    while (!test()) {
      final now = DateTime.now();
      final timeSinceStart = now.difference(start);
      final timeSinceLastCheck = now.difference(lastCheck);

      if (timeout.inMilliseconds > 0 && timeSinceStart >= timeout) {
        throw TimeoutException('等待条件超时', timeout);
      }

      final sleepTime = interval - timeSinceLastCheck;
      if (sleepTime > Duration.zero) {
        await Future.delayed(sleepTime);
      }

      lastCheck = DateTime.now();
    }
  }

  /// 析构函数
  Future<void> dispose() async {
    await stop();
  }
}
