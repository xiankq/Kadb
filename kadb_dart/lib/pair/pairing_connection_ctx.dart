import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:kadb_dart/cert/adb_key_pair.dart';
import 'package:kadb_dart/cert/cert_utils.dart';
import 'package:kadb_dart/pair/pairing_auth_ctx.dart';

/// 配对连接上下文
/// 管理ADB设备配对连接的TLS通信和认证流程
class PairingConnectionCtx {
  final String _host;
  final int _port;
  final Uint8List _password;
  final AdbKeyPair _keyPair;
  final String _deviceName;
  
  late Socket _socket;
  late IOSink _outputStream;
  late Stream<List<int>> _inputStream;
  
  PairingAuthCtx? _pairingAuthCtx;
  PairingState _state = PairingState.ready;
  
  PairingConnectionCtx({
    required String host,
    required int port,
    required Uint8List password,
    required AdbKeyPair keyPair,
    required String deviceName,
  }) : _host = host,
       _port = port,
       _password = password,
       _keyPair = keyPair,
       _deviceName = deviceName;
  
  /// 启动配对连接
  Future<void> start() async {
    if (_state != PairingState.ready) {
      throw Exception('连接未就绪');
    }
    
    _state = PairingState.exchangingMsgs;
    
    // 启动工作线程
    await _setupTlsConnection();
    
    while (true) {
      switch (_state) {
        case PairingState.exchangingMsgs:
          if (!await _doExchangeMsgs()) {
            _notifyResult();
            throw Exception('消息交换失败');
          }
          _state = PairingState.exchangingPeerInfo;
          break;
          
        case PairingState.exchangingPeerInfo:
          if (!await _doExchangePeerInfo()) {
            _notifyResult();
            throw Exception('无法交换对等方信息');
          }
          _notifyResult();
          return;
          
        case PairingState.ready:
        case PairingState.stopped:
          throw Exception('连接已关闭');
      }
    }
  }
  
  /// 通知结果
  void _notifyResult() {
    _state = PairingState.stopped;
  }
  
  /// 设置TLS连接
  Future<void> _setupTlsConnection() async {
    final socket = await Socket.connect(_host, _port);
    _socket = socket;
    
    _outputStream = socket;
    _inputStream = socket;
    
    // 创建配对认证上下文
    final passwordBytes = Uint8List(_password.length);
    passwordBytes.setRange(0, _password.length, _password);
    
    final pairingAuthCtx = PairingAuthCtxFactory.createAlice(passwordBytes);
    _pairingAuthCtx = pairingAuthCtx;
  }
  
  /// 写入数据包头
  Future<void> _writeHeader(PairingPacketHeader header, Uint8List payload) async {
    final buffer = ByteData(PairingPacketHeader.pairingPacketHeaderSize);
    header.writeTo(buffer);
    
    _outputStream.add(buffer.buffer.asUint8List());
    _outputStream.add(payload);
    await _outputStream.flush();
  }
  
  /// 读取数据包头
  Future<PairingPacketHeader?> _readHeader() async {
    final bytes = await _readBytes(PairingPacketHeader.pairingPacketHeaderSize);
    if (bytes.length != PairingPacketHeader.pairingPacketHeaderSize) {
      return null;
    }
    
    final buffer = ByteData.view(bytes.buffer);
    return PairingPacketHeader.readFrom(buffer);
  }
  
  /// 读取指定长度的字节
  Future<Uint8List> _readBytes(int length) async {
    final completer = Completer<Uint8List>();
    final buffer = <int>[];
    
    late StreamSubscription<List<int>> subscription;
    subscription = _inputStream.listen((data) {
      buffer.addAll(data);
      if (buffer.length >= length) {
        subscription.cancel();
        completer.complete(Uint8List.fromList(buffer.sublist(0, length)));
      }
    });
    
    return completer.future;
  }
  
  /// 创建数据包头
  PairingPacketHeader _createHeader(int type, int payloadSize) {
    return PairingPacketHeader(
      PairingPacketHeader.currentKeyHeaderVersion,
      type,
      payloadSize,
    );
  }
  
  /// 检查包头类型
  bool _checkHeaderType(int expected, int actual) {
    return expected == actual;
  }
  
  /// 执行消息交换
  Future<bool> _doExchangeMsgs() async {
    final msg = _pairingAuthCtx!.msg;
    final ourHeader = _createHeader(PairingPacketHeader.spake2Msg, msg.length);
    
    // 写入SPAKE2消息
    await _writeHeader(ourHeader, msg);
    
    // 读取对等方的SPAKE2消息包头
    final theirHeader = await _readHeader();
    if (theirHeader == null || 
        !_checkHeaderType(PairingPacketHeader.spake2Msg, theirHeader.type)) {
      return false;
    }
    
    // 读取SPAKE2消息负载并初始化加密
    final theirMsg = await _readBytes(theirHeader.payloadSize);
    try {
      return _pairingAuthCtx!.initCipher(theirMsg);
    } catch (e) {
      throw Exception('初始化加密失败: $e');
    }
  }
  
  /// 执行对等方信息交换
  Future<bool> _doExchangePeerInfo() async {
    // 加密对等方信息
    final peerInfo = PeerInfo(
      PeerInfo.adbRsaPubKey,
      CertUtils.encodeWithName(_keyPair.publicKey, _deviceName),
    );
    
    final buffer = ByteData(PeerInfo.maxPeerInfoSize);
    peerInfo.writeTo(buffer);
    
    final outBuffer = _pairingAuthCtx!.encrypt(buffer.buffer.asUint8List());
    if (outBuffer == null) {
      return false;
    }
    
    // 写入数据包头
    final ourHeader = _createHeader(PairingPacketHeader.peerInfo, outBuffer.length);
    await _writeHeader(ourHeader, outBuffer);
    
    // 读取对等方的数据包头
    final theirHeader = await _readHeader();
    if (theirHeader == null || 
        !_checkHeaderType(PairingPacketHeader.peerInfo, theirHeader.type)) {
      return false;
    }
    
    // 读取加密的对等方证书
    final theirMsg = await _readBytes(theirHeader.payloadSize);
    final decryptedMsg = _pairingAuthCtx!.decrypt(theirMsg);
    if (decryptedMsg == null) {
      return false;
    }
    
    // 解密后的消息应包含对等方信息
    if (decryptedMsg.length != PeerInfo.maxPeerInfoSize) {
      return false;
    }
    
    PeerInfo.readFrom(ByteData.view(decryptedMsg.buffer));
    return true;
  }
  
  /// 关闭连接
  Future<void> close() async {
    // 清空密码
    for (int i = 0; i < _password.length; i++) {
      _password[i] = 0;
    }
    
    try {
      await _socket.close();
    } catch (_) {}
    
    if (_state != PairingState.ready) {
      _pairingAuthCtx?.destroy();
    }
  }
}

/// 配对状态枚举
enum PairingState {
  ready,
  exchangingMsgs,
  exchangingPeerInfo,
  stopped,
}

/// 配对角色枚举
enum PairingRole {
  client,
  server,
}

/// 对等方信息类
class PeerInfo {
  final int type;
  final Uint8List data;
  
  PeerInfo(this.type, Uint8List data) : data = Uint8List(maxPeerInfoSize - 1) {
    final length = data.length < maxPeerInfoSize - 1 ? data.length : maxPeerInfoSize - 1;
    this.data.setRange(0, length, data.sublist(0, length));
  }
  
  /// 写入到缓冲区
  void writeTo(ByteData buffer) {
    buffer.setUint8(0, type);
    for (int i = 0; i < data.length; i++) {
      buffer.setUint8(i + 1, data[i]);
    }
  }
  
  @override
  String toString() => 'PeerInfo{type: $type, data: ${data.length} bytes}';
  
  /// 从缓冲区读取
  static PeerInfo readFrom(ByteData buffer) {
    final type = buffer.getUint8(0);
    final data = Uint8List(maxPeerInfoSize - 1);
    for (int i = 0; i < data.length; i++) {
      data[i] = buffer.getUint8(i + 1);
    }
    return PeerInfo(type, data);
  }
  
  static const int maxPeerInfoSize = 1 << 13;
  static const int adbRsaPubKey = 0;
  static const int adbDeviceGuid = 0;
}

/// 配对数据包头类
class PairingPacketHeader {
  final int version;
  final int type;
  final int payloadSize;
  
  PairingPacketHeader(this.version, this.type, this.payloadSize);
  
  /// 写入到缓冲区
  void writeTo(ByteData buffer) {
    buffer.setUint8(0, version);
    buffer.setUint8(1, type);
    buffer.setUint32(2, payloadSize, Endian.big);
  }
  
  @override
  String toString() => 'PairingPacketHeader{version: $version, type: $type, payloadSize: $payloadSize}';
  
  /// 从缓冲区读取
  static PairingPacketHeader? readFrom(ByteData buffer) {
    final version = buffer.getUint8(0);
    final type = buffer.getUint8(1);
    final payload = buffer.getUint32(2, Endian.big);
    
    if (version < minSupportedKeyHeaderVersion || version > maxSupportedKeyHeaderVersion) {
      return null;
    }
    
    if (type != spake2Msg && type != peerInfo) {
      return null;
    }
    
    if (payload <= 0 || payload > maxPayloadSize) {
      return null;
    }
    
    return PairingPacketHeader(version, type, payload);
  }
  
  static const int currentKeyHeaderVersion = 1;
  static const int minSupportedKeyHeaderVersion = 1;
  static const int maxSupportedKeyHeaderVersion = 1;
  static const int maxPayloadSize = 2 * PeerInfo.maxPeerInfoSize;
  static const int pairingPacketHeaderSize = 6;
  static const int spake2Msg = 0;
  static const int peerInfo = 1;
}