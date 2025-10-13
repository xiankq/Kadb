import 'dart:async';
import 'dart:typed_data';
import 'package:kadb_dart/cert/adb_key_pair.dart';
import 'package:kadb_dart/cert/cert_utils.dart';
import 'package:kadb_dart/core/adb_message.dart';
import 'package:kadb_dart/core/adb_protocol.dart';
import 'package:kadb_dart/core/adb_reader.dart';
import 'package:kadb_dart/core/adb_writer.dart';
import 'package:kadb_dart/queue/adb_message_queue.dart';
import 'package:kadb_dart/stream/adb_stream.dart';
import 'package:kadb_dart/transport/transport_channel.dart' as base;
import 'package:kadb_dart/transport/socket_transport_channel.dart';

/// ADB连接类
/// 负责ADB协议的连接管理和流操作
class AdbConnection {
  static const int _maxId = 0x7FFFFFFF;

  final AdbKeyPair _keyPair;
  final Duration ioTimeout;
  final bool _debug;

  late AdbMessageQueue _messageQueue;
  late AdbWriter _writer;
  late base.TransportChannel _currentChannel;
  int _nextLocalId = 1;
  final Map<int, AdbStream> _streams = {};
  bool _closed = false;

  /// 创建ADB连接
  /// [keyPair] ADB密钥对
  /// [ioTimeout] IO操作超时时间
  /// [debug] 是否启用调试模式
  AdbConnection({
    required AdbKeyPair keyPair,
    this.ioTimeout = const Duration(seconds: 30),
    bool debug = false,
  }) : _keyPair = keyPair,
       _debug = debug;

  /// 连接到ADB服务器
  /// [host] 主机地址
  /// [port] 端口号
  /// [useTls] 是否使用TLS加密
  Future<void> connect(String host, int port, {bool useTls = false}) async {
    if (_closed) {
      throw StateError('连接已关闭');
    }

    // 建立网络连接
    await _establishConnection(host, port);

    // 生成系统身份标识
    final systemIdentity = CertUtils.generateSystemIdentity();

    // 发送初始连接请求
    // 重要修复：使用与系统ADB一致的payload格式
    // 系统ADB发送的payload是 'host::用户@主机名\u0000'，总长度25字节
    final connectPayload = 'host::$systemIdentity\u0000';

    await _writer.writeConnect(
      version: AdbProtocol.version,
      maxData: AdbProtocol.maxPayload,
      systemIdentityString: connectPayload,
    );

    // 处理认证流程
    await _handleAuthentication(systemIdentity);

    if (_debug) {
      print('✅ ADB连接成功建立');
    }
  }

  /// 建立网络连接
  Future<void> _establishConnection(String host, int port) async {
    // 创建Socket传输通道
    final socketChannel = SocketTransportChannel();
    await socketChannel.connect(host, port, timeout: ioTimeout);
    _currentChannel = socketChannel;

    // 创建读写器
    final reader = AdbReader((int length) async {
      final buffer = Uint8List(length);
      await _currentChannel.readExactly(buffer, ioTimeout);
      return buffer.toList();
    });

    _writer = AdbWriter((List<int> data) async {
      await _currentChannel.write(Uint8List.fromList(data), ioTimeout);
    });

    // 创建消息队列
    _messageQueue = AdbMessageQueue(reader);
  }

  /// 处理认证流程
  Future<void> _handleAuthentication(String systemIdentity) async {
    AdbMessage message;

    while (true) {
      message = await _messageQueue.next();

      switch (message.command) {
        case AdbProtocol.cmdStls:
          // 暂时不支持TLS升级
          throw UnsupportedError('TLS升级功能暂未实现');

        case AdbProtocol.CMD_AUTH:
          // 直接处理认证流程
          await _performAuthentication(message, systemIdentity);
          return;

        case AdbProtocol.CMD_CNXN:
          // 直接连接成功，无需认证
          return;

        default:
          throw Exception('未知的连接消息: ${message.command}');
      }
    }
  }

  /// 执行认证流程
  Future<void> _performAuthentication(AdbMessage authMessage, String systemIdentity) async {
    if (authMessage.arg0 != AdbProtocol.authTypeToken) {
      throw Exception('不支持的认证类型: ${authMessage.arg0}');
    }

    // 提取token数据
    final tokenData = authMessage.payload.sublist(0, authMessage.payloadLength);

    if (_debug) {
      print('📝 收到认证token，长度: ${tokenData.length}');
      final tokenHex = tokenData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      print('📝 Token内容: $tokenHex');
    }

    // 尝试签名认证
    final signature = _keyPair.signAdbMessagePayload(tokenData);

    if (_debug) {
      print('🔐 生成签名，长度: ${signature.length}');
      final sigHex = signature.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      print('🔐 签名前8字节: $sigHex');
    }

    // 发送签名响应
    await _writer.writeAuth(AdbProtocol.authTypeSignature, signature);

    // 等待设备响应
    final responseMessage = await _messageQueue.next();

    if (responseMessage.command == AdbProtocol.CMD_CNXN) {
      if (_debug) {
        print('✅ 签名认证成功');
      }
      return;
    }

    // 签名认证失败，尝试公钥认证
    if (_debug) {
      print('🔑 签名认证失败，尝试公钥认证...');
    }

    final publicKeyData = CertUtils.generateAuthFormatPublicKey(_keyPair, systemIdentity);

    if (_debug) {
      print('📤 发送公钥认证，长度: ${publicKeyData.length}');
      final publicKeyString = String.fromCharCodes(publicKeyData);
      print('📤 公钥内容: $publicKeyString');
      print('📤 公钥长度分析: Base64=${publicKeyString.split(' ')[0].length}, 标识符="${publicKeyString.split(' ')[1]}"');
    }

    // 发送公钥认证请求
    await _writer.writeAuth(AdbProtocol.authTypeRsapublickey, publicKeyData);

    // 等待最终认证结果
    final finalMessage = await _messageQueue.next();

    if (finalMessage.command == AdbProtocol.CMD_CNXN) {
      if (_debug) {
        print('✅ 公钥认证成功');
      }
      return;
    }

    throw Exception('认证失败: 期望CNXN消息，收到命令: 0x${finalMessage.command.toRadixString(16)}');
  }

  
  /// 打开ADB流
  /// [destination] 目标服务
  Future<AdbStream> open(String destination) async {
    if (_closed) {
      throw StateError('连接已关闭');
    }

    final localId = _newId();
    final stream = AdbStream(
      localId: localId,
      remoteId: 0,
      destination: destination,
      messageQueue: _messageQueue,
      writer: _writer,
      debug: _debug,
    );

    _streams[localId] = stream;

    // 发送打开流请求
    await _writer.writeOpen(localId, destination);

    // 等待远程ID分配
    await stream.waitForRemoteId();

    return stream;
  }

  /// 生成新的本地ID
  int _newId() {
    final id = _nextLocalId;
    _nextLocalId = (_nextLocalId + 1) % _maxId;
    return id;
  }

  /// 关闭连接
  void close() {
    if (!_closed) {
      _closed = true;
      _messageQueue.close();
      _currentChannel.close();

      // 关闭所有打开的流
      for (final stream in _streams.values) {
        stream.close();
      }
      _streams.clear();
    }
  }

  /// 检查连接是否关闭
  bool get isClosed => _closed;

  /// 检查是否支持特定功能（占位实现）
  /// [feature] 功能名称
  /// 返回是否支持该功能
  bool supportsFeature(String feature) {
    // 目前返回false，后续根据实际功能实现
    return false;
  }
}
