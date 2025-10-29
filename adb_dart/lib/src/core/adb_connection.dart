/**
 * ADB连接管理
 * 处理与ADB设备的连接建立和管理
 */

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/pointycastle.dart' as pc;
import 'package:convert/convert.dart';
import 'adb_message.dart';
import 'adb_reader.dart';
import 'adb_writer.dart';
import 'adb_protocol.dart';
import '../exception/adb_exceptions.dart';
import '../cert/adb_key_pair.dart';
import '../queue/adb_message_queue.dart';
import '../stream/adb_stream.dart';

/// ADB连接状态
enum AdbConnectionState {
  disconnected,
  connecting,
  authenticating,
  connected,
  disconnecting,
}

/// ADB连接类
class AdbConnection {
  final String host;
  final int port;
  final AdbKeyPair keyPair;
  final Duration connectTimeout;
  final Duration socketTimeout;

  Socket? _socket;
  AdbReader? _reader;
  AdbWriter? _writer;
  AdbMessageQueue? _messageQueue;

  AdbConnectionState _state = AdbConnectionState.disconnected;
  int _version = 0;
  int _maxPayloadSize = 0;
  Set<String> _supportedFeatures = {};
  final Random _random = Random();

  AdbConnection({
    required this.host,
    required this.port,
    required this.keyPair,
    this.connectTimeout = const Duration(seconds: 10),
    this.socketTimeout = const Duration(seconds: 30),
  });

  /// 获取连接状态
  AdbConnectionState get state => _state;

  /// 获取协议版本
  int get version => _version;

  /// 获取最大载荷大小
  int get maxPayloadSize => _maxPayloadSize;

  /// 获取支持的特性
  Set<String> get supportedFeatures => Set.unmodifiable(_supportedFeatures);

  /// 是否支持特定特性
  bool supportsFeature(String feature) {
    return _supportedFeatures.contains(feature);
  }

  /// 建立连接
  Future<void> connect() async {
    if (_state != AdbConnectionState.disconnected) {
      throw AdbConnectionException('Connection is already established or in progress');
    }

    _state = AdbConnectionState.connecting;

    try {
      // 建立TCP连接
      _socket = await Socket.connect(host, port, timeout: connectTimeout);
      _socket?.setOption(SocketOption.tcpNoDelay, true);

      // 初始化读写器
      _reader = AdbReader(_socket!);
      _writer = AdbWriter(_socket!);
      _messageQueue = AdbMessageQueue(_reader!);

      // 发送连接请求
      await _writer!.writeConnect();

      // 处理连接响应
      await _handleConnectionResponse();

      _state = AdbConnectionState.connected;
    } catch (e) {
      _state = AdbConnectionState.disconnected;
      await _cleanup();
      throw AdbConnectionException('Failed to establish connection', e);
    }
  }

  /// 处理连接响应
  Future<void> _handleConnectionResponse() async {
    while (true) {
      final response = await _reader!.readMessage();

      switch (response.command) {
        case AdbProtocol.cmdStls:
          // TLS加密请求
          await _handleTlsRequest(response);
          break;

        case AdbProtocol.cmdAuth:
          // 认证请求
          await _handleAuthRequest(response);
          break;

        case AdbProtocol.cmdCnxn:
          // 连接确认
          await _handleConnectionConfirmation(response);
          return;

        default:
          throw AdbProtocolException('Unexpected message during connection: ${AdbProtocol.getCommandName(response.command)}');
      }
    }
  }

  /// 处理TLS请求
  Future<void> _handleTlsRequest(AdbMessage request) async {
    // TODO: 实现TLS支持
    throw UnimplementedError('TLS support not implemented yet');
  }

  /// 处理认证请求
  Future<void> _handleAuthRequest(AdbMessage request) async {
    _state = AdbConnectionState.authenticating;

    if (request.arg0 == AdbProtocol.authTypeToken) {
      // 使用私钥签名token
      final signature = keyPair.signPayload(request.payload!);
      await _writer!.writeAuth(AdbProtocol.authTypeSignature, signature);
    } else {
      throw AdbAuthException('Unsupported auth type: ${request.arg0}');
    }
  }

  /// 处理连接确认
  Future<void> _handleConnectionConfirmation(AdbMessage confirmation) async {
    _version = confirmation.arg0;
    _maxPayloadSize = confirmation.arg1;

    // 解析连接字符串
    final connectionString = String.fromCharCodes(confirmation.payload!);
    _parseConnectionString(connectionString);

    print('ADB连接已建立: 版本=$_version, 最大载荷=$_maxPayloadSize');
    print('设备信息: $connectionString');
  }

  /// 解析连接字符串
  void _parseConnectionString(String connectionString) {
    // 解析格式: "device::ro.product.name=xxx;ro.product.model=yyy;features=aaa,bbb,ccc"
    try {
      final deviceInfo = connectionString.substring('device::'.length);
      final parts = deviceInfo.split(';');

      for (final part in parts) {
        if (part.startsWith('features=')) {
          final featuresStr = part.substring('features='.length);
          _supportedFeatures = featuresStr.split(',').toSet();
          break;
        }
      }
    } catch (e) {
      print('警告: 无法解析连接字符串: $connectionString');
    }
  }

  /// 打开流
  Future<AdbStream> openStream(String destination) async {
    if (_state != AdbConnectionState.connected) {
      throw AdbConnectionException('Connection is not established');
    }

    final localId = _generateLocalId();
    _messageQueue!.startListening(localId);

    try {
      // 发送OPEN消息
      await _writer!.writeOpen(localId, destination);

      // 等待OKAY响应
      final response = await _messageQueue!.take(localId, AdbProtocol.cmdOkay);
      final remoteId = response.arg0;

      // 创建流对象
      return AdbStream(
        messageQueue: _messageQueue!,
        writer: _writer!,
        maxPayloadSize: _maxPayloadSize,
        localId: localId,
        remoteId: remoteId,
      );
    } catch (e) {
      _messageQueue!.stopListening(localId);
      throw AdbStreamException('Failed to open stream to $destination', e);
    }
  }

  /// 生成本地流ID
  int _generateLocalId() {
    return _random.nextInt(0x7FFFFFFF) + 1; // 确保为正数且非零
  }

  /// 关闭连接
  Future<void> close() async {
    if (_state == AdbConnectionState.disconnected) {
      return;
    }

    _state = AdbConnectionState.disconnecting;
    await _cleanup();
    _state = AdbConnectionState.disconnected;
  }

  /// 清理资源
  Future<void> _cleanup() async {
    try {
      _messageQueue?.close();
      _reader?.close();
      _writer?.close();
      await _socket?.close();
    } catch (e) {
      // 忽略清理过程中的错误
    } finally {
      _messageQueue = null;
      _reader = null;
      _writer = null;
      _socket = null;
    }
  }

  /// 静态工厂方法：建立连接
  static Future<AdbConnection> connectTo(
    String host,
    int port,
    AdbKeyPair keyPair, {
    Duration? connectTimeout,
    Duration? socketTimeout,
  }) async {
    final connection = AdbConnection(
      host: host,
      port: port,
      keyPair: keyPair,
      connectTimeout: connectTimeout ?? const Duration(seconds: 10),
      socketTimeout: socketTimeout ?? const Duration(seconds: 30),
    );

    await connection.connect();
    return connection;
  }
}