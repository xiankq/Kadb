/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'cert/cert_utils.dart';
import 'core/adb_connection.dart';
import 'shell/adb_shell_response.dart';
import 'shell/adb_shell_stream.dart';
import 'stream/adb_stream.dart';
import 'sync/adb_sync_stream.dart';
import 'forwarding/tcp_forwarder.dart';
import 'pair/pairing_connection_ctx.dart';

/// ADB客户端类，提供完整的ADB功能接口
class AdbClient {
  final String host;
  final int port;
  final Duration connectTimeout;
  final Duration socketTimeout;

  AdbConnection? _connection;
  bool _isDisposed = false;

  AdbClient({
    required this.host,
    this.port = 5037,
    this.connectTimeout = const Duration(seconds: 10),
    this.socketTimeout = Duration.zero,
  });

  /// 检查连接状态
  bool get isConnected => _connection != null;

  /// 连接到ADB服务器
  Future<void> connect() async {
    if (_isDisposed) {
      throw StateError('客户端已释放');
    }

    if (_connection != null) {
      return; // 已经连接
    }

    try {
      // 加载密钥对
      final keyPair = await CertUtils.loadKeyPair();

      // 建立连接
      _connection = await AdbConnection.connect(
        host: host,
        port: port,
        keyPair: keyPair,
        connectTimeout: connectTimeout,
        ioTimeout: socketTimeout,
      );

      print('成功连接到ADB服务器：$host:$port');
    } catch (e) {
      _connection = null;
      throw Exception('连接ADB服务器失败：$e');
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    if (_connection != null) {
      await _connection!.close();
      _connection = null;
      print('已断开与ADB服务器的连接');
    }
  }

  /// 执行shell命令并返回结果
  Future<AdbShellResponse> shell(String command) async {
    await _ensureConnected();

    final shellStream = await openShell(command);
    return await shellStream.readAll();
  }

  /// 打开shell流
  Future<AdbShellStream> openShell([String command = '']) async {
    await _ensureConnected();

    final stream = await _connection!.open('shell,v2,raw:$command');
    return AdbShellStream(stream);
  }

  /// 检查是否支持某个特性
  Future<bool> supportsFeature(String feature) async {
    await _ensureConnected();
    return _connection!.supportsFeature(feature);
  }

  /// 安装APK文件
  Future<void> install(File apkFile, [List<String> options = const []]) async {
    await _ensureConnected();

    if (!await apkFile.exists()) {
      throw ArgumentError('APK文件不存在：${apkFile.path}');
    }

    // 检查是否支持cmd特性
    if (await supportsFeature('cmd')) {
      await _installWithCmd(apkFile, options);
    } else {
      await _installWithPm(apkFile, options);
    }
  }

  /// 安装APK（使用Source）
  Future<void> installStream(
    Stream<List<int>> source,
    int size, [
    List<String> options = const [],
  ]) async {
    await _ensureConnected();

    // 检查是否支持cmd特性
    if (await supportsFeature('cmd')) {
      await _installStreamWithCmd(source, size, options);
    } else {
      // 创建临时文件
      final tempFile = await _createTempFileFromStream(source);
      try {
        await _installWithPm(tempFile, options);
      } finally {
        await tempFile.delete();
      }
    }
  }

  /// 安装多个APK文件
  Future<void> installMultiple(
    List<File> apks, [
    List<String> options = const [],
  ]) async {
    await _ensureConnected();

    // 验证所有文件存在
    for (final apk in apks) {
      if (!await apk.exists()) {
        throw ArgumentError('APK文件不存在：${apk.path}');
      }
    }

    // 检查是否支持abb_exec特性
    if (await supportsFeature('abb_exec')) {
      await _installMultipleWithAbb(apks, options);
    } else {
      await _installMultipleWithPm(apks, options);
    }
  }

  /// 使用cmd命令安装APK
  Future<void> _installWithCmd(File apkFile, List<String> options) async {
    try {
      final stream = await _connection!.open(
        'exec:cmd package install -S ${apkFile.length} ${options.join(' ')}',
      );

      // 创建文件读取流
      final fileStream = apkFile.openRead();
      await for (final chunk in fileStream) {
        await stream.write(chunk);
      }
      await stream.write([]); // 发送结束标记

      // 读取响应
      final response = await stream.read();
      final responseStr = String.fromCharCodes(response);

      if (!responseStr.startsWith('Success')) {
        throw Exception('安装失败：$responseStr');
      }
    } catch (e) {
      throw Exception('安装失败：$e');
    }
  }

  /// 使用cmd命令安装APK流
  Future<void> _installStreamWithCmd(
    Stream<List<int>> source,
    int size,
    List<String> options,
  ) async {
    try {
      final stream = await _connection!.open(
        'exec:cmd package install -S $size ${options.join(' ')}',
      );

      // 写入数据流
      await for (final chunk in source) {
        await stream.write(chunk);
      }
      await stream.write([]); // 发送结束标记

      // 读取响应
      final response = await stream.read();
      final responseStr = String.fromCharCodes(response);

      if (!responseStr.startsWith('Success')) {
        throw Exception('安装失败：$responseStr');
      }
    } catch (e) {
      throw Exception('安装失败：$e');
    }
  }

  /// 使用pm命令安装APK
  Future<void> _installWithPm(File apkFile, List<String> options) async {
    try {
      final remotePath = '/data/local/tmp/${apkFile.uri.pathSegments.last}';

      // 推送APK文件到设备
      await push(apkFile, remotePath);

      // 执行安装命令
      final result = await shell(
        'pm install ${options.join(' ')} "$remotePath"',
      );

      if (!result.isSuccess) {
        throw Exception('安装失败：${result.allOutput}');
      }
    } catch (e) {
      throw Exception('安装失败：$e');
    }
  }

  /// 使用abb_exec安装多个APK
  Future<void> _installMultipleWithAbb(
    List<File> apks,
    List<String> options,
  ) async {
    try {
      final totalLength = apks.fold<int>(
        0,
        (sum, apk) => sum + apk.lengthSync(),
      );

      // 创建安装会话
      final createStream = await _connection!.open(
        'abb_exec:package\u0000install-create\u0000-S\u0000$totalLength\u0000${options.join('\u0000')}',
      );
      final createResponse = await createStream.read();
      final sessionId = _extractSessionId(String.fromCharCodes(createResponse));

      // 逐个安装APK
      String? error;
      for (final apk in apks) {
        try {
          final writeStream = await _connection!.open(
            'abb_exec:package\u0000install-write\u0000-S\u0000${apk.lengthSync()}\u0000$sessionId\u0000${apk.uri.pathSegments.last}\u0000-\u0000${options.join('\u0000')}',
          );

          // 传输APK数据
          final fileStream = apk.openRead();
          await for (final chunk in fileStream) {
            await writeStream.write(chunk);
          }
          await writeStream.write([]);

          // 检查响应
          final response = await writeStream.read();
          final responseStr = String.fromCharCodes(response);
          if (!responseStr.startsWith('Success')) {
            error = responseStr;
            break;
          }
        } catch (e) {
          error = e.toString();
          break;
        }
      }

      // 完成或放弃会话
      _finalizeSession(sessionId, error, options);
    } catch (e) {
      throw Exception('多APK安装失败：$e');
    }
  }

  /// 卸载应用
  Future<void> uninstall(String packageName) async {
    await _ensureConnected();

    final result = await shell('cmd package uninstall $packageName');
    if (!result.isSuccess) {
      throw Exception('卸载失败：${result.allOutput}');
    }
  }

  /// 推送文件到设备
  Future<void> push(File localFile, String remotePath) async {
    await _ensureConnected();

    if (!await localFile.exists()) {
      throw ArgumentError('本地文件不存在：${localFile.path}');
    }

    try {
      final syncStream = AdbSyncStream(await _connection!.open('sync:'));

      // 获取文件模式
      final mode = _readFileMode(localFile);
      final lastModified = localFile.lastModifiedSync().millisecondsSinceEpoch;

      await syncStream.send(localFile, remotePath, mode, lastModified);
      await syncStream.close();
    } catch (e) {
      throw Exception('文件推送失败：$e');
    }
  }

  /// 从设备拉取文件
  Future<void> pull(String remotePath, File localFile) async {
    await _ensureConnected();

    try {
      final syncStream = AdbSyncStream(await _connection!.open('sync:'));

      await syncStream.recv(remotePath, localFile);
      await syncStream.close();
    } catch (e) {
      throw Exception('文件拉取失败：$e');
    }
  }

  /// 重启adb守护进程为root模式
  Future<String> root() async {
    await _ensureConnected();

    final stream = await _connection!.open('root:');
    // TODO: 实现完整的数据读取
    throw UnimplementedError('root功能待实现');
  }

  /// 重启adb守护进程为非root模式
  Future<String> unroot() async {
    await _ensureConnected();

    final stream = await _connection!.open('unroot:');
    final response = await stream.read();
    return String.fromCharCodes(response);
  }

  /// 执行cmd命令
  Future<AdbStream> execCmd(List<String> command) async {
    await _ensureConnected();
    return await _connection!.open('exec:cmd ${command.join(' ')}');
  }

  /// 打开指定目标的流
  Future<AdbStream> openStream(String destination) async {
    await _ensureConnected();
    return await _connection!.open(destination);
  }

  /// 执行abb_exec命令
  Future<AdbStream> abbExec(List<String> command) async {
    await _ensureConnected();
    return await _connection!.open('abb_exec:${command.join('\u0000')}');
  }

  /// 设置TCP端口转发
  Future<TcpForwarder> tcpForward(int hostPort, int targetPort) async {
    await _ensureConnected();

    final forwarder = TcpForwarder(this, hostPort, targetPort);
    await forwarder.start();
    return forwarder;
  }

  /// 确保已连接
  Future<void> _ensureConnected() async {
    if (_isDisposed) {
      throw StateError('客户端已释放');
    }

    if (_connection == null) {
      await connect();
    }
  }

  /// 读取文件模式
  int _readFileMode(File file) {
    if (Platform.isWindows) {
      return SyncProtocol.defaultFileMode;
    }

    try {
      final result = Process.runSync('stat', ['-c', '%a', file.path]);
      if (result.exitCode == 0) {
        return int.tryParse(result.stdout.trim()) ??
            SyncProtocol.defaultFileMode;
      }
    } catch (e) {
      // 忽略错误，使用默认模式
    }

    return SyncProtocol.defaultFileMode;
  }

  /// 从数据流创建临时文件
  Future<File> _createTempFileFromStream(Stream<List<int>> source) async {
    final tempFile = File(
      '${Directory.systemTemp.path}/temp_${DateTime.now().millisecondsSinceEpoch}.apk',
    );
    final sink = tempFile.openWrite();

    try {
      await for (final chunk in source) {
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    return tempFile;
  }

  /// 提取会话ID
  String _extractSessionId(String response) {
    final match = RegExp(r'\[(\w+)\]').firstMatch(response);
    if (match != null) {
      return match.group(1)!;
    } else {
      throw Exception('无法从响应提取会话ID：$response');
    }
  }

  /// 完成或放弃会话
  Future<void> _finalizeSession(
    String sessionId,
    String? error,
    List<String> options,
  ) async {
    final finalCommand = error == null ? 'install-commit' : 'install-abandon';

    try {
      final result = await shell(
        'pm $finalCommand $sessionId ${options.join(' ')}',
      );

      if (!result.allOutput.startsWith('Success')) {
        throw Exception('无法完成会话：${result.allOutput}');
      }

      if (error != null) {
        throw Exception('安装失败：$error');
      }
    } catch (e) {
      throw Exception('会话完成失败：$e');
    }
  }

  /// 使用pm安装多个APK
  Future<void> _installMultipleWithPm(
    List<File> apks,
    List<String> options,
  ) async {
    try {
      final totalLength = apks.fold<int>(
        0,
        (sum, apk) => sum + apk.lengthSync(),
      );

      // 创建会话
      final response = await shell(
        'pm install-create -S $totalLength ${options.join(' ')}',
      );
      final sessionId = _extractSessionId(response.allOutput);

      // 逐个推送和安装APK
      String? error;
      for (int i = 0; i < apks.length; i++) {
        final apk = apks[i];
        final result = await _pushAndWrite(apk, sessionId, i);

        if (!result.startsWith('Success')) {
          error = result;
          break;
        }
      }

      // 完成或放弃会话
      await _finalizeSession(sessionId, error, options);
    } catch (e) {
      throw Exception('多APK安装失败：$e');
    }
  }

  /// 推送并写入APK
  Future<String> _pushAndWrite(File apk, String sessionId, int index) async {
    final remotePath = '/data/local/tmp/${apk.uri.pathSegments.last}';
    await push(apk, remotePath);

    final result = await shell(
      'pm install-write -S ${apk.lengthSync()} $sessionId $index $remotePath',
    );
    return result.allOutput;
  }

  /// 释放资源
  Future<void> dispose() async {
    _isDisposed = true;
    await disconnect();
  }

  /// 设备配对（静态方法）
  static Future<void> pair({
    required String host,
    required int port,
    required String pairingCode,
    String deviceName = '',
  }) async {
    // 如果未提供设备名称，使用默认值
    final actualDeviceName = deviceName.isEmpty
        ? CertUtils.getDefaultDeviceName()
        : deviceName;

    // 加载密钥对
    final keyPair = await CertUtils.loadKeyPair();

    // 创建配对连接上下文
    final pairingCtx = PairingConnectionCtx(
      host: host,
      port: port,
      pairingCode: Uint8List.fromList(pairingCode.codeUnits),
      keyPair: keyPair,
      deviceName: actualDeviceName,
    );

    // 执行配对
    await pairingCtx.start();
  }

  /// 创建ADB客户端实例
  static AdbClient create({
    required String host,
    int port = 5037,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration socketTimeout = Duration.zero,
  }) {
    return AdbClient(
      host: host,
      port: port,
      connectTimeout: connectTimeout,
      socketTimeout: socketTimeout,
    );
  }

  /// 测试连接
  static Future<AdbClient?> tryConnection(String host, int port) async {
    try {
      final client = create(host: host, port: port);
      await client.connect();

      // 测试执行简单命令
      final result = await client.shell('echo success');
      if (result.stdout.trim() == 'success') {
        return client;
      }

      await client.dispose();
      return null;
    } catch (e) {
      return null;
    }
  }
}
