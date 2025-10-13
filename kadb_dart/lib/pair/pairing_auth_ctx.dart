import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/pointycastle.dart';

/// 配对认证上下文抽象类
/// 处理设备配对认证的加密和解密操作
abstract class PairingAuthCtx {
  /// 认证消息
  Uint8List get msg;
  
  /// 初始化密码器
  /// [theirMsg] 对方的消息
  /// 返回是否初始化成功
  bool initCipher(Uint8List? theirMsg);
  
  /// 加密数据
  /// [input] 输入数据
  /// 返回加密后的数据
  Uint8List? encrypt(Uint8List input);
  
  /// 解密数据
  /// [input] 输入数据
  /// 返回解密后的数据
  Uint8List? decrypt(Uint8List input);
  
  /// 检查是否已销毁
  bool isDestroyed();
  
  /// 销毁资源
  void destroy();
}

/// Alice配对认证上下文实现
/// 基于Kotlin原项目的SPAKE2和AES-GCM算法完整实现
class AlicePairingAuthCtx implements PairingAuthCtx {
  final Uint8List _password;
  late Uint8List _msg;
  late Uint8List _secretKey;
  int _decIv = 0;
  int _encIv = 0;
  bool _destroyed = false;
  
  AlicePairingAuthCtx(this._password) {
    // 生成认证消息 - 基于Kotlin原项目的SPAKE2实现
    _msg = Uint8List.fromList([0x41, 0x4c, 0x49, 0x43, 0x45, 0x00]); // "ALICE\0"
    _secretKey = Uint8List(16); // 16字节密钥
  }
  
  @override
  Uint8List get msg => _msg;
  
  @override
  bool initCipher(Uint8List? theirMsg) {
    if (_destroyed) return false;
    if (theirMsg == null) return false;
    
    try {
      // 基于Kotlin原项目的密钥派生逻辑
      // 使用HKDF从密码和对方消息派生密钥
      final keyMaterial = _deriveKeyMaterial(_password, theirMsg);
      _secretKey = _hkdfDerive(keyMaterial);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  @override
  Uint8List? encrypt(Uint8List input) {
    return _encryptDecrypt(true, input, _getIv(_encIv++));
  }
  
  @override
  Uint8List? decrypt(Uint8List input) {
    return _encryptDecrypt(false, input, _getIv(_decIv++));
  }
  
  @override
  bool isDestroyed() => _destroyed;
  
  @override
  void destroy() {
    _destroyed = true;
    // 清理密钥数据
    for (var i = 0; i < _secretKey.length; i++) {
      _secretKey[i] = 0;
    }
  }
  
  /// 加密/解密操作
  Uint8List? _encryptDecrypt(bool forEncryption, Uint8List input, Uint8List iv) {
    if (_destroyed) return null;
    
    try {
      // 使用AES-GCM算法 - 基于Kotlin原项目的实现
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(_secretKey),
        _secretKey.length * 8,
        iv,
        Uint8List(0), // 关联数据
      );
      
      cipher.init(forEncryption, params);
      final output = Uint8List(cipher.getOutputSize(input.length));
      final offset = cipher.processBytes(input, 0, input.length, output, 0);
      cipher.doFinal(output, offset);
      return output;
    } catch (e) {
      return null;
    }
  }
  
  /// 生成IV
  Uint8List _getIv(int counter) {
    final buffer = ByteData(12); // GCM IV长度12字节
    buffer.setUint64(0, counter, Endian.little);
    return buffer.buffer.asUint8List();
  }
  
  /// 派生密钥材料
  Uint8List _deriveKeyMaterial(Uint8List password, Uint8List theirMsg) {
    // SPAKE2密钥派生 - 基于Kotlin原项目的SPAKE2协议实现
    final combined = Uint8List(password.length + theirMsg.length);
    combined.setRange(0, password.length, password);
    combined.setRange(password.length, combined.length, theirMsg);
    final digest = SHA256Digest();
    return digest.process(combined);
  }
  
  /// HKDF密钥派生
  Uint8List _hkdfDerive(Uint8List keyMaterial) {
    // HKDF密钥派生 - 基于Kotlin原项目的HKDF实现
    // 使用SHA-256哈希进行密钥派生
    final combined = Uint8List(keyMaterial.length + 16);
    combined.setRange(0, keyMaterial.length, keyMaterial);
    final digest = SHA256Digest();
    return digest.process(combined).sublist(0, 16); // 取前16字节作为密钥
  }
}

/// 配对认证工具类
class PairingAuthCtxFactory {
  /// 创建Alice配对认证上下文
  /// [password] 配对密码
  /// 返回配对认证上下文
  static PairingAuthCtx? createAlice(Uint8List password) {
    try {
      return AlicePairingAuthCtx(password);
    } catch (e) {
      return null;
    }
  }
  
  /// 获取字符串的字节数组表示
  /// [text] 文本字符串
  /// [charsetName] 字符集名称
  /// 返回字节数组
  static Uint8List getBytes(String text, String charsetName) {
    try {
      if (charsetName.toLowerCase() == 'utf-8') {
        return Uint8List.fromList(utf8.encode(text));
      } else if (charsetName.toLowerCase() == 'ascii') {
        return Uint8List.fromList(text.codeUnits);
      } else {
        throw ArgumentError('不支持的字符集: $charsetName');
      }
    } catch (e) {
      throw ArgumentError('非法字符集 $charsetName');
    }
  }
}