import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'adb_key_pair.dart';
import 'android_pubkey.dart';
import 'cert_utils.dart';

/// TLS工具类
class TlsUtils {
  /// 创建SSL安全上下文
  static Future<SecurityContext> createSslContext(AdbKeyPair keyPair) async {
    final context = SecurityContext();

    // 设置客户端证书和私钥
    // 使用AndroidPubkey.encode方法生成证书编码
    final certificateBytes = AndroidPubkey.encode(keyPair.publicKey);

    // 将私钥编码为PEM格式
    final privateKeyPem = CertUtils.toPrivateKeyPem(keyPair);

    // 将证书和私钥添加到安全上下文
    context.useCertificateChainBytes(certificateBytes);
    context.usePrivateKeyBytes(utf8.encode(privateKeyPem));

    // 允许任何SSL证书（为了兼容性）
    context.setTrustedCertificatesBytes(Uint8List(0));

    return context;
  }

  /// 验证证书（简化实现）
  static bool verifyCertificate(X509Certificate cert, String host) {
    // 在实际应用中，这里应该进行完整的证书验证
    // 为了ADB配对的兼容性，我们接受任何证书
    return true;
  }
}
