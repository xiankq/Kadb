/// ADB连接管理器
///
/// 负责管理ADB连接的生命周期，包括：
/// - 建立TCP连接
/// - 执行ADB握手流程（CNXN/AUTH）
/// - 处理认证（RSA签名）
/// - 创建和管理数据流
/// - 连接状态管理
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'adb_protocol.dart';
import 'adb_message.dart';
import 'adb_reader.dart';
import 'adb_writer.dart';
import '../transport/transport_channel.dart';
import '../cert/adb_key_pair.dart';
import '../cert/android_pubkey.dart';
import '../cert/cert_utils.dart';

/// ADB连接类
class AdbConnection {
  final AdbReader _reader;
  final AdbWriter _writer;
  final TransportChannel _channel;
  final Set<String> _supportedFeatures;
  final int _version;
  final int _maxPayloadSize;
  final Random _random = Random();
  bool _isClosed = false;

  AdbConnection._({
    required AdbReader reader,
    required AdbWriter writer,
    required TransportChannel channel,
    required Set<String> supportedFeatures,
    required int version,
    required int maxPayloadSize,
  })  : _reader = reader,
        _writer = writer,
        _channel = channel,
        _supportedFeatures = supportedFeatures,
        _version = version,
        _maxPayloadSize = maxPayloadSize;

  /// 获取支持的特性集合
  Set<String> get supportedFeatures => Set.from(_supportedFeatures);

  /// 检查是否支持指定特性
  bool supportsFeature(String feature) {
    return _supportedFeatures.contains(feature);
  }

  /// 获取协议版本
  int get version => _version;

  /// 获取最大载荷大小
  int get maxPayloadSize => _maxPayloadSize;

  /// 创建新的数据流
  ///
  /// [destination] 目标服务名称，如 "shell:", "sync:", "tcp:8080"
  Future<AdbStream> openStream(String destination) async {
    if (_isClosed) {
      throw StateError('连接已关闭');
    }

    final localId = _generateLocalId();

    // 发送OPEN消息
    await _writer.writeOpen(localId, destination);

    // 等待OKAY响应
    final response = await _reader.readMessage();
    if (response.command != AdbProtocol.aOkay) {
      throw StateError(
          '打开流失败，期望OKAY，实际收到: ${AdbProtocol.getCommandString(response.command)}');
    }

    final remoteId = response.arg0;

    return AdbStream(
      reader: _reader,
      writer: _writer,
      maxPayloadSize: _maxPayloadSize,
      localId: localId,
      remoteId: remoteId,
    );
  }

  /// 生成本地流ID
  int _generateLocalId() {
    return _random.nextInt(1 << 31); // 生成正整数ID
  }

  /// 关闭连接
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    try {
      await _reader.close();
      await _writer.close();
      await _channel.close();
    } catch (e) {
      // 忽略关闭错误
    }
  }

  /// 建立ADB连接
  static Future<AdbConnection> connect({
    required String host,
    required int port,
    AdbKeyPair? keyPair,
    Duration? connectionTimeout,
    Duration? readTimeout,
    Duration? writeTimeout,
  }) async {
    // 如果未提供密钥对，生成或使用默认密钥对
    final actualKeyPair = keyPair ?? await CertUtils.generateKeyPair();

    // 创建传输通道
    final channel = await TcpTransportChannelFactory().createTcpChannel(
      host: host,
      port: port,
      connectionTimeout: connectionTimeout,
      readTimeout: readTimeout,
      writeTimeout: writeTimeout,
    );

    // 创建读取器和写入器
    final reader = StandardAdbReader(channel.inputStream);
    final writer = StandardAdbWriter(channel.outputSink);

    try {
      // 发送连接消息
      await writer.writeConnect();

      // 读取设备响应
      var response = await reader.readMessage();

      // 处理可能的STLS升级
      if (response.command == AdbProtocol.aStls) {
        // 发送STLS响应
        writer.writeStls(response.arg0);

        // 创建TLS上下文和引擎
        final sslContext = SslUtils.getSslContext(actualKeyPair);
        final tlsConfig = TlsConfig(
          useClientMode: true,
          clientCertificate: actualKeyPair.certificateData,
          clientPrivateKey: actualKeyPair.privateKeyData,
          verifyCertificate: false, // ADB通常不验证证书
        );

        // 创建TLS传输通道
        final tlsChannel = TlsTransportChannel(channel, tlsConfig);

        try {
          // 执行TLS握手
          await tlsChannel.handshake(Duration(milliseconds: ioTimeout));
          print('TLS握手成功，使用协议: ${tlsChannel.tlsInfo}');
        } catch (e) {
          throw StateError('TLS握手失败: $e');
        }

        // 重新创建读写器，使用TLS通道
        reader.close();
        writer.close();

        channel = tlsChannel;
        reader = AdbReader(channel, timeout: Duration(milliseconds: ioTimeout));
        writer = AdbWriter(channel, timeout: Duration(milliseconds: ioTimeout));

        // 读取TLS升级后的响应
        response = await reader.readMessage();
      }

      // 处理认证流程
      if (response.command == AdbProtocol.aAuth) {
        // 处理设备发送的认证挑战
        response = await _handleAuthentication(
            reader, writer, response, actualKeyPair);
      }

      // 验证连接确认
      if (response.command != AdbProtocol.aCnxn) {
        throw StateError(
            '连接失败，期望CNXN，实际收到: ${AdbProtocol.getCommandString(response.command)}');
      }

      // 解析连接信息
      final connectionInfo = _parseConnectionString(response);

      return AdbConnection._(
        reader: reader,
        writer: writer,
        channel: channel,
        supportedFeatures: connectionInfo.features,
        version: response.arg0,
        maxPayloadSize: response.arg1,
      );
    } catch (e) {
      // 连接失败时清理资源
      try {
        await reader.close();
      } catch (_) {}
      try {
        await writer.close();
      } catch (_) {}
      try {
        await channel.close();
      } catch (_) {}

      rethrow;
    }
  }

  /// 处理认证流程
  static Future<AdbMessage> _handleAuthentication(
    AdbReader reader,
    AdbWriter writer,
    AdbMessage authMessage,
    AdbKeyPair keyPair,
  ) async {
    if (authMessage.arg0 != AdbProtocol.authTypeToken) {
      throw StateError('不支持的认证类型: ${authMessage.arg0}');
    }

    // 获取Token数据
    if (authMessage.payload == null || authMessage.payload!.isEmpty) {
      throw StateError('认证消息缺少Token数据');
    }

    // 使用私钥签名Token
    final signature = keyPair.signPayload(authMessage.payload!);

    // 发送签名响应
    await writer.writeAuth(AdbProtocol.authTypeSignature, signature);

    // 读取设备响应
    var response = await reader.readMessage();

    // 如果签名验证失败，设备会发送新的AUTH消息
    if (response.command == AdbProtocol.aAuth) {
      // 发送RSA公钥
      final publicKeyData =
          AndroidPubkey.encodeWithName(keyPair.publicKey, 'adb_dart');
      await writer.writeAuth(AdbProtocol.authTypeRsaPublic, publicKeyData);

      // 等待最终响应
      response = await reader.readMessage();
    }

    return response;
  }

  /// 解析连接字符串
  static _ConnectionInfo _parseConnectionString(AdbMessage message) {
    if (message.payload == null || message.payload!.isEmpty) {
      throw StateError('连接消息缺少载荷数据');
    }

    try {
      final connectionString = String.fromCharCodes(message.payload!);

      // 解析格式: "device::key1=value1;key2=value2;"
      if (!connectionString.startsWith('device::')) {
        throw StateError('无效的连接字符串格式');
      }

      final properties = connectionString.substring('device::'.length);
      final keyValues = <String, String>{};

      for (final part in properties.split(';')) {
        if (part.isEmpty) continue;
        final equalsIndex = part.indexOf('=');
        if (equalsIndex != -1) {
          final key = part.substring(0, equalsIndex);
          final value = part.substring(equalsIndex + 1);
          keyValues[key] = value;
        }
      }

      // 解析特性列表
      final features = <String>{};
      if (keyValues.containsKey('features')) {
        features.addAll(keyValues['features']!.split(','));
      }

      return _ConnectionInfo(
        features: features,
        properties: keyValues,
      );
    } catch (e) {
      throw StateError('解析连接字符串失败: $e');
    }
  }
}

/// ADB数据流
///
/// 表示一个双向的ADB数据流，用于传输应用数据
class AdbStream {
  final AdbReader _reader;
  final AdbWriter _writer;
  final int _maxPayloadSize;
  final int _localId;
  final int _remoteId;
  bool _isClosed = false;

  AdbStream({
    required AdbReader reader,
    required AdbWriter writer,
    required int maxPayloadSize,
    required int localId,
    required int remoteId,
  })  : _reader = reader,
        _writer = writer,
        _maxPayloadSize = maxPayloadSize,
        _localId = localId,
        _remoteId = remoteId;

  /// 获取本地流ID
  int get localId => _localId;

  /// 获取远程流ID
  int get remoteId => _remoteId;

  /// 获取最大载荷大小
  int get maxPayloadSize => _maxPayloadSize;

  /// 读取数据
  Future<Uint8List?> read() async {
    if (_isClosed) return null;

    try {
      final message = await _reader.readMessage();

      if (message.command == AdbProtocol.aClse) {
        // 流已关闭
        await close();
        return null;
      }

      if (message.command == AdbProtocol.aWrte && message.arg0 == _remoteId) {
        // 发送确认
        await _writer.writeOkay(_localId, _remoteId);
        return message.payload;
      }

      throw StateError(
          '意外的消息: ${AdbProtocol.getCommandString(message.command)}');
    } catch (e) {
      if (!_isClosed) {
        await close();
      }
      rethrow;
    }
  }

  /// 写入数据
  Future<void> write(Uint8List data) async {
    if (_isClosed) {
      throw StateError('流已关闭');
    }

    try {
      await _writer.writeWrite(_localId, _remoteId, data);
    } catch (e) {
      if (!_isClosed) {
        await close();
      }
      rethrow;
    }
  }

  /// 关闭流
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    try {
      await _writer.writeClose(_localId, _remoteId);
    } catch (e) {
      // 忽略关闭错误
    }
  }
}

/// 连接信息内部类
class _ConnectionInfo {
  final Set<String> features;
  final Map<String, String> properties;

  _ConnectionInfo({
    required this.features,
    required this.properties,
  });
}
