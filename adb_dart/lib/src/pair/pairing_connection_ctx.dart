/// 设备配对连接上下文
/// 处理WiFi设备配对的完整流程
library pairing_connection_ctx;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'pairing_auth_ctx.dart';
import '../cert/adb_key_pair.dart';
import '../exception/adb_exceptions.dart';
import '../tls/ssl_utils.dart';

/// 配对协议常量（对标Kadb实现）
class PairingProtocol {
  /// 最大对等信息大小
  static const int peerInfoMaxSize = 1 << 13; // 8192字节

  /// ADB RSA公钥类型
  static const int adbRsaPubKey = 0;

  /// ADB设备GUID类型
  static const int adbDeviceGuid = 0;

  /// 当前密钥头部版本
  static const int currentKeyHeaderVersion = 1;

  /// 最小支持的密钥头部版本
  static const int minSupportedKeyHeaderVersion = 1;

  /// 最大支持的密钥头部版本
  static const int maxSupportedKeyHeaderVersion = 1;

  /// 最大载荷大小
  static const int maxPayloadSize = 2 * peerInfoMaxSize;

  /// 配对数据包头部大小
  static const int pairingPacketHeaderSize = 6;

  /// SPAKE2消息类型
  static const int spake2Msg = 0;

  /// 对等信息类型
  static const int peerInfo = 1;
}

/// 配对协议数据包头部
class PairingPacketHeader {
  final int version;
  final int type;
  final int payloadSize;

  PairingPacketHeader(this.version, this.type, this.payloadSize);

  /// 序列化到字节数组
  Uint8List serialize() {
    final buffer = ByteData(6);
    buffer.setUint8(0, version);
    buffer.setUint8(1, type);
    buffer.setUint32(2, payloadSize, Endian.big);
    return buffer.buffer.asUint8List();
  }

  /// 从字节数组解析
  factory PairingPacketHeader.parse(Uint8List data) {
    if (data.length < 6) {
      throw AdbPairAuthException('无效的数据包头部');
    }

    final buffer = ByteData.view(data.buffer);
    final version = buffer.getUint8(0);
    final type = buffer.getUint8(1);
    final payloadSize = buffer.getUint32(2, Endian.big);

    return PairingPacketHeader(version, type, payloadSize);
  }
}

/// 对等节点信息
class PeerInfo {
  final int type;
  final Uint8List data;

  PeerInfo(this.type, this.data);

  /// 序列化到字节数组
  Uint8List serialize() {
    final buffer = ByteData(1 + PairingProtocol.peerInfoMaxSize);
    buffer.setUint8(0, type);

    final dataToWrite = data.length > PairingProtocol.peerInfoMaxSize - 1
        ? data.sublist(0, PairingProtocol.peerInfoMaxSize - 1)
        : data;

    for (int i = 0; i < dataToWrite.length; i++) {
      buffer.setUint8(1 + i, dataToWrite[i]);
    }

    return buffer.buffer.asUint8List();
  }

  /// 从字节数组解析
  factory PeerInfo.parse(Uint8List data) {
    if (data.isEmpty) {
      throw AdbPairAuthException('无效的对等节点信息');
    }

    final type = data[0];
    final infoData = data.length > 1 ? data.sublist(1) : Uint8List(0);
    return PeerInfo(type, infoData);
  }
}

/// 配对连接上下文
class PairingConnectionCtx {
  final String host;
  final int port;
  final Uint8List password;
  final AdbKeyPair keyPair;
  final String deviceName;

  late final PairingAuthCtx _authCtx;
  late final PeerInfo _peerInfo;
  Socket? _socket;
  bool _isConnected = false;

  PairingConnectionCtx({
    required this.host,
    required this.port,
    required this.password,
    required this.keyPair,
    required this.deviceName,
  }) {
    // 初始化对等节点信息
    final publicKeyData = keyPair.getAdbPublicKey();
    _peerInfo = PeerInfo(PairingProtocol.adbRsaPubKey, publicKeyData);

    // 创建认证上下文（Alice角色）
    _authCtx = createAlice(password);
  }

  /// 开始配对过程
  Future<void> start() async {
    if (_isConnected) {
      throw AdbPairAuthException('连接已建立');
    }

    try {
      // 建立TCP连接
      _socket = await Socket.connect(host, port);
      _socket!.setOption(SocketOption.tcpNoDelay, true);

      // 执行配对协议
      await _performPairing();

      _isConnected = true;
      print('设备配对成功');
    } catch (e) {
      await close();
      if (e is AdbPairAuthException) {
        rethrow;
      }
      throw AdbPairAuthException('配对失败: $e');
    }
  }

  /// 执行配对协议
  Future<void> _performPairing() async {
    // 阶段1: 交换SPAKE2消息
    await _exchangeSpake2Msgs();

    // 阶段2: 交换对等节点信息
    await _exchangePeerInfo();
  }

  /// 交换SPAKE2消息
  Future<void> _exchangeSpake2Msgs() async {
    // 发送我们的SPAKE2消息
    final ourMsg = _authCtx.msg;
    _writePacket(PairingProtocol.spake2Msg, ourMsg);

    // 接收对方的SPAKE2消息
    final theirHeader = await _readHeader();
    if (theirHeader.type != PairingProtocol.spake2Msg) {
      throw AdbPairAuthException('意外的消息类型: ${theirHeader.type}');
    }

    final theirMsg = await _readPayload(theirHeader.payloadSize);
    final success = _authCtx.initCipher(theirMsg);

    if (!success) {
      throw AdbPairAuthException('SPAKE2消息交换失败');
    }
  }

  /// 交换对等节点信息
  Future<void> _exchangePeerInfo() async {
    // 加密并发送我们的对等节点信息
    final peerInfoData = _peerInfo.serialize();
    final encryptedData = _authCtx.encrypt(peerInfoData);
    if (encryptedData == null) {
      throw AdbPairAuthException('无法加密对等节点信息');
    }

    _writePacket(PairingProtocol.peerInfo, encryptedData);

    // 接收并解密对方的对等节点信息
    final theirHeader = await _readHeader();
    if (theirHeader.type != PairingProtocol.peerInfo) {
      throw AdbPairAuthException('意外的消息类型: ${theirHeader.type}');
    }

    final encryptedPeerData = await _readPayload(theirHeader.payloadSize);
    final decryptedData = _authCtx.decrypt(encryptedPeerData);
    if (decryptedData == null) {
      throw AdbPairAuthException('无法解密对等节点信息');
    }

    final theirPeerInfo = PeerInfo.parse(decryptedData);
    print(
        '收到设备对等节点信息: type=${theirPeerInfo.type}, data长度=${theirPeerInfo.data.length}');
  }

  /// 写入数据包
  void _writePacket(int type, Uint8List payload) {
    final header = PairingPacketHeader(
      PairingProtocol.currentKeyHeaderVersion,
      type,
      payload.length,
    );

    final headerData = header.serialize();
    _socket!.add(headerData);
    _socket!.add(payload);
    _socket!.flush();
  }

  /// 读取数据包头部
  Future<PairingPacketHeader> _readHeader() async {
    final headerData =
        await _readExact(PairingProtocol.pairingPacketHeaderSize);
    return PairingPacketHeader.parse(headerData);
  }

  /// 读取载荷数据
  Future<Uint8List> _readPayload(int length) async {
    return await _readExact(length);
  }

  /// 精确读取指定数量的字节
  Future<Uint8List> _readExact(int length) async {
    final buffer = Uint8List(length);
    int totalRead = 0;

    await for (final data in _socket!) {
      final remaining = length - totalRead;
      final toRead = data.length < remaining ? data.length : remaining;

      buffer.setAll(totalRead, data.sublist(0, toRead));
      totalRead += toRead;

      if (totalRead >= length) {
        return buffer;
      }
    }

    throw AdbPairAuthException('连接在读取完成前关闭');
  }

  /// 关闭连接
  Future<void> close() async {
    _isConnected = false;

    try {
      _authCtx.destroy();
    } catch (e) {
      // 忽略销毁错误
    }

    try {
      await _socket?.close();
    } catch (e) {
      // 忽略关闭错误
    } finally {
      _socket = null;
    }
  }
}

/// 设备配对管理器
class DevicePairingManager {
  /// 配对设备
  static Future<void> pairDevice({
    required String host,
    required int port,
    required String pairingCode,
    required AdbKeyPair keyPair,
    String deviceName = 'adb_dart',
  }) async {
    final password = Uint8List.fromList(pairingCode.codeUnits);

    final pairingCtx = PairingConnectionCtx(
      host: host,
      port: port,
      password: password,
      keyPair: keyPair,
      deviceName: deviceName,
    );

    try {
      await pairingCtx.start();
      print('设备配对成功: $host:$port');
    } finally {
      await pairingCtx.close();
    }
  }
}

/// TLS安全的设备配对连接上下文
/// 在标准配对协议基础上添加TLS加密层
class TlsPairingConnectionCtx extends PairingConnectionCtx {
  SecureSocket? _secureSocket;
  final bool _useTls;

  TlsPairingConnectionCtx({
    required super.host,
    required super.port,
    required super.password,
    required super.keyPair,
    required super.deviceName,
    bool useTls = true,
  }) : _useTls = useTls;

  @override
  Future<void> start() async {
    if (_isConnected) {
      throw AdbPairAuthException('连接已建立');
    }

    try {
      // 建立TCP连接
      _socket = await Socket.connect(host, port);
      _socket!.setOption(SocketOption.tcpNoDelay, true);

      // 如果使用TLS，升级到安全连接
      if (_useTls) {
        print('升级到TLS安全连接...');
        _secureSocket = await SslUtils.createSecureSocket(
          _socket!,
          host,
          port,
          isServer: false, // 我们是客户端
          keyPair: keyPair,
        );

        // 执行TLS握手
        await SslUtils.performTlsHandshake(_secureSocket!);
        print('TLS握手完成');
      }

      // 执行配对协议
      await _performPairing();

      _isConnected = true;
      print('设备配对成功（TLS加密）');
    } catch (e) {
      await close();
      if (e is AdbPairAuthException) {
        rethrow;
      }
      throw AdbPairAuthException('配对失败: $e');
    }
  }

  @override
  Future<void> close() async {
    _isConnected = false;

    try {
      _authCtx.destroy();
    } catch (e) {
      // 忽略销毁错误
    }

    try {
      await _secureSocket?.close();
    } catch (e) {
      // 忽略关闭错误
    }

    try {
      await _socket?.close();
    } catch (e) {
      // 忽略关闭错误
    } finally {
      _socket = null;
      _secureSocket = null;
    }
  }

  /// 获取TLS连接信息
  Map<String, dynamic>? getTlsInfo() {
    if (_secureSocket != null) {
      return SslUtils.getTlsInfo(_secureSocket!);
    }
    return null;
  }
}

/// TLS设备配对管理器
class TlsDevicePairingManager {
  /// 使用TLS安全配对设备
  static Future<void> pairDeviceSecurely({
    required String host,
    required int port,
    required String pairingCode,
    required AdbKeyPair keyPair,
    String deviceName = 'adb_dart',
    bool useTls = true,
  }) async {
    final password = Uint8List.fromList(pairingCode.codeUnits);

    final pairingCtx = TlsPairingConnectionCtx(
      host: host,
      port: port,
      password: password,
      keyPair: keyPair,
      deviceName: deviceName,
      useTls: useTls,
    );

    try {
      await pairingCtx.start();
      print('设备安全配对成功: $host:$port');

      // 显示TLS连接信息
      final tlsInfo = pairingCtx.getTlsInfo();
      if (tlsInfo != null) {
        print('TLS连接详情:');
        print('  协议: ${tlsInfo['protocol']}');
        print('  加密套件: ${tlsInfo['cipher']}');
        print('  安全连接: ${tlsInfo['isSecure']}');
      }
    } finally {
      await pairingCtx.close();
    }
  }

  /// 检查配对码格式
  static bool validatePairingCode(String pairingCode) {
    // ADB配对码通常为6位数字
    if (pairingCode.length != 6) return false;
    return RegExp(r'^\d{6}$').hasMatch(pairingCode);
  }

  /// 生成配对请求二维码内容
  static String generatePairingQrContent({
    required String host,
    required int port,
    required String deviceName,
  }) {
    // 格式: adb://host:port?name=deviceName
    return 'adb://$host:$port?name=$deviceName';
  }
}
