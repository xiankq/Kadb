import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:crypto/crypto.dart';

// ADB配对协议常量
const String _clientNameStr = 'adb pair client\u0000';
const String _serverNameStr = 'adb pair server\u0000';
const String _infoStr = 'adb pairing_auth aes-128-gcm key';

const int _hkdfKeyLength = 16;
const int _gcmIvLength = 12;

/// SPAKE2角色枚举
enum Spake2Role {
  alice, // 客户端
  bob, // 服务器
}

/// SPAKE2上下文接口
abstract class Spake2Context {
  Uint8List generateMessage(Uint8List password);
  Uint8List? processMessage(Uint8List? theirMsg);
  void destroy();
}

/// SPAKE2协议实现
class Spake2ContextImpl implements Spake2Context {
  final Uint8List _myName;
  final Uint8List _theirName;
  final Uint8List _privateKey = Uint8List(32);
  final Uint8List _publicKey = Uint8List(32);
  final Uint8List _scalar = Uint8List(32);
  bool _destroyed = false;

  Spake2ContextImpl(Spake2Role role, this._myName, this._theirName) {
    _initializeKeys();
  }

  void _initializeKeys() {
    final random = Random.secure();
    for (var i = 0; i < 32; i++) {
      _privateKey[i] = random.nextInt(256);
    }

    // 简化的公钥生成（实际应用中应使用完整的椭圆曲线实现）
    for (var i = 0; i < 32; i++) {
      _publicKey[i] = _privateKey[i] ^ 0x55;
    }
  }

  @override
  Uint8List generateMessage(Uint8List password) {
    if (_destroyed) throw StateError('SPAKE2上下文已销毁');

    final passwordHash = _hashPassword(password);
    final w = _reduceModQ(passwordHash);

    // 简化的SPAKE2消息生成
    for (var i = 0; i < 32; i++) {
      _scalar[i] = (_publicKey[i] + w[i % w.length]) % 256;
    }

    return Uint8List.fromList(_scalar);
  }

  @override
  Uint8List? processMessage(Uint8List? theirMsg) {
    if (_destroyed || theirMsg == null) return null;

    try {
      // 简化的共享密钥计算
      final sharedSecret = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        sharedSecret[i] = (_privateKey[i] * theirMsg[i]) % 256;
      }
      return sharedSecret;
    } catch (e) {
      return null;
    }
  }

  @override
  void destroy() {
    _destroyed = true;
    for (var i = 0; i < _privateKey.length; i++) {
      _privateKey[i] = 0;
    }
    for (var i = 0; i < _scalar.length; i++) {
      _scalar[i] = 0;
    }
  }

  Uint8List _hashPassword(Uint8List password) {
    final data = Uint8List(
      password.length + _myName.length + _theirName.length,
    );
    data.setRange(0, password.length, password);
    data.setRange(password.length, password.length + _myName.length, _myName);
    data.setRange(password.length + _myName.length, data.length, _theirName);
    return Uint8List.fromList(sha256.convert(data).bytes);
  }

  Uint8List _reduceModQ(Uint8List input) {
    final q = BigInt.parse(
      '7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed',
      radix: 16,
    );
    final value = BigInt.parse(
      input
          .sublist(0, 32)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      radix: 16,
    );
    final result = value % q;
    return _bigIntToBytes(result, 32);
  }

  Uint8List _bigIntToBytes(BigInt value, int length) {
    var hex = value.toRadixString(16).padLeft(length * 2, '0');
    if (hex.length > length * 2) {
      hex = hex.substring(hex.length - length * 2);
    }
    return Uint8List.fromList(
      List.generate(
        length,
        (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
  }
}

/// 配对认证上下文接口
abstract class PairingAuthCtx {
  Uint8List get msg;
  bool initCipher(Uint8List? theirMsg);
  Uint8List? encrypt(Uint8List input);
  Uint8List? decrypt(Uint8List input);
  bool isDestroyed();
  void destroy();
}

/// Alice配对认证上下文实现
class AlicePairingAuthCtx implements PairingAuthCtx {
  final Uint8List _password;
  late final Uint8List _msg;
  final Uint8List _secretKey = Uint8List(_hkdfKeyLength);
  late final Spake2Context _spake2Ctx;
  int _decIv = 0;
  int _encIv = 0;
  bool _destroyed = false;

  AlicePairingAuthCtx(this._password) {
    _spake2Ctx = Spake2ContextImpl(
      Spake2Role.alice,
      PairingAuthCtxFactory._getBytes(_clientNameStr),
      PairingAuthCtxFactory._getBytes(_serverNameStr),
    );
    _msg = _spake2Ctx.generateMessage(_password);
  }

  @override
  Uint8List get msg => _msg;

  @override
  bool initCipher(Uint8List? theirMsg) {
    if (_destroyed || theirMsg == null) return false;

    try {
      final keyMaterial = _spake2Ctx.processMessage(theirMsg);
      if (keyMaterial == null) return false;

      final derivedKey = _hkdfSha256(
        keyMaterial,
        PairingAuthCtxFactory._getBytes(_infoStr),
        _hkdfKeyLength,
      );
      _secretKey.setRange(0, derivedKey.length, derivedKey);
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Uint8List? encrypt(Uint8List input) {
    return _aesGcm(true, input, _getIv(_encIv++));
  }

  @override
  Uint8List? decrypt(Uint8List input) {
    return _aesGcm(false, input, _getIv(_decIv++));
  }

  @override
  bool isDestroyed() => _destroyed;

  @override
  void destroy() {
    _destroyed = true;
    for (var i = 0; i < _secretKey.length; i++) {
      _secretKey[i] = 0;
    }
    _spake2Ctx.destroy();
  }

  Uint8List? _aesGcm(bool encrypt, Uint8List input, Uint8List iv) {
    if (_destroyed) return null;

    try {
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(_secretKey),
        128,
        iv,
        Uint8List(0),
      );

      cipher.init(encrypt, params);
      final output = Uint8List(cipher.getOutputSize(input.length));
      final offset = cipher.processBytes(input, 0, input.length, output, 0);
      cipher.doFinal(output, offset);
      return output;
    } catch (e) {
      return null;
    }
  }

  Uint8List _getIv(int counter) {
    final buffer = ByteData(_gcmIvLength);
    buffer.setUint64(0, counter, Endian.little);
    return buffer.buffer.asUint8List();
  }

  Uint8List _hkdfSha256(Uint8List ikm, Uint8List info, int length) {
    // HKDF-Extract
    final salt = Uint8List(32);
    final prk = _hmacSha256(salt, ikm);

    // HKDF-Expand
    final result = Uint8List(length);
    var t = Uint8List(0);
    var offset = 0;

    for (var i = 1; offset < length; i++) {
      final input = Uint8List(t.length + info.length + 1);
      if (t.isNotEmpty) {
        input.setRange(0, t.length, t);
      }
      input.setRange(t.length, t.length + info.length, info);
      input[t.length + info.length] = i;

      t = _hmacSha256(prk, input);
      final copyLength = (offset + t.length > length)
          ? length - offset
          : t.length;
      result.setRange(offset, offset + copyLength, t);
      offset += copyLength;
    }

    return result;
  }

  Uint8List _hmacSha256(Uint8List key, Uint8List data) {
    final blockSize = 64;
    final digest = SHA256Digest();

    if (key.length > blockSize) {
      key = digest.process(key);
    }

    final keyPad = Uint8List(blockSize);
    keyPad.setRange(0, key.length, key);

    final ipad = Uint8List(blockSize);
    final opad = Uint8List(blockSize);
    for (var i = 0; i < blockSize; i++) {
      ipad[i] = keyPad[i] ^ 0x36;
      opad[i] = keyPad[i] ^ 0x5c;
    }

    final innerInput = Uint8List(ipad.length + data.length);
    innerInput.setRange(0, ipad.length, ipad);
    innerInput.setRange(ipad.length, innerInput.length, data);
    final innerHash = digest.process(innerInput);

    final outerInput = Uint8List(opad.length + innerHash.length);
    outerInput.setRange(0, opad.length, opad);
    outerInput.setRange(opad.length, outerInput.length, innerHash);
    return digest.process(outerInput);
  }
}

/// 配对认证工具类
class PairingAuthCtxFactory {
  /// 创建Alice配对认证上下文
  static PairingAuthCtx? createAlice(Uint8List password) {
    try {
      return AlicePairingAuthCtx(password);
    } catch (_) {
      return null;
    }
  }

  /// 获取字符串的字节数组表示
  static Uint8List _getBytes(String text) {
    return Uint8List.fromList(utf8.encode(text));
  }
}
