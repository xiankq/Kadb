import 'dart:async';
import 'dart:typed_data';
import '../security/adb_key_pair.dart';
import '../security/cert_utils.dart';
import 'adb_message.dart';
import 'adb_protocol.dart';
import 'adb_reader.dart';
import 'adb_writer.dart';
import '../queue/adb_message_queue.dart';
import '../stream/adb_stream.dart';
import '../transport/transport_channel.dart';
import '../transport/socket_transport.dart';
import '../utils/logging.dart';

/// ADB连接类，负责ADB协议的连接管理和流操作
class AdbConnection {
  final AdbKeyPair _keyPair;
  final Duration ioTimeout;
  final bool _debug;

  late AdbMessageQueue _messageQueue;
  late AdbWriter _writer;
  late TransportChannel _currentChannel;
  bool _closed = false;

  Timer? _heartbeatTimer;
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  /// 创建ADB连接实例
  AdbConnection({
    required AdbKeyPair keyPair,
    this.ioTimeout = const Duration(seconds: 30),
    bool debug = false,
  }) : _keyPair = keyPair,
       _debug = debug;

  /// 连接到ADB服务器
  Future<void> connect(String host, int port, {bool useTls = false}) async {
    if (_closed) throw StateError('连接已关闭');

    Logging.status('正在连接到 $host:$port...');

    try {
      await _establishConnection(host, port);
      await _performHandshake();
      _startHeartbeat();

      Logging.status('ADB连接成功建立');
    } catch (e) {
      await close();
      rethrow;
    }
  }

  /// 执行握手流程
  Future<void> _performHandshake() async {
    final systemIdentity = CertUtils.generateSystemIdentity();
    final connectPayload = 'host::$systemIdentity\u0000';

    await _writer.writeConnect(
      version: AdbProtocol.version,
      maxData: AdbProtocol.maxPayload,
      systemIdentityString: connectPayload,
    );

    await _handleAuthentication(systemIdentity);
  }

  /// 启动心跳检测
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_closed) return;
      // 简单的心跳检测
    });
  }

  /// 建立网络连接
  Future<void> _establishConnection(String host, int port) async {
    final socketChannel = SocketTransportChannel();
    await socketChannel.connect(host, port, timeout: ioTimeout);
    _currentChannel = socketChannel;

    final reader = AdbReader((int length) async {
      final buffer = Uint8List(length);
      await _currentChannel.readExactly(buffer, ioTimeout);
      return buffer.toList();
    }, debug: _debug);

    _writer = AdbWriter((List<int> data) async {
      await _currentChannel.write(Uint8List.fromList(data), ioTimeout);
    }, debug: _debug);

    _messageQueue = AdbMessageQueue(reader);
  }

  /// 处理认证流程
  Future<void> _handleAuthentication(String systemIdentity) async {
    try {
      AdbMessage message;

      while (true) {
        message = await _messageQueue.next();

        switch (message.command) {
          case AdbProtocol.cmdStls:
            throw UnsupportedError('TLS升级功能暂未实现');

          case AdbProtocol.cmdAuth:
            Logging.status('开始认证流程...');
            await _performAuthentication(message, systemIdentity);
            return;

          case AdbProtocol.cmdCnxn:
            Logging.status('连接成功，无需认证');
            return;

          default:
            throw Exception('未知的连接消息: ${message.command}');
        }
      }
    } catch (e) {
      Logging.error('认证流程失败: $e');
      rethrow;
    }
  }

  /// 执行认证流程
  Future<void> _performAuthentication(
    AdbMessage authMessage,
    String systemIdentity,
  ) async {
    if (authMessage.arg0 != AdbProtocol.authTypeToken) {
      throw Exception('不支持的认证类型: ${authMessage.arg0}');
    }

    final tokenData = authMessage.payload.sublist(0, authMessage.payloadLength);

    // 尝试签名认证
    final signature = _keyPair.signAdbMessagePayload(tokenData);
    await _writer.writeAuth(AdbProtocol.authTypeSignature, signature);

    // 等待设备响应
    final responseMessage = await _messageQueue.next();

    if (responseMessage.command == AdbProtocol.cmdCnxn) {
      return;
    }

    // 签名认证失败，尝试公钥认证
    Logging.warning('签名认证失败，尝试公钥认证...');

    final publicKeyData = CertUtils.generateAuthFormatPublicKey(
      _keyPair,
      systemIdentity,
    );

    await _writer.writeAuth(AdbProtocol.authTypeRsapublickey, publicKeyData);

    // 等待最终认证结果
    final finalMessage = await _messageQueue.next();

    if (finalMessage.command == AdbProtocol.cmdCnxn) {
      Logging.status('公钥认证成功');
      return;
    }

    throw Exception('认证失败: 期望CNXN消息');
  }

  /// 打开ADB流
  Future<AdbStream> open(String destination) async {
    if (_closed) throw StateError('连接已关闭');

    final localId = _generateLocalId();
    final stream = AdbStream(
      localId: localId,
      remoteId: 0,
      destination: destination,
      messageQueue: _messageQueue,
      writer: _writer,
      debug: _debug,
    );

    try {
      await _writer.writeOpen(localId, destination);
      await stream.waitForRemoteId();
      return stream;
    } catch (e) {
      await stream.close();
      rethrow;
    }
  }

  /// 生成新的本地ID
  int _generateLocalId() {
    const maxId = 0x7FFFFFFF;
    return DateTime.now().millisecondsSinceEpoch % maxId;
  }

  /// 关闭连接
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    try {
      _messageQueue.close();
      _currentChannel.close();
    } catch (e) {
      Logging.warning('关闭连接时发生错误: $e');
    }
  }

  /// 检查连接是否关闭
  bool get isClosed => _closed;

  /// 检查连接是否活跃
  bool get isActive => !_closed;

  /// 检查是否支持特定功能
  bool supportsFeature(String feature) {
    return false;
  }
}
