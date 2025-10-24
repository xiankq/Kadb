import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'transport_channel.dart';

/// Socket传输通道，实现TransportChannel接口
class SocketTransportChannel implements TransportChannel {
  Socket? _socket;
  final List<int> _readBuffer = [];
  Completer<void>? _dataAvailable;
  bool _isConnected = false;
  bool _listenerStarted = false;
  bool _isClosed = false;

  static const int _maxBufferSize = 1024 * 1024;
  static const int _highWaterMark = 512 * 1024;
  static const int _lowWaterMark = 128 * 1024;

  bool _isBackpressureActive = false;
  final StreamController<void> _drainController =
      StreamController<void>.broadcast();

  /// 创建Socket传输通道
  SocketTransportChannel();

  Future<void> connect(String host, int port, {Duration? timeout}) async {
    if (_isClosed) throw StateError('传输通道已关闭');

    try {
      final addresses = await InternetAddress.lookup(host);
      if (addresses.isEmpty) {
        throw Exception('无法解析主机地址: $host');
      }

      _socket = await Socket.connect(addresses.first, port, timeout: timeout);
      _isConnected = true;
      _startSocketListener();
    } on TimeoutException {
      throw Exception('连接超时: $host:$port');
    } on SocketException catch (e) {
      throw Exception('连接失败: $e');
    }
  }

  /// 启动Socket数据监听
  void _startSocketListener() {
    if (_listenerStarted || _socket == null) return;
    _listenerStarted = true;

    _socket!.listen(
      (data) {
        if (_isClosed) return;

        if (_readBuffer.length + data.length > _maxBufferSize) {
          if (!_isBackpressureActive) {
            _isBackpressureActive = true;
          }
          final dropSize = _readBuffer.length + data.length - _maxBufferSize;
          _readBuffer.removeRange(0, dropSize);
        }

        _readBuffer.addAll(data);
        _signalDataAvailable();

        if (_isBackpressureActive && _readBuffer.length < _lowWaterMark) {
          _isBackpressureActive = false;
          _drainController.add(null);
        }
      },
      onError: (error) {
        if (!_isClosed) {
          _signalDataError(error);
        }
      },
      onDone: () {
        if (!_isClosed) {
          _signalDataAvailable();
        }
      },
      cancelOnError: false,
    );
  }

  void _signalDataAvailable() {
    final completer = _dataAvailable;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
      _dataAvailable = null;
    }
  }

  void _signalDataError(Object error) {
    final completer = _dataAvailable;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
      _dataAvailable = null;
    }
  }

  @override
  Future<void> readExactly(Uint8List buffer, Duration timeout) async {
    if (_isClosed || _socket == null || !_isConnected) {
      throw Exception('通道未连接');
    }

    var totalRead = 0;
    while (totalRead < buffer.length) {
      final remaining = buffer.length - totalRead;
      if (_readBuffer.length >= remaining) {
        buffer.setRange(totalRead, totalRead + remaining, _readBuffer);
        _readBuffer.removeRange(0, remaining);
        totalRead += remaining;
        continue;
      }

      if (_readBuffer.isNotEmpty) {
        final available = _readBuffer.length;
        buffer.setRange(totalRead, totalRead + available, _readBuffer);
        _readBuffer.removeRange(0, available);
        totalRead += available;
      }

      try {
        await _waitForData(timeout);
      } on TimeoutException {
        throw Exception('读取超时: 期望${buffer.length}字节，已读取$totalRead字节');
      }
    }
  }

  /// 等待数据可用
  Future<void> _waitForData(Duration timeout) async {
    if (_dataAvailable == null || _dataAvailable!.isCompleted) {
      _dataAvailable = Completer<void>();
    }

    try {
      await _dataAvailable!.future.timeout(timeout);
    } catch (e) {
      _dataAvailable = null;
      rethrow;
    }
  }

  @override
  Future<int> write(Uint8List data, Duration timeout) async {
    if (_isClosed || _socket == null || !_isConnected) {
      return 0;
    }

    final completer = Completer<int>();
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('写入超时'));
      }
    });

    try {
      if (_isBackpressureActive) {
        await _drainController.stream.first.timeout(timeout);
      }

      _socket!.add(data);
      await _socket!.flush();
      timer.cancel();

      if (!completer.isCompleted) {
        completer.complete(data.length);
      }
    } catch (e) {
      timer.cancel();

      if (_isConnectionClosedError(e)) {
        if (!completer.isCompleted) {
          completer.complete(0);
        }
      } else if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }

    return completer.future;
  }

  /// 检查是否为连接关闭错误
  bool _isConnectionClosedError(dynamic error) {
    final errorStr = error.toString();
    return errorStr.contains('Connection closed') ||
        errorStr.contains('Socket closed') ||
        errorStr.contains('Bad state') ||
        errorStr.contains('通道未连接');
  }

  @override
  Future<int> read(Uint8List buffer, Duration timeout) async {
    if (_isClosed || _socket == null || !_isConnected) {
      throw Exception('通道未连接');
    }

    var totalRead = 0;
    final available = _readBuffer.length;
    final toRead = available < buffer.length ? available : buffer.length;

    if (toRead > 0) {
      buffer.setRange(0, toRead, _readBuffer);
      _readBuffer.removeRange(0, toRead);
    }

    totalRead = toRead;
    return totalRead;
  }

  @override
  Future<void> writeExactly(Uint8List data, Duration timeout) async {
    final written = await write(data, timeout);
    if (written != data.length) {
      throw Exception('写入不完整: 期望${data.length}字节，实际写入$written字节');
    }
  }

  @override
  Future<void> shutdownInput() async {
    if (_socket != null) {
      try {
        _socket!.close();
      } catch (e) {
        // 忽略关闭异常
      }
    }
  }

  @override
  Future<void> shutdownOutput() async {
    if (_socket != null) {
      try {
        _socket!.close();
      } catch (e) {
        // 忽略关闭异常
      }
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    _isConnected = false;

    // 清理资源
    _dataAvailable = null;
    _readBuffer.clear();

    try {
      await _drainController.close();
    } catch (e) {
      // 忽略关闭异常
    }

    if (_socket != null) {
      try {
        await _socket!.close();
      } catch (e) {
        // 忽略关闭异常
      } finally {
        _socket = null;
      }
    }
  }

  bool get isConnected => _isConnected && !_isClosed;

  @override
  bool get isOpen => isConnected;

  @override
  InternetAddress get localAddress =>
      _socket?.address ?? InternetAddress('0.0.0.0');

  @override
  InternetAddress get remoteAddress {
    if (_socket == null) {
      return InternetAddress('0.0.0.0');
    }
    return _socket!.remoteAddress;
  }

  /// 获取缓冲区大小（用于监控）
  int get bufferSize => _readBuffer.length;

  /// 检查是否处于背压状态
  bool get isBackpressureActive => _isBackpressureActive;
}
