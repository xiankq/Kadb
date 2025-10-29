/// ADB连接管理
/// 处理与ADB设备的连接建立和管理
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
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
      throw AdbConnectionException(
          'Connection is already established or in progress');
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

      // 启动消息队列
      _messageQueue!.start();

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
    print('等待ADB连接响应...');
    int responseCount = 0;

    while (true) {
      responseCount++;
      print('等待响应 #$responseCount...');

      final response = await _reader!.readMessage();
      print('收到响应: ${AdbProtocol.getCommandName(response.command)} (arg0=${response.arg0}, arg1=${response.arg1})');

      switch (response.command) {
        case AdbProtocol.cmdStls:
          // TLS加密请求
          print('收到TLS请求');
          await _handleTlsRequest(response);
          break;

        case AdbProtocol.cmdAuth:
          // 认证请求
          print('收到认证请求');
          await _handleAuthRequest(response);
          // 认证后需要继续等待响应（可能是CNXN或另一个AUTH）
          break;

        case AdbProtocol.cmdCnxn:
          // 连接确认
          print('收到连接确认');
          await _handleConnectionConfirmation(response);
          return;

        default:
          throw AdbProtocolException(
              'Unexpected message during connection: ${AdbProtocol.getCommandName(response.command)}');
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
    print('收到认证请求: authType=${request.arg0}, payload长度=${request.payload?.length ?? 0}');

    if (request.arg0 == AdbProtocol.authTypeToken) {
      // ADB标准认证流程：首先发送公钥
      print('发送RSA公钥进行认证...');
      final publicKey = keyPair.getAdbPublicKey();
      await _writer!.writeAuth(AdbProtocol.authTypeRsaPublic, publicKey);
      print('RSA公钥已发送，等待设备响应...');

      // 设备会响应：
      // 1. CNXN (如果公钥已授权)
      // 2. 新的AUTH token (如果公钥未知，需要签名认证)
      final deviceResponse = await _reader!.readMessage().timeout(
        Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('等待设备认证响应超时');
        },
      );

      print('收到设备认证响应: ${AdbProtocol.getCommandName(deviceResponse.command)}');

      if (deviceResponse.command == AdbProtocol.cmdCnxn) {
        // 公钥已授权，连接成功！
        print('✅ 公钥认证成功，连接已建立！');
        await _handleConnectionConfirmation(deviceResponse);
        return;
      }

      if (deviceResponse.command == AdbProtocol.cmdAuth &&
          deviceResponse.arg0 == AdbProtocol.authTypeToken) {
        // 设备不认识这个公钥，需要提供签名
        print('设备需要签名认证，正在生成签名...');

        // 使用私钥对新的token进行签名
        final signature = keyPair.signPayload(deviceResponse.payload!);
        print('生成RSA签名: ${signature.length} 字节');

        // 发送签名
        await _writer!.writeAuth(AdbProtocol.authTypeSignature, signature);
        print('RSA签名已发送，等待最终确认...');

        // 等待最终连接确认
        final finalResponse = await _reader!.readMessage().timeout(
          Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('等待最终连接确认超时');
          },
        );

        if (finalResponse.command == AdbProtocol.cmdCnxn) {
          print('✅ 签名认证成功，连接已建立！');
          await _handleConnectionConfirmation(finalResponse);
        } else {
          throw AdbAuthException('认证失败，收到意外响应: ${AdbProtocol.getCommandName(finalResponse.command)}');
        }
      } else {
        throw AdbAuthException('认证收到意外响应: ${AdbProtocol.getCommandName(deviceResponse.command)}');
      }
    } else {
      throw AdbAuthException('不支持的认证类型: ${request.arg0}');
    }
  }

  /// 处理连接确认
  Future<void> _handleConnectionConfirmation(AdbMessage confirmation) async {
    _version = confirmation.arg0;
    _maxPayloadSize = confirmation.arg1;

    // 解析连接字符串
    final connectionString = String.fromCharCodes(confirmation.payload!);
    _parseConnectionString(connectionString);

    print('✅ ADB连接已建立: 版本=$_version, 最大载荷=$_maxPayloadSize');
    print('✅ 设备信息: $connectionString');
    print('✅ 支持特性: ${_supportedFeatures.join(', ')}');
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
