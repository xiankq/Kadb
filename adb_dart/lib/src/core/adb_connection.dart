/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'adb_message.dart';
import 'adb_protocol.dart';
import 'adb_reader.dart';
import 'adb_writer.dart';
import '../cert/adb_key_pair.dart';
import '../cert/cert_utils.dart';
import '../cert/base64_utils.dart';
import '../cert/android_pubkey.dart';
import '../queue/adb_message_queue.dart';
import '../pair/ssl_utils.dart';
import '../tls/tls_error_mapper.dart';
import '../stream/adb_stream.dart';
import '../transport/transport_channel.dart';
import '../transport/tls_transport_channel.dart';
import '../transport/socket_transport_channel.dart';

/// ADB连接类，管理与服务器的连接
class AdbConnection {
  final AdbReader _reader;
  final AdbWriter _writer;
  final Socket _socket;
  final Set<String> _supportedFeatures;
  final int _version;
  final int _maxPayloadSize;
  final Random _random = Random();
  final AdbMessageQueue _messageQueue;
  final Map<int, StreamController<AdbMessage>> _streamControllers = {};

  AdbConnection({
    required AdbReader reader,
    required AdbWriter writer,
    required Socket socket,
    required Set<String> supportedFeatures,
    required int version,
    required int maxPayloadSize,
  }) : _reader = reader,
       _writer = writer,
       _socket = socket,
       _supportedFeatures = supportedFeatures,
       _version = version,
       _maxPayloadSize = maxPayloadSize,
       _messageQueue = AdbMessageQueue(reader) {
    _startMessageHandling();
  }

  /// 开始处理接收到的消息
  void _startMessageHandling() {
    _messageQueue.messageStream.listen(
      (message) {
        // 处理消息队列中的消息
        _handleMessage(message);
      },
      onError: (error) {
        print('消息处理错误：$error');
        // 同时通知所有流控制器
        for (final controller in _streamControllers.values) {
          controller.addError(error);
        }
      },
    );
  }

  /// 处理消息
  void _handleMessage(AdbMessage message) {
    final localId = message.arg1;

    // 检查是否有对应的流控制器
    final streamController = _streamControllers[localId];
    if (streamController != null) {
      streamController.add(message);
    }
  }

  /// 打开新的流
  Future<AdbStream> open(String destination) async {
    final localId = _generateId();

    try {
      await _writer.writeOpen(localId, destination);

      // 等待OKAY响应
      final response = await _waitForMessage(localId, AdbProtocol.cmdOkay);
      final remoteId = response.arg0;

      return AdbStream(
        connection: this,
        localId: localId,
        remoteId: remoteId,
        maxPayloadSize: _maxPayloadSize,
      );
    } catch (e) {
      // 清理pending状态 - 消息队列会自动处理
      rethrow;
    }
  }

  /// 检查是否支持某个特性
  bool supportsFeature(String feature) {
    return _supportedFeatures.contains(feature);
  }

  /// 生成新的ID
  int _generateId() {
    return _random.nextInt(0x7FFFFFFF);
  }

  /// 等待特定消息
  Future<AdbMessage> _waitForMessage(int localId, int expectedCommand) async {
    return _messageQueue.waitForMessage(localId, expectedCommand);
  }

  /// 发送OKAY消息
  Future<void> sendOkay(int localId, int remoteId) async {
    await _writer.writeOkay(localId, remoteId);
  }

  /// 发送WRITE消息
  Future<void> sendWrite(int localId, int remoteId, List<int> data) async {
    await _writer.writeWrite(localId, remoteId, data);
  }

  /// 发送CLOSE消息
  Future<void> sendClose(int localId, int remoteId) async {
    await _writer.writeClose(localId, remoteId);
    // 清理流控制器
    _streamControllers.remove(localId)?.close();
  }

  /// 注册流处理器
  void registerStreamController(int localId, AdbStream stream) {
    _messageQueue.registerStreamHandler(localId, stream);
  }
  
  /// 注销流处理器
  void unregisterStreamController(int localId) {
    _messageQueue.unregisterStreamHandler(localId);
  }

  /// 关闭连接
  Future<void> close() async {
    try {
      _messageQueue.close();
    } catch (e) {
      print('关闭消息队列时出错: $e');
    }
    
    try {
      _reader.close();
    } catch (e) {
      print('关闭读取器时出错: $e');
    }
    
    try {
      _writer.close();
    } catch (e) {
      print('关闭写入器时出错: $e');
    }
    
    try {
      await _socket.close();
    } catch (e) {
      print('关闭socket时出错: $e');
    }
  }

  /// 连接到ADB服务器
  static Future<AdbConnection> connect({
    required String host,
    required int port,
    required AdbKeyPair keyPair,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration ioTimeout = Duration.zero,
  }) async {
    print('开始连接到ADB服务器: $host:$port');
    Socket? socket;
    AdbReader? reader;
    AdbWriter? writer;

    try {
      // 建立socket连接
      socket = await Socket.connect(host, port, timeout: connectTimeout);
      final channel = SocketTransportChannel(socket);
      reader = AdbReader(channel);
      writer = AdbWriter(channel);

      print('正在发送连接消息...');
      // 发送连接消息
      await writer.writeConnect();

      print('等待服务器响应...');
        AdbMessage message;
      
      while (true) {
        print('读取下一条消息...');
        try {
          message = await reader!.readMessage().timeout(const Duration(seconds: 30));
          print('接收到消息: ${message.command.toRadixString(16)}');
        } catch (e) {
          print('读取消息失败: $e');
          rethrow;
        }

        switch (message.command) {
          case AdbProtocol.cmdStls:
            print('收到STLS请求，正在建立TLS连接...');
            // 实现TLS支持
            await writer!.writeStls(message.arg0);

            try {
              final sslContext = SslUtils.getSslContext(keyPair);
              final secureSocket = await SslUtils.createTlsClient(
                host,
                port,
                keyPair,
              );

              // 执行TLS握手
              await SslUtils.handshake(
                secureSocket,
                const Duration(seconds: 30),
              );

              print('TLS握手成功，切换到加密通道...');

              // 关闭当前的reader和writer
              reader.close();
              writer.close();

              // 创建新的基于TLS的reader和writer
              // 这里需要将SecureSocket适配到我们的TransportChannel接口
              final tlsChannel = _createTlsTransportChannel(secureSocket);
              reader = AdbReader(tlsChannel);
              writer = AdbWriter(tlsChannel);

              // 继续读取消息
              message = await reader.readMessage();
            } catch (t) {
              throw TlsErrorMapper.map(t);
            }

          case AdbProtocol.cmdAuth:
            if (message.arg0 != AdbProtocol.authTypeToken) {
              throw Exception('不支持的认证类型：${message.arg0}');
            }

            print('收到认证请求，正在发送签名...');
            // 使用签名进行认证
            final signature = await keyPair.signPayload(message);
            print('签名长度：${signature.length}');
            await writer!.writeAuth(AdbProtocol.authTypeSignature, signature);

            print('等待认证响应...');
            // 等待响应
            message = await reader.readMessage();

            // 如果还需要公钥认证
            if (message.command == AdbProtocol.cmdAuth) {
              print('需要公钥认证，正在发送公钥...');
              // 实现公钥认证
              final publicKeyData = await _generateAdbPublicKey(keyPair);
              await writer!.writeAuth(AdbProtocol.authTypeRsaPublic, publicKeyData);
              print('公钥已发送，等待响应...');
              message = await reader.readMessage();
            }
            break;

          case AdbProtocol.cmdCnxc:
            print('收到连接确认消息，正在创建连接...');
            // 连接成功，解析连接信息
            final connectionString = String.fromCharCodes(message.payload);
            print('连接字符串：$connectionString');
            final features = _parseFeatures(connectionString);
            print('支持的特性：$features');

            final connection = AdbConnection(
              reader: reader,
              writer: writer!,
              socket: socket,
              supportedFeatures: features,
              version: message.arg0,
              maxPayloadSize: message.arg1,
            );

            print('连接创建成功！');
            return connection;

          default:
            throw Exception('连接失败：收到意外的消息类型 ${message.command}');
        }
      }
    } catch (e) {
      print('连接过程出错: $e');
      // 清理资源
      try {
        reader?.close();
      } catch (_) {}
      try {
        writer?.close();
      } catch (_) {}
      try {
        socket?.close();
      } catch (_) {}
      rethrow;
    }
  }

  /// 生成ADB公钥
  static Future<List<int>> _generateAdbPublicKey(AdbKeyPair keyPair) async {
    try {
      print('正在生成ADB公钥格式...');

      // 获取公钥的Android格式
      final androidFormat = await keyPair.toAdbFormat();

      // 使用专业的Base64编码
      final base64Encoded = Base64Utils.encode(androidFormat);

      // 添加设备名称（注意：Kadb的实现中有一个额外的"}"，我们需要保持一致）
      final deviceName = CertUtils.getDefaultDeviceName();
      final result = '$base64Encoded $deviceName}';

      print('ADB公钥生成完成，长度: ${result.length}');
      return result.codeUnits;
    } catch (e) {
      throw Exception('生成ADB公钥失败：$e');
    }
  }

  /// Base64编码实现（使用专业版本）
  static String base64Encode(List<int> data) {
    return Base64Utils.encode(data);
  }

  /// 解析特性列表
  static Set<String> _parseFeatures(String connectionString) {
    final featuresMatch = RegExp(
      r'features=([^;]+)',
    ).firstMatch(connectionString);
    if (featuresMatch == null) {
      throw Exception('无法从连接字符串解析特性：$connectionString');
    }

    final featuresStr = featuresMatch.group(1)!;
    return featuresStr.split(',').toSet();
  }

  /// 创建TLS传输通道
  static TransportChannel _createTlsTransportChannel(
    SecureSocket secureSocket,
  ) {
    return TlsTransportChannel(secureSocket);
  }
}
