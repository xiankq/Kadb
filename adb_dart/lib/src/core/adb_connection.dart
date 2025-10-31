/// ADB连接管理
/// 处理与ADB设备的连接建立和管理
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'adb_message.dart';
import 'adb_reader.dart';
import 'adb_writer.dart';
import 'adb_protocol.dart';
import '../exception/adb_exceptions.dart';
import '../cert/adb_key_pair.dart';
import '../queue/adb_message_queue.dart';
import '../stream/adb_stream.dart';
import '../tls/ssl_utils.dart';
import '../cert/android_pubkey.dart';

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
      print('DEBUG: 当前连接状态: $_state');

      try {
        print('DEBUG: 准备读取消息...');
        final response = await _reader!.readMessage().timeout(
          Duration(seconds: 30), // 增加超时时间到30秒
          onTimeout: () {
            print('❌ 等待响应超时 (30秒)');
            throw TimeoutException('等待数据超时 - 设备可能无响应', Duration(seconds: 30));
          },
        );
        print('收到响应: ${AdbProtocol.getCommandName(response.command)} (arg0=${response.arg0}, arg1=${response.arg1})');

        switch (response.command) {
          case AdbProtocol.cmdStls:
            // TLS加密请求
            print('收到TLS请求');
            await _handleTlsRequest(response);
            break;

          case AdbProtocol.cmdAuth:
            // 认证请求
            print('DEBUG: 进入认证处理分支 - cmdAuth=${response.command}');
            print('收到认证请求');
            await _handleAuthRequest(response);
            // 认证后需要继续等待响应（可能是CNXN或另一个AUTH）
            print('DEBUG: 认证处理完成，继续等待下一个响应');
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

        print('DEBUG: 响应处理完成，继续循环...');
      } catch (e) {
        print('消息循环错误: $e');
        rethrow;
      }
    }
  }

  /// 处理TLS请求
  Future<void> _handleTlsRequest(AdbMessage request) async {
    try {
      print('收到TLS请求，开始TLS握手...');

      // 获取SSL上下文（使用当前密钥对）
      final sslContext = SslUtils.getSslContext(keyPair);

      // 配置安全套接字
      final secureSocket = await SecureSocket.connect(
        host,
        port,
        context: sslContext,
        onBadCertificate: (certificate) {
          // 在ADB配对中接受所有证书
          print('接受TLS证书（ADB配对模式）');
          return true;
        },
      );

      print('TLS连接建立成功');
      print('TLS版本: ${secureSocket.selectedProtocol}');

      // 发送TLS握手完成确认
      final responsePayload = Uint8List.fromList('TLS_OK'.codeUnits);
      final responseChecksum = responsePayload.fold<int>(0, (sum, byte) => sum + (byte & 0xFF));
      final response = AdbMessage(
        command: AdbProtocol.cmdOkay,
        arg0: 0,
        arg1: request.arg0,
        dataLength: responsePayload.length,
        dataCrc32: responseChecksum,
        magic: AdbProtocol.cmdOkay ^ 0xffffffff,
        payload: responsePayload,
      );

      await _writer!.writeMessage(response);
      print('TLS握手完成确认已发送');

      print('连接已升级为TLS加密');

    } catch (e) {
      print('TLS握手失败: $e');

      // 发送TLS握手失败响应 - 使用CLSE命令表示连接关闭
      final errorPayload = Uint8List.fromList('TLS_HANDSHAKE_FAILED'.codeUnits);
      final errorChecksum = errorPayload.fold<int>(0, (sum, byte) => sum + (byte & 0xFF));
      final errorResponse = AdbMessage(
        command: AdbProtocol.cmdClse,
        arg0: 1,
        arg1: request.arg0,
        dataLength: errorPayload.length,
        dataCrc32: errorChecksum,
        magic: AdbProtocol.cmdClse ^ 0xffffffff,
        payload: errorPayload,
      );

      await _writer!.writeMessage(errorResponse);

      throw AdbConnectionException('TLS握手失败: $e');
    }
  }

  /// 处理认证请求
  Future<void> _handleAuthRequest(AdbMessage request) async {
    _state = AdbConnectionState.authenticating;
    print('收到认证请求: authType=${request.arg0}, payload长度=${request.payload?.length ?? 0}');

    if (request.arg0 == AdbProtocol.authTypeToken) {
      print('DEBUG: 开始标准ADB认证流程（对标Kadb实现）');

      // Kadb的认证策略：首先尝试签名认证，如果失败再发送公钥
      print('首先尝试签名认证...');

      // 使用私钥对token进行签名
      final signature = keyPair.signPayload(request.payload!);
      print('生成RSA签名: ${signature.length} 字节');

      // 发送签名
      await _writer!.writeAuth(AdbProtocol.authTypeSignature, signature);
      print('签名已发送，等待设备响应...');

      // 读取设备响应
      print('DEBUG: 等待设备对签名的响应...');
      final deviceResponse = await _reader!.readMessage().timeout(
        Duration(seconds: 30), // 增加到30秒
        onTimeout: () {
          throw TimeoutException('等待设备签名响应超时');
        },
      );

      print('DEBUG: 收到设备响应，命令: ${deviceResponse.command} (${deviceResponse.command.toRadixString(16)})');
      print('收到设备对签名的响应: ${AdbProtocol.getCommandName(deviceResponse.command)}');

      // 调试：检查响应类型
      print('DEBUG: 响应命令值: ${deviceResponse.command}');
      print('DEBUG: CNXN命令值: ${AdbProtocol.cmdCnxn}');
      print('DEBUG: AUTH命令值: ${AdbProtocol.cmdAuth}');

      if (deviceResponse.command == AdbProtocol.cmdCnxn) {
        // 签名认证成功！
        print('✅ 签名认证成功，连接已建立！');
        await _handleConnectionConfirmation(deviceResponse);
        return;
      }

      if (deviceResponse.command == AdbProtocol.cmdAuth) {
        // 签名认证失败，设备不认识这个密钥，需要提供公钥
        print('签名认证失败，设备需要公钥认证');
        print('发送RSA公钥进行认证...');

        try {
          final publicKey = keyPair.getAdbPublicKey();
          print('DEBUG: 公钥长度: ${publicKey.length} 字节');
          print('DEBUG: 公钥格式验证...');

          // 验证公钥格式
          final isValidFormat = AndroidPubkey.verifyPublicKeyFormat(publicKey);
          print('DEBUG: 公钥格式验证结果: $isValidFormat');

          // 打印公钥的前几个字节用于调试
          print('DEBUG: 公钥前16字节 (十六进制): ${publicKey.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

          // 检查公钥长度是否合理
          if (publicKey.length > 1000) {
            throw AdbAuthException('公钥长度异常: ${publicKey.length} 字节');
          }

          await _writer!.writeAuth(AdbProtocol.authTypeRsaPublic, publicKey);
          print('RSA公钥已发送，等待设备响应...');
        } catch (e) {
          print('DEBUG: 公钥发送失败: $e');
          rethrow;
        }

        // 等待最终连接确认
        print('等待最终连接确认（15秒超时）...');
        final finalResponse = await _reader!.readMessage().timeout(
          Duration(seconds: 15),
          onTimeout: () {
            print('⏰ 等待最终连接确认超时 - 设备可能在处理公钥');
            throw TimeoutException('等待最终连接确认超时 - 设备可能需要手动授权');
          },
        );

        print('DEBUG: 收到最终响应 - 命令: ${finalResponse.command} (${finalResponse.command.toRadixString(16)})');
        print('收到最终响应: ${AdbProtocol.getCommandName(finalResponse.command)}');

        if (finalResponse.command == AdbProtocol.cmdCnxn) {
          print('✅ 公钥认证成功，连接已建立！');
          await _handleConnectionConfirmation(finalResponse);
        } else if (finalResponse.command == AdbProtocol.cmdAuth) {
          // 设备可能需要其他认证方式
          print('⚠️  设备返回AUTH响应，可能需要其他认证方式');
          print('  认证类型: ${finalResponse.arg0}');
          if (finalResponse.payload != null) {
            final payloadStr = String.fromCharCodes(finalResponse.payload!);
            print('  载荷信息: $payloadStr');
          }
          throw AdbAuthException('设备拒绝公钥认证，可能需要手动授权或ADB调试未开启');
        } else {
          throw AdbAuthException('认证失败，收到意外响应: ${AdbProtocol.getCommandName(finalResponse.command)}');
        }
      } else {
        throw AdbAuthException('签名认证收到意外响应: ${AdbProtocol.getCommandName(deviceResponse.command)}');
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
