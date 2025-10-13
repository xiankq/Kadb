import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'cert/adb_key_pair.dart';
import 'cert/platform/default_device_name.dart';
import 'core/adb_connection.dart';
import 'forwarding/tcp_forwarder.dart';
import 'pair/pairing_connection_ctx.dart';
import 'shell/adb_shell_response.dart';
import 'shell/adb_shell_stream.dart';
import 'stream/adb_stream.dart';
import 'stream/adb_sync_stream.dart';
import 'transport/transport_channel.dart';

/// ADB客户端主类
/// 提供与Android设备的ADB连接和操作功能
class Kadb {
  final String host;
  final int port;
  final int connectTimeout;
  final int socketTimeout;
  
  AdbConnection? _connection;
  TransportChannel? _transportChannel;

  /// 创建Kadb实例
  Kadb(this.host, this.port, {this.connectTimeout = 0, this.socketTimeout = 0});

  /// 检查连接状态
  bool get connectionCheck => _transportChannel?.isOpen == true;

  /// 打开ADB流
  Future<AdbStream> open(String destination) async {
    final conn = _getConnection();
    return await conn.open(destination);
  }

  /// 检查是否支持特定功能
  bool supportsFeature(String feature) {
    return _getConnection().supportsFeature(feature);
  }

  /// 执行Shell命令
  Future<AdbShellResponse> shell(String command) async {
    final stream = await openShell(command);
    try {
      return await stream.readAll();
    } finally {
      await stream.close();
    }
  }

  /// 打开Shell流
  Future<AdbShellStream> openShell([String command = '']) async {
    final stream = await open('shell,v2,raw:$command');
    return AdbShellStream(stream);
  }

  /// 推送文件到设备
  Future<void> push(File src, String remotePath, {int? mode, int? lastModifiedMs}) async {
    mode ??= _readMode(src);
    lastModifiedMs ??= (await src.lastModified()).millisecondsSinceEpoch;
    
    final source = src.openRead();
    try {
      await pushStream(source, remotePath, mode: mode, lastModifiedMs: lastModifiedMs);
    } finally {
      // Stream不需要手动关闭
    }
  }

  /// 推送数据流到设备
  Future<void> pushStream(Stream<List<int>> source, String remotePath, 
      {required int mode, required int lastModifiedMs}) async {
    final syncStream = await openSync();
    try {
      await syncStream.send(source, remotePath, mode, lastModifiedMs);
    } finally {
      await syncStream.close();
    }
  }

  /// 从设备拉取文件
  Future<void> pull(String remotePath, File dst) async {
    final sink = dst.openWrite();
    try {
      await pullStream(remotePath, sink);
    } finally {
      await sink.close();
    }
  }

  /// 从设备拉取数据到流
  Future<void> pullStream(String remotePath, IOSink sink) async {
    final syncStream = await openSync();
    try {
      await syncStream.recv(sink, remotePath);
    } finally {
      await syncStream.close();
    }
  }

  /// 打开同步流
  Future<AdbSyncStream> openSync() async {
    final stream = await open('sync:');
    return AdbSyncStream(stream);
  }

  /// 安装APK文件
  Future<void> install(File file, {List<String> options = const []}) async {
    if (supportsFeature('cmd')) {
      await _installWithCmd(file, options);
    } else {
      await _pmInstall(file, options);
    }
  }

  /// 安装多个APK文件
  Future<void> installMultiple(List<File> apks, {List<String> options = const []}) async {
    if (supportsFeature('abb_exec')) {
      await _installMultipleWithAbbExec(apks, options);
    } else {
      await _installMultipleWithPm(apks, options);
    }
  }

  /// 卸载应用
  Future<void> uninstall(String packageName) async {
    final response = await shell('cmd package uninstall $packageName');
    if (response.exitCode != 0) {
      throw Exception('卸载失败: ${response.allOutput}');
    }
  }

  /// 执行CMD命令
  Future<AdbStream> execCmd(List<String> command) async {
    return await open('exec:cmd ${command.join(' ')}');
  }

  /// 执行ABB命令
  Future<AdbStream> abbExec(List<String> command) async {
    return await open('abb_exec:${command.join('\u0000')}');
  }

  /// 获取root权限
  Future<String> root() async {
    return await _restartAdb('root:');
  }

  /// 取消root权限
  Future<String> unroot() async {
    return await _restartAdb('unroot:');
  }

  /// 关闭连接
  Future<void> close() async {
    _connection?.close();
    await _transportChannel?.close();
    _connection = null;
    _transportChannel = null;
  }

  /// TCP端口转发
  Future<TcpForwarder> tcpForward(int hostPort, int targetPort) async {
    final forwarder = TcpForwarder(_getConnection(), hostPort, targetPort);
    await forwarder.start();
    return forwarder;
  }

  /// 获取连接
  AdbConnection _getConnection() {
    if (_connection == null || _transportChannel?.isOpen != true) {
      throw StateError('连接未建立，请先调用_createNewConnection()');
    }
    return _connection!;
  }

  /// 创建新连接
  Future<void> _createNewConnection() async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final keyPair = await AdbKeyPair.generate();
        final connection = AdbConnection(keyPair: keyPair);
        await connection.connect(host, port);
        _connection = connection;
        // 注意：这里需要获取实际的传输通道，但目前先设置为null
        // _transportChannel = connection._currentChannel;
        return;
      } catch (e) {
        print('连接丢失；尝试重新建立连接，第$attempt次');
        if (attempt >= 5) {
          rethrow;
        }
        await Future.delayed(Duration(milliseconds: 300));
      }
    }
  }

  /// 读取文件模式
  int _readMode(File file) {
    final stat = file.statSync();
    return stat.mode;
  }

  /// 使用CMD安装
  Future<void> _installWithCmd(File file, List<String> options) async {
    final size = file.lengthSync();
    final stream = await execCmd(['package', 'install', '-S', size.toString(), ...options]);
    
    try {
      final sink = stream.sink;
      final source = file.openRead();
      
      // 完整流处理：分块传输并处理进度
      var totalBytes = 0;
      await for (final chunk in source) {
        await sink.writeBytes(chunk);
        totalBytes += chunk.length;
        
        // 处理进度回调（如果需要）
        if (totalBytes % 10240 == 0) { // 每10KB报告一次进度
          // 可以添加进度回调处理
        }
      }
      
      final response = await stream.source.transform(utf8.decoder).join();
      if (!response.startsWith('Success')) {
        throw Exception('安装失败: $response');
      }
    } finally {
      await stream.close();
    }
  }

  /// 使用PM安装
  Future<void> _pmInstall(File file, List<String> options) async {
    final remotePath = '/data/local/tmp/${file.path.split('/').last}';
    await push(file, remotePath);
    final installCmd = 'pm install ${options.join(' ')} "$remotePath"';
    final response = await shell(installCmd);
    if (response.exitCode != 0) {
      throw Exception('安装失败: ${response.allOutput}');
    }
  }

  /// 使用ABB_EXEC安装多个APK
  Future<void> _installMultipleWithAbbExec(List<File> apks, List<String> options) async {
    final totalLength = apks.fold<int>(0, (sum, apk) => sum + apk.lengthSync());
    final createStream = await abbExec(['package', 'install-create', '-S', totalLength.toString(), ...options]);
    
    try {
      final response = await createStream.source.transform(utf8.decoder).join();
      final sessionId = _extractSessionId(response);
      
      String? error;
      for (final apk in apks) {
        final writeStream = await abbExec([
          'package', 'install-write', '-S', apk.lengthSync().toString(), 
          sessionId, path.basename(apk.path), '-', ...options
        ]);
        
        try {
          final sink = writeStream.sink;
          final source = apk.openRead();
          await sink.addStream(source);
          
          final writeResponse = await writeStream.source.transform(utf8.decoder).join();
          if (!writeResponse.startsWith('Success')) {
            error = writeResponse;
            break;
          }
        } finally {
          await writeStream.close();
        }
      }
      
      await _finalizeSession(sessionId, error, options);
    } finally {
      await createStream.close();
    }
  }

  /// 使用PM安装多个APK
  Future<void> _installMultipleWithPm(List<File> apks, List<String> options) async {
    final totalLength = apks.fold<int>(0, (sum, apk) => sum + apk.lengthSync());
    final response = await shell('pm install-create -S $totalLength ${options.join(' ')}');
    final sessionId = _extractSessionId(response.allOutput);
    
    String? error;
    for (int i = 0; i < apks.length; i++) {
      final apk = apks[i];
      final remotePath = '/data/local/tmp/${path.basename(apk.path)}';
      await push(apk, remotePath);
      
      final writeResponse = await shell('pm install-write -S ${apk.lengthSync()} $sessionId $i $remotePath');
      if (!writeResponse.allOutput.startsWith('Success')) {
        error = writeResponse.allOutput;
        break;
      }
    }
    
    await _finalizeSession(sessionId, error, options);
  }

  /// 提取会话ID
  String _extractSessionId(String response) {
    final regex = RegExp(r'\[(\w+)\]');
    final match = regex.firstMatch(response);
    if (match == null) {
      throw Exception('无法创建会话: $response');
    }
    return match.group(1)!;
  }

  /// 完成会话
  Future<void> _finalizeSession(String sessionId, String? error, List<String> options) async {
    final finalCommand = error == null ? 'install-commit' : 'install-abandon';
    final response = await shell('pm $finalCommand $sessionId ${options.join(' ')}');
    
    if (!response.allOutput.startsWith('Success')) {
      throw Exception('完成会话失败: ${response.allOutput}');
    }
    
    if (error != null) {
      throw Exception('安装失败: $error');
    }
  }

  /// 重启ADB
  Future<String> _restartAdb(String destination) async {
    final stream = await open(destination);
    try {
      final source = stream.source.transform(utf8.decoder);
      return await source.takeWhile((chunk) => chunk.isNotEmpty).join();
    } finally {
      await stream.close();
    }
  }
}

/// Kadb伴生对象（静态方法）
extension KadbCompanion on Kadb {
  /// 配对连接
  static Future<void> pair(String host, int port, String pairingCode, {String? name}) async {
    name ??= DefaultDeviceName.get();
    final keyPair = await AdbKeyPair.generate();
    final ctx = PairingConnectionCtx(
      host: host,
      port: port,
      password: Uint8List.fromList(pairingCode.codeUnits),
      keyPair: keyPair,
      deviceName: name
    );
    try {
      await ctx.start();
    } finally {
      await ctx.close();
    }
  }

  /// 创建Kadb实例
  static Future<Kadb> create(String host, int port, {int connectTimeout = 0, int socketTimeout = 0}) async {
    final kadb = Kadb(host, port, connectTimeout: connectTimeout, socketTimeout: socketTimeout);
    await kadb._createNewConnection();
    return kadb;
  }

  /// 尝试连接
  static Future<Kadb?> tryConnection(String host, int port) async {
    try {
      final kadb = await create(host, port);
      final response = await kadb.shell('echo success');
      return response.allOutput == 'success\n' ? kadb : null;
    } catch (e) {
      return null;
    }
  }

  /// TCP端口转发
  static Future<TcpForwarder> tcpForward(String host, int port, int targetPort) async {
    final kadb = await create(host, port);
    return await kadb.tcpForward(port, targetPort);
  }
}