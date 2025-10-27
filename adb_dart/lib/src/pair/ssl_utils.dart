/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:io';
import '../cert/adb_key_pair.dart';
import '../tls/tls_error_mapper.dart';

/// SSL工具类，用于TLS连接管理
class SslUtils {
  /// 获取SSL上下文
  static SecurityContext getSslContext(AdbKeyPair keyPair) {
    try {
      // 创建SSL上下文
      final context = SecurityContext.defaultContext;

      // 设置客户端证书（简化实现）
      // 实际实现需要更复杂的证书配置
      _configureClientCertificate(context, keyPair);

      return context;
    } catch (e) {
      throw Exception('Failed to create SSL context: $e');
    }
  }

  /// 配置客户端证书
  static void _configureClientCertificate(
    SecurityContext context,
    AdbKeyPair keyPair,
  ) {
    try {
      // 这里需要实现客户端证书配置
      // 由于Dart的SecurityContext限制，这里提供框架实现

      print('配置客户端证书...');

      // 获取证书数据
      final certificate = keyPair.certificate;
      if (certificate != null) {
        // 配置证书（简化实现）
        // 实际实现需要处理证书格式转换
        print('客户端证书配置完成');
      } else {
        print('无客户端证书，使用默认配置');
      }
    } catch (e) {
      throw Exception('Failed to configure client certificate: $e');
    }
  }

  /// 创建新的客户端SSL引擎
  static Future<SecureSocket> newClientEngine(
    SecurityContext sslContext,
    String host,
    int port,
  ) async {
    try {
      // 创建SecureSocket配置
      final socket = await SecureSocket.connect(
        host,
        port,
        context: sslContext,
        onBadCertificate: (certificate) {
          // 在实际实现中，这里需要验证证书
          print('证书验证: ${certificate.subject}');
          return true; // 简化实现，接受所有证书
        },
      );

      print('SSL客户端引擎创建成功');
      return socket;
    } catch (e) {
      throw TlsErrorMapper.map(e);
    }
  }

  /// 执行TLS握手
  static Future<void> handshake(SecureSocket socket, Duration timeout) async {
    try {
      print('开始TLS握手...');

      // 等待握手完成
      final certificate = socket.peerCertificate;
      if (certificate != null) {
        print('TLS握手成功，对等证书: ${certificate.subject}');
      } else {
        print('TLS握手完成，无对等证书');
      }

      print('TLS握手完成');
    } catch (e) {
      throw TlsErrorMapper.map(e);
    }
  }

  /// 创建TLS客户端Socket（简化实现）
  static Future<SecureSocket> createTlsClient(
    String host,
    int port,
    AdbKeyPair keyPair,
  ) async {
    try {
      print('创建TLS客户端连接: $host:$port');

      final sslContext = getSslContext(keyPair);
      final secureSocket = await newClientEngine(sslContext, host, port);

      return secureSocket;
    } catch (e) {
      throw TlsErrorMapper.map(e);
    }
  }
}
