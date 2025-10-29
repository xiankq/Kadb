/// WiFi配对认证上下文
///
/// 处理WiFi设备配对的认证流程
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../cert/adb_key_pair.dart';
import '../cert/android_pubkey.dart';
import '../tls/ssl_utils.dart';

/// 配对角色
enum PairingRole {
  client,
  server,
}

/// 对等方信息
class PeerInfo {
  static const int ADB_RSA_PUB_KEY = 1;

  final int type;
  final Uint8List data;

  const PeerInfo({
    required this.type,
    required this.data,
  });

  /// 编码为字节数组
  Uint8List encode() {
    final buffer = ByteData(8 + data.length);
    buffer.setUint32(0, type, Endian.big);
    buffer.setUint32(4, data.length, Endian.big);
    final result = buffer.buffer.asUint8List();
    result.setAll(8, data);
    return result;
  }

  /// 从字节数组解码
  factory PeerInfo.decode(Uint8List data) {
    if (data.length < 8) {
      throw StateError('对等方信息数据太短');
    }

    final buffer = ByteData.sublistView(data);
    final type = buffer.getUint32(0, Endian.big);
    final length = buffer.getUint32(4, Endian.big);

    if (data.length < 8 + length) {
      throw StateError('对等方信息数据长度不匹配');
    }

    final infoData = data.sublist(8, 8 + length);
    return PeerInfo(type: type, data: infoData);
  }
}

/// 配对认证上下文
class PairingAuthCtx {
  static const String _exportedKeyLabel = "adb-label\u0000";
  static const int _exportKeySize = 64;

  final String host;
  final int port;
  final Uint8List password;
  final AdbKeyPair keyPair;
  final String deviceName;
  final PairingRole role;

  late final PeerInfo _peerInfo;
  SecureSocket? _sslSocket;
  bool _isAuthenticated = false;

  PairingAuthCtx({
    required this.host,
    required this.port,
    required this.password,
    required this.keyPair,
    required this.deviceName,
    this.role = PairingRole.client,
  }) {
    // 创建对等方信息
    _peerInfo = PeerInfo(
      type: PeerInfo.ADB_RSA_PUB_KEY,
      data: AndroidPubkey.encodeWithName(
        keyPair.publicKeyData,
        deviceName,
      ),
    );
  }

  /// 执行配对认证
  Future<void> authenticate() async {
    if (_isAuthenticated) {
      return;
    }

    try {
      // 建立TLS连接
      await _establishTlsConnection();

      // 执行配对协议
      await _performPairingProtocol();

      _isAuthenticated = true;
      print('WiFi配对认证成功');
    } catch (e) {
      throw StateError('WiFi配对认证失败: $e');
    }
  }

  /// 建立TLS连接
  Future<void> _establishTlsConnection() async {
    try {
      // 获取SSL上下文
      final sslContext = SslUtils.getSslContext(keyPair);

      // 连接到配对服务
      final socket = await Socket.connect(host, port);

      // 创建TLS socket
      _sslSocket = await SecureSocket.secure(
        socket,
        host,
        sslContext,
        timeout: Duration(seconds: 10),
      );

      print('TLS连接已建立');
    } catch (e) {
      throw StateError('建立TLS连接失败: $e');
    }
  }

  /// 执行配对协议
  Future<void> _performPairingProtocol() async {
    if (_sslSocket == null) {
      throw StateError('TLS连接未建立');
    }

    try {
      // 导出密钥材料
      final keyMaterial = _exportKeyingMaterial();

      // 计算认证哈希
      final authHash = _calculateAuthHash(keyMaterial);

      // 根据角色执行相应的协议步骤
      if (role == PairingRole.client) {
        await _performClientProtocol(authHash);
      } else {
        await _performServerProtocol(authHash);
      }
    } catch (e) {
      throw StateError('执行配对协议失败: $e');
    }
  }

  /// 导出密钥材料
  Uint8List _exportKeyingMaterial() {
    if (_sslSocket == null) {
      throw StateError('TLS连接未建立');
    }

    try {
      // 使用SSL工具导出密钥材料
      return SslUtils.exportKeyingMaterial(
        _sslSocket!,
        _exportedKeyLabel,
        null,
        _exportKeySize,
      );
    } catch (e) {
      throw StateError('导出密钥材料失败: $e');
    }
  }

  /// 计算认证哈希
  Uint8List _calculateAuthHash(Uint8List keyMaterial) {
    // 组合密码和对等方信息
    final data = Uint8List.fromList([
      ...password,
      ..._peerInfo.encode(),
    ]);

    // 使用SHA256计算哈希
    final digest = sha256.convert(data);
    return Uint8List.fromList(digest.bytes);
  }

  /// 执行客户端协议
  Future<void> _performClientProtocol(Uint8List authHash) async {
    try {
      // 发送认证哈希
      await _writeBytes(authHash);

      // 接收响应
      final response = await _readBytes(1);
      if (response.isEmpty || response[0] != 0) {
        throw StateError('配对认证失败：服务器拒绝了认证');
      }

      print('客户端配对协议完成');
    } catch (e) {
      throw StateError('执行客户端协议失败: $e');
    }
  }

  /// 执行服务器协议
  Future<void> _performServerProtocol(Uint8List authHash) async {
    try {
      // 接收客户端的认证哈希
      final clientAuthHash = await _readBytes(32); // SHA256哈希长度

      // 验证认证哈希
      if (!_bytesEqual(clientAuthHash, authHash)) {
        // 发送失败响应
        await _writeBytes(Uint8List.fromList([1])); // 错误码
        throw StateError('配对认证失败：认证哈希不匹配');
      }

      // 发送成功响应
      await _writeBytes(Uint8List.fromList([0])); // 成功码

      print('服务器配对协议完成');
    } catch (e) {
      throw StateError('执行服务器协议失败: $e');
    }
  }

  /// 写入字节数据
  Future<void> _writeBytes(Uint8List data) async {
    if (_sslSocket == null) {
      throw StateError('TLS连接未建立');
    }

    try {
      _sslSocket!.add(data);
      await _sslSocket!.flush();
    } catch (e) {
      throw StateError('写入数据失败: $e');
    }
  }

  /// 读取字节数据
  Future<Uint8List> _readBytes(int length) async {
    if (_sslSocket == null) {
      throw StateError('TLS连接未建立');
    }

    final completer = Completer<Uint8List>();
    final buffer = BytesBuilder();

    final subscription = _sslSocket!.listen(
      (data) {
        buffer.add(data);
        if (buffer.length >= length) {
          if (!completer.isCompleted) {
            completer.complete(buffer.toBytes().sublist(0, length));
          }
        }
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('读取数据失败: $error'));
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(buffer.toBytes());
        }
      },
      cancelOnError: true,
    );

    try {
      final result = await completer.future;
      subscription.cancel();
      return result;
    } catch (e) {
      subscription.cancel();
      rethrow;
    }
  }

  /// 比较两个字节数组是否相等
  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }

    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }

    return true;
  }

  /// 获取对等方信息
  PeerInfo get peerInfo => _peerInfo;

  /// 获取SSL socket
  SecureSocket? get sslSocket => _sslSocket;

  /// 检查是否已认证
  bool get isAuthenticated => _isAuthenticated;

  /// 关闭连接
  void close() {
    _sslSocket?.destroy();
    _sslSocket = null;
  }
}
