import 'package:flutter/foundation.dart';
import 'package:kadb_dart/kadb_dart.dart';
import 'package:path_provider/path_provider.dart';

class ConnectionProvider with ChangeNotifier {
  AdbConnection? _connection;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _statusMessage = '准备连接';

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String get statusMessage => _statusMessage;
  AdbConnection? get connection => _connection;

  ConnectionProvider() {
    debugPrint('ConnectionProvider 初始化');
  }

  Future<bool> connectToDevice(String host, int port) async {
    debugPrint('开始连接设备: $host:$port');
    if (_isConnecting) return false;

    _isConnecting = true;
    _statusMessage = '正在连接设备...';
    notifyListeners();

    try {
      debugPrint('获取应用文档目录...');
      // 获取应用文档目录用于存储密钥
      final documentsDir = await getApplicationDocumentsDirectory();
      final keyCacheDir = '${documentsDir.path}/adb_keys';
      debugPrint('密钥存储目录: $keyCacheDir');

      debugPrint('加载密钥对...');
      // 加载或生成密钥对
      final keyPair = await CertUtils.loadKeyPair(cacheDir: keyCacheDir);
      debugPrint('密钥对加载完成');

      debugPrint('建立ADB连接...');
      // 建立ADB连接
      _connection = await KadbDart.create(
        host: host,
        port: port,
        keyPair: keyPair,
        debug: kDebugMode,
        ioTimeoutMs: 30000,
        connectTimeoutMs: 15000,
      );
      debugPrint('ADB连接建立成功');

      _statusMessage = '设备连接成功';
      _isConnected = true;
      notifyListeners();
      return true;

    } catch (e, stackTrace) {
      debugPrint('连接失败: $e');
      debugPrint('错误堆栈: $stackTrace');
      _statusMessage = '连接失败: $e';
      _isConnected = false;
      _connection = null;
      notifyListeners();
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  
  Future<void> disconnect() async {
    try {
      _connection?.close();
    } catch (e) {
      debugPrint('断开连接时出错: $e');
    } finally {
      _connection = null;
      _isConnected = false;
      _statusMessage = '已断开连接';
      notifyListeners();
    }
  }

  void updateStatus(String message) {
    _statusMessage = message;
    notifyListeners();
  }
}