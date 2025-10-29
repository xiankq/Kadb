/// WiFi配对连接上下文
///
/// 处理WiFi设备配对的连接管理
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../debug/logging.dart';
import 'pairing_auth_ctx.dart';

/// 配对连接上下文
class PairingConnectionCtx {
  final String host;
  final int port;
  final Uint8List password;
  final AdbKeyPair keyPair;
  final String deviceName;

  PairingAuthCtx? _authCtx;
  bool _isConnected = false;
  bool _isPairing = false;

  PairingConnectionCtx({
    required this.host,
    required this.port,
    required this.password,
    required this.keyPair,
    required this.deviceName,
  });

  /// 执行WiFi配对
  Future<void> performPairing() async {
    if (_isPairing) {
      throw StateError('配对已在进行中');
    }

    _isPairing = true;
    print('开始WiFi配对: $host:$port');

    try {
      // 创建认证上下文
      _authCtx = PairingAuthCtx(
        host: host,
        port: port,
        password: password,
        keyPair: keyPair,
        deviceName: deviceName,
        role: PairingRole.client,
      );

      // 执行配对认证
      await _authCtx!.authenticate();

      _isConnected = true;
      print('WiFi配对成功');
    } catch (e) {
      _isConnected = false;
      throw StateError('WiFi配对失败: $e');
    } finally {
      _isPairing = false;
    }
  }

  /// 获取配对后的设备地址
  String getDeviceAddress() {
    if (!_isConnected) {
      throw StateError('设备未配对');
    }

    return '$host:5555'; // 配对后通常使用5555端口
  }

  /// 获取配对状态
  bool get isConnected => _isConnected;

  /// 获取认证上下文
  PairingAuthCtx? get authContext => _authCtx;

  /// 关闭配对连接
  void close() {
    _authCtx?.close();
    _authCtx = null;
    _isConnected = false;
    _isPairing = false;
    print('配对连接已关闭');
  }
}

/// 配对管理器
class PairingManager {
  static final Map<String, PairingConnectionCtx> _pairingSessions = {};

  /// 配对设备
  static Future<void> pairDevice({
    required String host,
    required int port,
    required String pairingCode,
    required AdbKeyPair keyPair,
    required String deviceName,
  }) async {
    final sessionKey = '$host:$port';

    // 检查是否已有配对会话
    if (_pairingSessions.containsKey(sessionKey)) {
      final existingSession = _pairingSessions[sessionKey]!;
      if (existingSession.isConnected) {
        print('设备已配对: $sessionKey');
        return;
      } else {
        // 关闭旧的会话
        existingSession.close();
        _pairingSessions.remove(sessionKey);
      }
    }

    try {
      // 创建配对上下文
      final pairingCtx = PairingConnectionCtx(
        host: host,
        port: port,
        password: Uint8List.fromList(pairingCode.codeUnits),
        keyPair: keyPair,
        deviceName: deviceName,
      );

      // 执行配对
      await pairingCtx.performPairing();

      // 保存配对会话
      _pairingSessions[sessionKey] = pairingCtx;

      print('设备配对成功: $sessionKey');
    } catch (e) {
      // 清理失败的会话
      _pairingSessions.remove(sessionKey);
      rethrow;
    }
  }

  /// 获取配对设备地址
  static String getPairedDeviceAddress(String host, int port) {
    final sessionKey = '$host:$port';
    final pairingCtx = _pairingSessions[sessionKey];

    if (pairingCtx == null || !pairingCtx.isConnected) {
      throw StateError('设备未配对: $sessionKey');
    }

    return pairingCtx.getDeviceAddress();
  }

  /// 检查设备是否已配对
  static bool isDevicePaired(String host, int port) {
    final sessionKey = '$host:$port';
    final pairingCtx = _pairingSessions[sessionKey];

    return pairingCtx != null && pairingCtx.isConnected;
  }

  /// 取消配对
  static void unpairDevice(String host, int port) {
    final sessionKey = '$host:$port';
    final pairingCtx = _pairingSessions.remove(sessionKey);

    if (pairingCtx != null) {
      pairingCtx.close();
      print('设备已取消配对: $sessionKey');
    }
  }

  /// 清除所有配对
  static void clearAllPairings() {
    for (final pairingCtx in _pairingSessions.values) {
      pairingCtx.close();
    }
    _pairingSessions.clear();
    print('所有配对已清除');
  }

  /// 获取配对会话数量
  static int get pairedDeviceCount => _pairingSessions.length;

  /// 获取所有配对设备
  static List<String> getPairedDevices() {
    return _pairingSessions.keys.toList();
  }
}
