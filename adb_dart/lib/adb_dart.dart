/// AdbDart - 纯Dart实现的ADB协议库
/// 完整复刻Kadb功能，提供简洁的API接口

library adb_dart;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'src/core/adb_connection.dart';
import 'src/cert/adb_key_pair.dart';
import 'src/stream/adb_stream.dart';
import 'src/stream/adb_sync_stream.dart';
import 'src/exception/adb_exceptions.dart';

// 导出TLS和配对功能
export 'src/tls/ssl_utils.dart' show SslUtils, TlsWrapper, TlsConfig;
export 'src/pair/pairing_connection_ctx.dart'
    show DevicePairingManager, TlsDevicePairingManager, TlsPairingConnectionCtx;
export 'src/stream/adb_sync_stream.dart' show FileInfo, DirectoryEntry;

/// 主ADB客户端类
class AdbDart {
  final String host;
  final int port;
  final Duration connectTimeout;
  final Duration socketTimeout;
  final AdbKeyPair? keyPair;

  AdbConnection? _connection;

  AdbDart({
    this.host = 'localhost',
    this.port = 5555,
    this.connectTimeout = const Duration(seconds: 10),
    this.socketTimeout = const Duration(seconds: 30),
    this.keyPair,
  });

  /// 获取当前连接状态
  bool get isConnected => _connection?.state == AdbConnectionState.connected;

  /// 获取连接对象
  AdbConnection? get connection => _connection;

  /// 建立ADB连接
  Future<void> connect() async {
    if (isConnected) {
      return; // 已经连接
    }

    try {
      _connection = AdbConnection(
        host: host,
        port: port,
        keyPair: keyPair ?? AdbKeyPair.generate(),
        connectTimeout: connectTimeout,
        socketTimeout: socketTimeout,
      );
      await _connection!.connect();
    } catch (e) {
      throw AdbConnectionException('连接失败: $e');
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    if (_connection != null) {
      await _connection!.close();
      _connection = null;
    }
  }

  /// 执行shell命令
  Future<String> shell(String command) async {
    await _ensureConnected();

    final stream = await _connection!.openStream('shell:$command');
    try {
      final output = StringBuffer();

      // 读取所有输出
      final allData = await stream.read();
      output.write(String.fromCharCodes(allData));

      return output.toString().trim();
    } finally {
      await stream.close();
    }
  }

  /// 打开交互式Shell
  Future<AdbStream> openShell() async {
    await _ensureConnected();
    return await _connection!.openStream('shell:');
  }

  /// 推送文件到设备
  Future<void> push(
    Uint8List data,
    String remotePath, {
    int mode = 0x1A4, // 0o644 in hex
    DateTime? lastModified,
  }) async {
    await _ensureConnected();

    final stream = await _connection!.openStream('sync:');
    final syncStream = AdbSyncStream(stream);

    try {
      // 创建临时文件
      final tempFile = File(
          '${Directory.systemTemp.path}/adb_push_${DateTime.now().millisecondsSinceEpoch}');
      await tempFile.writeAsBytes(data);

      // 发送文件
      await syncStream.send(tempFile, remotePath,
          mode: mode, lastModified: lastModified);

      // 清理临时文件
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } finally {
      await syncStream.close();
    }
  }

  /// 从设备拉取文件
  Future<Uint8List> pull(String remotePath) async {
    await _ensureConnected();

    final stream = await _connection!.openStream('sync:');
    final syncStream = AdbSyncStream(stream);

    try {
      // 创建临时文件
      final tempFile = File(
          '${Directory.systemTemp.path}/adb_pull_${DateTime.now().millisecondsSinceEpoch}');

      // 接收文件
      await syncStream.recv(remotePath, tempFile);

      // 读取数据
      final data = await tempFile.readAsBytes();

      // 清理临时文件
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      return data;
    } finally {
      await syncStream.close();
    }
  }

  /// 安装APK
  Future<void> installApk(String apkPath,
      {List<String> options = const []}) async {
    await _ensureConnected();

    final file = File(apkPath);
    if (!file.existsSync()) {
      throw ArgumentException('APK文件不存在: $apkPath');
    }

    if (_connection!.supportsFeature('cmd')) {
      // 使用新的cmd命令安装
      await _installUsingCmd(file, options);
    } else {
      // 使用旧的pm install方式
      await _installUsingPm(file, options);
    }
  }

  /// 安装多个APK（Split APK支持）
  Future<void> installMultipleApk(List<String> apkPaths,
      {List<String> options = const []}) async {
    await _ensureConnected();

    // 验证所有APK文件存在
    final apkFiles = apkPaths.map((path) {
      final file = File(path);
      if (!file.existsSync()) {
        throw ArgumentException('APK文件不存在: $path');
      }
      return file;
    }).toList();

    if (_connection!.supportsFeature('abb_exec')) {
      // 使用abb_exec进行现代安装
      await _installMultipleUsingAbb(apkFiles, options);
    } else if (_connection!.supportsFeature('cmd')) {
      // 使用cmd package进行会话式安装
      await _installMultipleUsingCmd(apkFiles, options);
    } else {
      // 使用旧的pm install方式
      await _installMultipleUsingPm(apkFiles, options);
    }
  }

  /// 卸载应用
  Future<void> uninstallApp(String packageName) async {
    await _ensureConnected();

    if (_connection!.supportsFeature('cmd')) {
      // 使用cmd package uninstall
      final result = await shell('cmd package uninstall $packageName');
      if (result.contains('Failure')) {
        throw AdbException('卸载失败: $result');
      }
    } else {
      // 使用pm uninstall
      final result = await shell('pm uninstall $packageName');
      if (!result.contains('Success')) {
        throw AdbException('卸载失败: $result');
      }
    }
  }

  /// 获取文件状态信息
  Future<Map<String, dynamic>> statFile(String remotePath) async {
    await _ensureConnected();

    final stream = await _connection!.openStream('sync:');
    final syncStream = AdbSyncStream(stream);

    try {
      return await syncStream.stat(remotePath);
    } finally {
      await syncStream.close();
    }
  }

  /// 列出目录内容
  Future<List<DirectoryEntry>> listDirectory(String remotePath) async {
    await _ensureConnected();

    final stream = await _connection!.openStream('sync:');
    final syncStream = AdbSyncStream(stream);

    try {
      return await syncStream.list(remotePath);
    } finally {
      await syncStream.close();
    }
  }

  /// 获取设备属性
  Future<String> getProp(String property) async {
    return await shell('getprop $property');
  }

  /// 执行cmd命令
  Future<String> execCmd(String command, [List<String> args = const []]) async {
    await _ensureConnected();

    if (!_connection!.supportsFeature('cmd')) {
      throw AdbException('设备不支持cmd命令');
    }

    final argString = args.isNotEmpty ? ' ${args.join(' ')}' : '';
    return await shell('cmd $command$argString');
  }

  /// 执行abb_exec命令
  Future<String> abbExec(String command, [List<String> args = const []]) async {
    await _ensureConnected();

    if (!_connection!.supportsFeature('abb_exec')) {
      throw AdbException('设备不支持abb_exec命令');
    }

    final allArgs = [command, ...args];
    final stream =
        await _connection!.openStream('abb_exec:${allArgs.join('\x00')}');

    try {
      final output = StringBuffer();

      // 读取所有输出
      final allData = await stream.read();
      output.write(String.fromCharCodes(allData));

      return output.toString().trim();
    } finally {
      await stream.close();
    }
  }

  /// 获取root权限
  Future<String> root() async {
    return await _restartAdb('root:');
  }

  /// 取消root权限
  Future<String> unroot() async {
    return await _restartAdb('unroot:');
  }

  /// 获取设备序列号
  Future<String> getSerialNumber() async {
    return await getProp('ro.serialno');
  }

  /// 获取设备型号
  Future<String> getModel() async {
    return await getProp('ro.product.model');
  }

  /// 获取设备厂商
  Future<String> getManufacturer() async {
    return await getProp('ro.product.manufacturer');
  }

  /// 获取Android版本
  Future<String> getAndroidVersion() async {
    return await getProp('ro.build.version.release');
  }

  /// 重启设备
  Future<void> reboot([String? mode]) async {
    await _ensureConnected();

    if (mode != null) {
      await shell('reboot $mode');
    } else {
      await shell('reboot');
    }
  }

  /// 获取设备信息
  Future<DeviceInfo> getDeviceInfo() async {
    await _ensureConnected();

    return DeviceInfo(
      serialNumber: await getSerialNumber(),
      model: await getModel(),
      manufacturer: await getManufacturer(),
      androidVersion: await getAndroidVersion(),
      adbVersion: _connection!.version.toString(),
      maxPayloadSize: _connection!.maxPayloadSize,
      supportedFeatures: _connection!.supportedFeatures.toList(),
    );
  }

  /// 确保已连接
  Future<void> _ensureConnected() async {
    if (!isConnected) {
      await connect();
    }
  }

  /// 关闭连接
  Future<void> close() async {
    await disconnect();
  }

  /// 重启ADB服务
  Future<String> _restartAdb(String destination) async {
    final stream = await _connection!.openStream(destination);
    try {
      // 读取重启结果
      final data = await stream.read();
      return String.fromCharCodes(data).trim();
    } finally {
      await stream.close();
    }
  }

  /// 使用cmd命令安装APK
  Future<void> _installUsingCmd(File apkFile, List<String> options) async {
    final size = apkFile.lengthSync();
    final stream = await _connection!
        .openStream('exec:cmd package install -S $size ${options.join(' ')}');

    try {
      // 发送APK数据
      final data = await apkFile.readAsBytes();
      await stream.write(data);
      await stream.close();

      // 读取安装结果
      final result = await stream.readString();
      if (!result.startsWith('Success')) {
        throw AdbException('安装失败: $result');
      }
    } catch (e) {
      throw AdbException('APK安装失败', e);
    }
  }

  /// 使用pm install安装APK
  Future<void> _installUsingPm(File apkFile, List<String> options) async {
    final tempPath = '/data/local/tmp/${apkFile.uri.pathSegments.last}';
    final data = await apkFile.readAsBytes();
    await push(data, tempPath);

    // 执行安装命令
    final result = await shell('pm install ${options.join(' ')} "$tempPath"');
    if (!result.contains('Success')) {
      throw AdbException('安装失败: $result');
    }

    // 删除临时文件
    await shell('rm "$tempPath"');
  }

  /// 使用abb_exec安装多个APK（现代方式）
  Future<void> _installMultipleUsingAbb(
      List<File> apkFiles, List<String> options) async {
    final totalLength =
        apkFiles.fold<int>(0, (sum, file) => sum + file.lengthSync());

    // 创建安装会话
    final createStream = await _connection!.openStream(
        'abb_exec:package\x00install-create\x00-S\x00$totalLength\x00${options.join('\x00')}');

    try {
      final createResponse = await createStream.readString();
      final sessionId = _extractSessionId(createResponse);

      // 逐个写入APK文件
      String? error;
      for (int i = 0; i < apkFiles.length; i++) {
        final apk = apkFiles[i];
        final fileName = apk.path.split(Platform.pathSeparator).last;
        final writeStream = await _connection!.openStream(
            'abb_exec:package\x00install-write\x00-S\x00${apk.lengthSync()}\x00$sessionId\x00$fileName\x00-\x00${options.join('\x00')}');

        try {
          // 发送APK数据
          final data = await apk.readAsBytes();
          await writeStream.write(data);
          await writeStream.close();

          final response = await writeStream.readString();
          if (!response.startsWith('Success')) {
            error = response;
            break;
          }
        } catch (e) {
          error = '写入APK失败: $e';
          break;
        }
      }

      // 完成或放弃会话
      await _finalizeSession(sessionId, error, options);
    } catch (e) {
      throw AdbException('多APK安装失败', e);
    }
  }

  /// 使用cmd package安装多个APK（会话式安装）
  Future<void> _installMultipleUsingCmd(
      List<File> apkFiles, List<String> options) async {
    final totalLength =
        apkFiles.fold<int>(0, (sum, file) => sum + file.lengthSync());

    // 创建安装会话
    final createResponse = await shell(
        'cmd package install-create -S $totalLength ${options.join(' ')}');
    final sessionId = _extractSessionId(createResponse);

    // 逐个写入APK文件
    String? error;
    for (int i = 0; i < apkFiles.length; i++) {
      final apk = apkFiles[i];
      final fileName = apk.path.split(Platform.pathSeparator).last;

      try {
        // 推送APK到临时位置
        final data = await apk.readAsBytes();
        await push(data, '/data/local/tmp/$fileName');

        // 写入会话
        final response = await shell(
            'cmd package install-write -S ${apk.lengthSync()} $sessionId $i /data/local/tmp/$fileName');
        if (!response.startsWith('Success')) {
          error = response;
          break;
        }
      } catch (e) {
        error = '写入APK失败: $e';
        break;
      }
    }

    // 完成或放弃会话
    await _finalizeSession(sessionId, error, options);
  }

  /// 使用pm install安装多个APK（旧方式）
  Future<void> _installMultipleUsingPm(
      List<File> apkFiles, List<String> options) async {
    // 创建安装会话
    final createResponse = await shell(
        'pm install-create -S ${apkFiles.fold<int>(0, (sum, file) => sum + file.lengthSync())} ${options.join(' ')}');
    final sessionId = _extractSessionId(createResponse);

    // 逐个写入APK文件
    String? error;
    for (int i = 0; i < apkFiles.length; i++) {
      final apk = apkFiles[i];
      final fileName = apk.path.split(Platform.pathSeparator).last;

      try {
        // 推送APK到临时位置
        final data = await apk.readAsBytes();
        await push(data, '/data/local/tmp/$fileName');

        // 写入会话
        final response = await shell(
            'pm install-write -S ${apk.lengthSync()} $sessionId $i /data/local/tmp/$fileName');
        if (!response.startsWith('Success')) {
          error = response;
          break;
        }
      } catch (e) {
        error = '写入APK失败: $e';
        break;
      }
    }

    // 完成或放弃会话
    await _finalizeSession(sessionId, error, options);
  }

  /// 完成或放弃安装会话
  Future<void> _finalizeSession(
      String sessionId, String? error, List<String> options) async {
    final command = error == null ? 'install-commit' : 'install-abandon';
    final response =
        await shell('cmd package $command $sessionId ${options.join(' ')}');

    if (!response.startsWith('Success')) {
      throw AdbException('会话完成失败: $response');
    }

    if (error != null) {
      throw AdbException('安装失败: $error');
    }
  }

  /// 提取会话ID
  String _extractSessionId(String response) {
    final match = RegExp(r'\[(\w+)\]').firstMatch(response);
    if (match == null) {
      throw AdbException('无法创建安装会话: $response');
    }
    return match.group(1)!;
  }
}

/// 设备信息
class DeviceInfo {
  final String serialNumber;
  final String model;
  final String manufacturer;
  final String androidVersion;
  final String adbVersion;
  final int maxPayloadSize;
  final List<String> supportedFeatures;

  DeviceInfo({
    required this.serialNumber,
    required this.model,
    required this.manufacturer,
    required this.androidVersion,
    required this.adbVersion,
    required this.maxPayloadSize,
    required this.supportedFeatures,
  });

  @override
  String toString() {
    return '''DeviceInfo{
      序列号: $serialNumber
      型号: $model
      厂商: $manufacturer
      Android版本: $androidVersion
      ADB版本: $adbVersion
      最大载荷: $maxPayloadSize
      支持特性: ${supportedFeatures.join(', ')}
    }''';
  }
}

/// 参数异常
class ArgumentException extends AdbException {
  ArgumentException(super.message);
}
