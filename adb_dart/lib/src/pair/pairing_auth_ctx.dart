/// 设备配对认证上下文
/// 实现WiFi设备配对功能
library pairing_auth_ctx;

import 'dart:typed_data';
import '../exception/adb_exceptions.dart';

/// 配对认证上下文接口
abstract class PairingAuthCtx {
  /// 获取消息数据
  Uint8List get msg;

  /// 初始化密码学上下文
  bool initCipher(Uint8List? theirMsg);

  /// 加密数据
  Uint8List? encrypt(Uint8List input);

  /// 解密数据
  Uint8List? decrypt(Uint8List input);

  /// 是否已销毁
  bool get isDestroyed;

  /// 销毁敏感数据
  void destroy();
}

/// 简单的配对认证上下文（简化实现）
/// TODO: 需要实现完整的SPAKE+协议
class SimplePairingAuthCtx implements PairingAuthCtx {
  final Uint8List _password;
  Uint8List? _theirMsg;
  bool _isDestroyed = false;

  SimplePairingAuthCtx(this._password);

  @override
  Uint8List get msg {
    if (_isDestroyed) {
      throw AdbPairAuthException('认证上下文已销毁');
    }
    // 返回一个简单的挑战消息
    return Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
  }

  @override
  bool initCipher(Uint8List? theirMsg) {
    if (_isDestroyed) {
      throw AdbPairAuthException('认证上下文已销毁');
    }

    if (theirMsg == null || theirMsg.isEmpty) {
      return false;
    }

    _theirMsg = Uint8List.fromList(theirMsg);
    return true;
  }

  @override
  Uint8List? encrypt(Uint8List input) {
    if (_isDestroyed) {
      throw AdbPairAuthException('认证上下文已销毁');
    }

    if (_theirMsg == null) {
      return null;
    }

    // 简单的XOR加密（仅用于演示，实际应该使用安全的加密算法）
    final result = Uint8List(input.length);
    for (int i = 0; i < input.length; i++) {
      result[i] = input[i] ^
          _password[i % _password.length] ^
          _theirMsg![i % _theirMsg!.length];
    }
    return result;
  }

  @override
  Uint8List? decrypt(Uint8List input) {
    if (_isDestroyed) {
      throw AdbPairAuthException('认证上下文已销毁');
    }

    if (_theirMsg == null) {
      return null;
    }

    // 使用相同的XOR算法解密
    return encrypt(input);
  }

  @override
  bool get isDestroyed => _isDestroyed;

  @override
  void destroy() {
    _isDestroyed = true;
    _password.fillRange(0, _password.length, 0);
    _theirMsg?.fillRange(0, _theirMsg!.length, 0);
    _theirMsg = null;
  }

  /// 创建Alice角色（客户端）
  static SimplePairingAuthCtx? createAlice(Uint8List password) {
    if (password.isEmpty) {
      return null;
    }
    return SimplePairingAuthCtx(password);
  }
}

/// 配对协议常量
class PairingProtocol {
  /// 当前协议版本
  static const int currentKeyHeaderVersion = 1;
  static const int minSupportedKeyHeaderVersion = 1;
  static const int maxSupportedKeyHeaderVersion = 1;

  /// 最大载荷大小
  static const int maxPayloadSize = 2 * peerInfoMaxSize;

  /// 数据包头部大小
  static const int pairingPacketHeaderSize = 6;

  /// 包类型
  static const int spake2Msg = 0;
  static const int peerInfo = 1;

  /// PeerInfo常量
  static const int peerInfoMaxSize = 1 << 13; // 8192
  static const int adbRsaPubKey = 0;
  static const int adbDeviceGuid = 0;

  /// 导出的密钥标签
  static const String exportedKeyLabel = "adb-label\u0000";
  static const int exportKeySize = 64;
}
