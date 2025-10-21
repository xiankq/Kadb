import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// TCP到HTTP流转换器
/// 接收TCP流数据并通过HTTP服务器提供给播放器
class TcpToHttpConverter {
  final int _tcpPort;
  final int _httpPort;
  final bool _debug;

  HttpServer? _httpServer;
  Socket? _tcpSocket;
  final List<Uint8List> _buffer = [];
  final StreamController<Uint8List> _streamController =
      StreamController<Uint8List>.broadcast();
  bool _isRunning = false;
  bool _isConnected = false;

  /// 获取HTTP URL
  String get httpUrl => 'http://127.0.0.1:$_httpPort';

  /// 获取运行状态
  bool get isRunning => _isRunning;

  /// 获取连接状态
  bool get isConnected => _isConnected;

  /// 获取HTTP端口
  int get httpPort => _httpPort;

  /// 获取TCP端口
  int get tcpPort => _tcpPort;

  TcpToHttpConverter({required int tcpPort, int? httpPort, bool debug = false})
    : _tcpPort = tcpPort,
      _httpPort = httpPort ?? (tcpPort + 1000), // 默认使用tcpPort+1000作为http端口
      _debug = debug;

  /// 启动转换器
  Future<void> start() async {
    if (_isRunning) {
      if (_debug) debugPrint('TCP到HTTP转换器已在运行');
      return;
    }

    try {
      // 启动HTTP服务器
      _httpServer = await HttpServer.bind('127.0.0.1', _httpPort);

      // 监听HTTP请求
      _httpServer!.listen(_handleHttpRequest);

      _isRunning = true;

      if (_debug) {
        debugPrint('TCP到HTTP转换器已启动');
        debugPrint('TCP端口: $_tcpPort -> HTTP端口: $_httpPort');
        debugPrint('HTTP URL: $httpUrl');
      }

      // 开始连接TCP流
      _connectToTcpStream();
    } catch (e) {
      if (_debug) debugPrint('启动TCP到HTTP转换器失败: $e');
      await stop();
      rethrow;
    }
  }

  /// 连接到TCP流
  Future<void> _connectToTcpStream() async {
    if (!_isRunning) return;

    int retryCount = 0;
    const maxRetries = 10;
    const retryDelay = Duration(seconds: 2);

    while (retryCount < maxRetries && _isRunning) {
      try {
        if (_debug) debugPrint('尝试连接TCP端口 $_tcpPort (第${retryCount + 1}次)');

        _tcpSocket = await Socket.connect(
          '127.0.0.1',
          _tcpPort,
          timeout: Duration(seconds: 5),
        );

        _isConnected = true;

        if (_debug) debugPrint('成功连接到TCP端口 $_tcpPort');

        // 开始监听TCP数据
        _listenToTcpData();

        return; // 连接成功，退出重试循环
      } catch (e) {
        retryCount++;
        if (_debug) {
          debugPrint('连接TCP端口 $_tcpPort 失败 (第${retryCount}次): $e');
        }

        if (retryCount < maxRetries && _isRunning) {
          await Future.delayed(retryDelay);
        }
      }
    }

    if (retryCount >= maxRetries) {
      if (_debug) debugPrint('无法连接到TCP端口 $_tcpPort，已达到最大重试次数');
    }
  }

  /// 监听TCP数据
  void _listenToTcpData() {
    if (_tcpSocket == null) return;

    _tcpSocket!.listen(
      (Uint8List data) {
        // 将数据添加到流中
        _streamController.add(data);

        // 保存到缓冲区（用于HTTP请求）
        _buffer.addAll([data]);

        // 限制缓冲区大小，避免内存溢出
        if (_buffer.length > 100) {
          _buffer.removeRange(0, _buffer.length - 50);
        }
      },
      onError: (error) {
        if (_debug) debugPrint('TCP数据流错误: $error');
        _isConnected = false;
        // 尝试重新连接
        _scheduleReconnect();
      },
      onDone: () {
        if (_debug) debugPrint('TCP数据流关闭');
        _isConnected = false;
        // 尝试重新连接
        _scheduleReconnect();
      },
      cancelOnError: false,
    );
  }

  /// 调度重连
  void _scheduleReconnect() {
    if (!_isRunning) return;

    Future.delayed(Duration(seconds: 3), () {
      if (_isRunning && !_isConnected) {
        if (_debug) debugPrint('尝试重新连接TCP流...');
        _connectToTcpStream();
      }
    });
  }

  /// 处理HTTP请求
  Future<void> _handleHttpRequest(HttpRequest request) async {
    if (_debug) {
      debugPrint('收到HTTP请求: ${request.method} ${request.uri.path}');
    }

    // 设置CORS头，允许跨域访问
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, OPTIONS',
    );
    request.response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type',
    );

    // 处理OPTIONS请求（CORS预检）
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    // 只处理GET请求
    if (request.method != 'GET') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    // 设置内容类型为原始H.264视频流
    request.response.headers.set('Content-Type', 'video/h264');
    request.response.headers.set('Accept-Ranges', 'bytes');
    
    // 设置缓存控制
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.headers.set('Connection', 'keep-alive');
    
    // 添加一些可能需要的头部
    request.response.headers.set('Transfer-Encoding', 'chunked');

    try {
      // 如果有缓冲数据，先发送缓冲数据
      if (_buffer.isNotEmpty) {
        for (final data in _buffer) {
          request.response.add(data);
        }
      }

      // 订阅数据流，实时转发数据
      final subscription = _streamController.stream.listen(
        (data) {
          try {
            request.response.add(data);
          } catch (e) {
            if (_debug) debugPrint('发送HTTP数据失败: $e');
          }
        },
        onError: (error) {
          if (_debug) debugPrint('HTTP流错误: $error');
        },
        onDone: () {
          if (_debug) debugPrint('HTTP流完成');
        },
      );

      // 当请求关闭时，取消订阅
      request.response.done
          .then((_) {
            subscription.cancel();
            if (_debug) debugPrint('HTTP请求关闭');
          })
          .catchError((error) {
            subscription.cancel();
            if (_debug) debugPrint('HTTP请求错误: $error');
          });

      // 保持连接开放，持续发送数据
      // 注意：不调用close()，保持流式传输
    } catch (e) {
      if (_debug) debugPrint('处理HTTP请求失败: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  /// 停止转换器
  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;
    _isConnected = false;

    // 关闭TCP连接
    try {
      await _tcpSocket?.close();
      _tcpSocket = null;
    } catch (e) {
      if (_debug) debugPrint('关闭TCP连接失败: $e');
    }

    // 关闭HTTP服务器
    try {
      await _httpServer?.close();
      _httpServer = null;
    } catch (e) {
      if (_debug) debugPrint('关闭HTTP服务器失败: $e');
    }

    // 关闭流控制器
    try {
      await _streamController.close();
    } catch (e) {
      if (_debug) debugPrint('关闭流控制器失败: $e');
    }

    // 清空缓冲区
    _buffer.clear();

    if (_debug) debugPrint('TCP到HTTP转换器已停止');
  }
}
