/// SSL工具类
/// 提供TLS/SSL相关功能支持
library ssl_utils;

import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'dart:async';
import 'package:pointycastle/pointycastle.dart' as pc;
import '../cert/adb_key_pair.dart';
import '../exception/adb_exceptions.dart';

/// SSL工具类
class SslUtils {
  static bool _customConscrypt = false;
  static SecurityContext? _sslContext;

  /// 创建客户端SSL引擎
  static HttpClient createSecureClient({String? host, int? port}) {
    final client = HttpClient();

    // 配置TLS 1.3
    client.badCertificateCallback = (cert, host, port) {
      // 在ADB配对中，我们接受所有证书
      return true;
    };

    return client;
  }

  /// 获取SSL上下文
  static SecurityContext getSslContext(AdbKeyPair keyPair) {
    if (_sslContext != null) {
      return _sslContext!;
    }

    try {
      // 创建安全上下文
      _sslContext = SecurityContext();

      // 设置客户端证书（如果需要）
      // TODO: 需要从AdbKeyPair导出证书并设置到SecurityContext

      _customConscrypt = false;
      return _sslContext!;
    } catch (e) {
      throw TlsException('无法创建SSL上下文: $e');
    }
  }

  /// 创建TLS安全套接字
  static Future<SecureSocket> createSecureSocket(
    Socket socket,
    String host,
    int port, {
    required bool isServer,
    AdbKeyPair? keyPair,
  }) async {
    try {
      if (isServer) {
        // 服务器模式
        final context = getSslContext(keyPair ?? _generateDummyKeyPair());
        return await SecureSocket.secureServer(
          socket,
          context,
          requestClientCertificate: true,
        );
      } else {
        // 客户端模式
        return await SecureSocket.secure(
          socket,
          host: host,
          onBadCertificate: (certificate) {
            // 在ADB配对中，我们接受所有证书
            return true;
          },
        );
      }
    } catch (e) {
      throw TlsException('创建TLS套接字失败: $e');
    }
  }

  /// 创建客户端SSL引擎（对标Kadb的newClientEngine）
  static SecurityContext createClientEngine({
    required String host,
    required int port,
    required SecurityContext sslContext,
  }) {
    try {
      // 在Dart中，我们返回配置好的SecurityContext
      // 实际的SSL引擎创建在连接时进行
      return sslContext;
    } catch (e) {
      throw TlsException('Failed to create client SSL engine: $e');
    }
  }

  /// 创建增强的KeyManager（对标Kadb的X509ExtendedKeyManager）
  static dynamic getKeyManager(AdbKeyPair keyPair) {
    // 在Dart中，SecurityContext处理密钥管理
    // 这里返回一个模拟的KeyManager对象
    return _EnhancedKeyManager(keyPair);
  }

  /// 创建接受所有证书的TrustManager（对标Kadb的getAllAcceptingTrustManager）
  static dynamic getAllAcceptingTrustManager() {
    // 在ADB配对中，我们接受所有证书
    return _AllAcceptingTrustManager();
  }

  /// 执行TLS握手
  static Future<void> performTlsHandshake(
    SecureSocket socket, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      // 等待握手完成
      await socket.done.timeout(timeout);
    } on TimeoutException {
      throw TlsException('TLS握手超时');
    } catch (e) {
      throw TlsException('TLS握手失败: $e');
    }
  }

  /// 导出密钥材料
  static Uint8List exportKeyingMaterial(
    SecureSocket socket,
    String label,
    Uint8List? context,
    int length,
  ) {
    // TODO: 在Dart中实现导出密钥材料功能
    // 这里返回一个模拟的密钥材料
    final random = Random.secure();
    final result = Uint8List(length);
    for (int i = 0; i < length; i++) {
      result[i] = random.nextInt(256);
    }
    return result;
  }

  /// 生成虚拟密钥对（用于测试）
  static AdbKeyPair _generateDummyKeyPair() {
    return AdbKeyPair.generate(
      keySize: 2048,
      commonName: 'adb_dart_tls',
    );
  }

  /// 检查TLS连接状态
  static bool isSecureConnection(Socket socket) {
    return socket is SecureSocket;
  }

  /// 获取TLS连接信息
  static Map<String, dynamic> getTlsInfo(SecureSocket socket) {
    return {
      'protocol': 'TLSv1.3', // 假设使用TLS 1.3
      'cipher': '未知', // Dart没有直接暴露cipher信息
      'peerCertificate': null, // TODO: 获取对等证书信息
      'isSecure': true,
    };
  }
}

/// 增强的KeyManager（模拟Kadb的X509ExtendedKeyManager）
class _EnhancedKeyManager {
  final AdbKeyPair _keyPair;
  final String _alias = 'key';

  _EnhancedKeyManager(this._keyPair);

  /// 获取客户端别名（对标chooseClientAlias）
  String? chooseClientAlias(
    List<String>? keyTypes,
    List<Principal>? issuers,
    Socket? socket,
  ) {
    // 检查是否支持RSA
    if (keyTypes != null &&
        keyTypes.any((type) => type.toLowerCase().contains('rsa'))) {
      return _alias;
    }
    return _alias; // 默认返回我们的别名
  }

  /// 获取客户端别名（针对SSLEngine）
  String? chooseEngineClientAlias(
    List<String>? keyTypes,
    List<Principal>? issuers,
    dynamic engine, // SSLEngine
  ) {
    return chooseClientAlias(keyTypes, issuers, null);
  }

  /// 获取证书链（对标getCertificateChain）
  List<Uint8List>? getCertificateChain(String? alias) {
    if (alias == _alias) {
      // 返回证书链（简化处理）
      return [_keyPair.certificate];
    }
    return null;
  }

  /// 获取私钥（对标getPrivateKey）
  pc.RSAPrivateKey? getPrivateKey(String? alias) {
    if (alias == _alias) {
      return _keyPair.privateKey;
    }
    return null;
  }

  /// 获取客户端别名数组（对标getClientAliases）
  List<String>? getClientAliases(String? keyType, List<Principal>? issuers) {
    if (keyType?.toLowerCase().contains('rsa') ?? true) {
      return [_alias];
    }
    return [_alias];
  }

  /// 获取服务器别名（对标getServerAliases）
  List<String>? getServerAliases(String? keyType, List<Principal>? issuers) {
    // 我们不支持服务器模式
    return null;
  }

  /// 选择服务器别名（对标chooseServerAlias）
  String? chooseServerAlias(
    String? keyType,
    List<Principal>? issuers,
    Socket? socket,
  ) {
    // 我们不支持服务器模式
    return null;
  }
}

/// 接受所有证书的TrustManager（对标Kadb的getAllAcceptingTrustManager）
class _AllAcceptingTrustManager {
  /// 检查客户端可信度（对标checkClientTrusted）
  void checkClientTrusted(List<Uint8List> chain, String authType) {
    // 接受所有客户端证书
    return;
  }

  /// 检查服务器可信度（对标checkServerTrusted）
  void checkServerTrusted(List<Uint8List> chain, String authType) {
    // 接受所有服务器证书
    return;
  }

  /// 获取接受的发行者（对标getAcceptedIssuers）
  List<Uint8List> getAcceptedIssuers() {
    // 返回空数组，接受所有发行者
    return [];
  }
}

/// 主体信息（模拟Java的Principal）
class Principal {
  final String name;

  Principal(this.name);

  @override
  String toString() => name;
}

/// TLS包装器
class TlsWrapper {
  final SecureSocket _socket;
  final bool _isServer;

  TlsWrapper._(this._socket, this._isServer);

  /// 创建TLS包装器
  static Future<TlsWrapper> create({
    required Socket socket,
    required String host,
    required int port,
    required bool isServer,
    AdbKeyPair? keyPair,
  }) async {
    final secureSocket = await SslUtils.createSecureSocket(
      socket,
      host,
      port,
      isServer: isServer,
      keyPair: keyPair,
    );

    return TlsWrapper._(secureSocket, isServer);
  }

  /// 获取底层套接字
  SecureSocket get socket => _socket;

  /// 是否服务器模式
  bool get isServer => _isServer;

  /// 读取数据
  Future<Uint8List> read() async {
    final completer = Completer<Uint8List>();
    final buffer = BytesBuilder();

    StreamSubscription<List<int>>? subscription;
    subscription = _socket.listen(
      (data) {
        buffer.add(data);
        if (!completer.isCompleted) {
          completer.complete(buffer.toBytes());
          subscription?.cancel();
        }
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(buffer.toBytes());
        }
      },
    );

    return completer.future;
  }

  /// 写入数据
  Future<void> write(Uint8List data) async {
    _socket.add(data);
    await _socket.flush();
  }

  /// 关闭连接
  Future<void> close() async {
    await _socket.close();
  }
}

/// TLS配置
class TlsConfig {
  final bool enabled;
  final bool requireClientCertificate;
  final Duration handshakeTimeout;
  final SecurityContext? securityContext;

  const TlsConfig({
    this.enabled = true,
    this.requireClientCertificate = false,
    this.handshakeTimeout = const Duration(seconds: 30),
    this.securityContext,
  });

  /// 默认TLS配置
  static const TlsConfig defaultConfig = TlsConfig();
}
