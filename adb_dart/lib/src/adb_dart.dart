/// 主Kadb类
///
/// 提供完整的ADB功能接口，包括Shell命令、文件传输、应用管理等
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'core/adb_connection.dart' as core hide AdbStream;
import 'core/adb_protocol.dart';
import 'core/adb_reader.dart';
import 'core/adb_writer.dart';
import 'cert/cert_utils.dart';
import 'cert/adb_key_pair.dart' as cert;
import 'stream/adb_stream.dart' as stream;  // Use alias to avoid conflicts
import 'stream/adb_sync_stream.dart';
import 'stream/adb_shell_stream.dart';
import 'queue/adb_message_queue.dart';
import 'shell/adb_shell_response.dart';
import 'exception/adb_exceptions.dart';
import 'forwarding/tcp_forwarder.dart';
import 'pair/pairing_connection_ctx.dart';

/// 主Kadb类
///
/// 提供完整的ADB功能接口
class Kadb {
  final String _host;
  final int _port;
  final Duration? _connectionTimeout;
  final Duration? _readTimeout;
  final Duration? _writeTimeout;

  core.AdbConnection? _connection;
  cert.AdbKeyPair? _keyPair; // Use full namespace
  bool _isClosed = false;

  /// 构造函数
  Kadb(
    this._host,
    this._port, {
    Duration? connectionTimeout,
    Duration? readTimeout,
    Duration? writeTimeout,
  }) : _connectionTimeout = connectionTimeout,
       _readTimeout = readTimeout,
       _writeTimeout = writeTimeout;

  /// 获取连接的主机
  String get host => _host;

  /// 获取连接的端口
  int get port => _port;

  /// 检查是否已连接
  bool get isConnected => _connection != null;

  /// 检查是否已关闭
  bool get isClosed => _isClosed;

  /// 检查连接状态
  bool connectionCheck() {
    try {
      return isConnected;
    } catch (e) {
      return false;
    }
  }

  /// 获取当前连接
  core.AdbConnection get connection {
    if (_connection == null) {
      throw AdbConnectionException('未建立连接');
    }
    return _connection!;
  }

  /// 建立连接
  Future<void> connect({cert.AdbKeyPair? keyPair}) async {
    if (_isClosed) {
      throw AdbConnectionException('连接已关闭');
    }

    if (_connection != null) {
      return; // 已连接
    }

    try {
      _keyPair = keyPair ?? await CertUtils.generateKeyPair();

      _connection = await core.AdbConnection.connect(
        host: _host,
        port: _port,
        keyPair: _keyPair,
        connectionTimeout: _connectionTimeout,
        readTimeout: _readTimeout,
        writeTimeout: _writeTimeout,
      );
    } catch (e) {
      throw AdbConnectionException('建立连接失败', cause: e);
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    if (_connection != null) {
      try {
        await _connection!.close();
      } catch (e) {
        // 忽略断开错误
      }
      _connection = null;
    }
  }

  /// 执行Shell命令（同步）
  ///
  /// [command] 要执行的命令
  /// 返回命令执行结果
  Future<AdbShellResponse> shell(String command) async {
    await _ensureConnected();

    final stream = await openShellStream(command);
    final response = await stream.readAll();
    await stream.close();

    return response;
  }

  /// 执行Shell命令（交互式）
  ///
  /// [command] 要执行的命令（可选，为空则启动交互式Shell）
  /// 返回Shell流对象
  Future<AdbShellStream> openShellStream([String command = '']) async {
    await _ensureConnected();

    final destination = command.isEmpty ? 'shell,v2,raw:' : 'shell,v2,raw:$command';
    final basicStream = await connection.openStream(destination);

    // 创建消息队列和写入器来包装基本流
    final messageQueue = AdbMessageQueue();
    // 需要使用连接的基础写入器而不是流的私有字段
    // 由于类型系统限制，这里使用直接转换
    final writer = connection as dynamic; // 临时解决方案

    // 创建完整的流
    final wrappedStream = stream.AdbStream(
      messageQueue: messageQueue,
      writer: writer,
      maxPayloadSize: connection.maxPayloadSize,
      localId: basicStream.localId,
      remoteId: basicStream.remoteId,
    );

    return AdbShellStream(wrappedStream);
  }

  /// 推送文件到设备
  ///
  /// [localFile] 本地文件路径
  /// [remotePath] 远程路径
  /// [onProgress] 进度回调（可选）
  Future<void> pushFile({
    required String localFile,
    required String remotePath,
    void Function(int transferred, int total)? onProgress,
  }) async {
    await _ensureConnected();

    final file = File(localFile);
    if (!file.existsSync()) {
      throw AdbFileException('本地文件不存在', localPath: localFile);
    }

    final syncStream = await _openSyncStream();

    try {
      await syncStream.sendFile(
        localFile: file,
        remotePath: remotePath,
        onProgress: onProgress != null ? (transferred, total) {
          onProgress(transferred, total);
        } : null,
      );
    } finally {
      await syncStream.close();
    }
  }

  /// 推送数据流到设备
  ///
  /// [data] 数据流
  /// [remotePath] 远程路径
  /// [size] 数据大小
  /// [onProgress] 进度回调（可选）
  Future<void> pushStream({
    required Stream<List<int>> data,
    required String remotePath,
    required int size,
    void Function(int transferred, int total)? onProgress,
  }) async {
    await _ensureConnected();

    final syncStream = await _openSyncStream();

    try {
      await syncStream.sendData(
        data: data,
        remotePath: remotePath,
        size: size,
        mode: 0x1A4, // 默认权限 (0o644 = 0x1A4)
        lastModifiedMs: DateTime.now().millisecondsSinceEpoch,
        onProgress: onProgress != null ? (transferred, total) {
          onProgress(transferred, total);
        } : null,
      );
    } finally {
      await syncStream.close();
    }
  }

  /// 从设备拉取文件
  ///
  /// [localFile] 本地文件路径
  /// [remotePath] 远程路径
  /// [onProgress] 进度回调（可选）
  Future<void> pullFile({
    required String localFile,
    required String remotePath,
    void Function(int transferred, int total)? onProgress,
  }) async {
    await _ensureConnected();

    final file = File(localFile);
    if (file.existsSync()) {
      // 备份现有文件
      final backupFile = File('$localFile.backup');
      if (backupFile.existsSync()) {
        await backupFile.delete();
      }
      await file.rename(backupFile.path);
    }

    final syncStream = await _openSyncStream();

    try {
      await syncStream.receiveFile(
        localFile: localFile,
        remotePath: remotePath,
        onProgress: onProgress,
      );
    } catch (e) {
      // 恢复备份文件
      final backupFile = File('$localFile.backup');
      if (backupFile.existsSync()) {
        await backupFile.rename(localFile);
      }
      rethrow;
    } finally {
      await syncStream.close();

      // 删除备份文件
      final backupFile = File('$localFile.backup');
      if (backupFile.existsSync()) {
        await backupFile.delete();
      }
    }
  }

  /// 拉取数据流
  ///
  /// [sink] 数据接收器
  /// [remotePath] 远程路径
  /// [onProgress] 进度回调（可选）
  Future<void> pullStream({
    required EventSink<List<int>> sink,
    required String remotePath,
    void Function(int transferred, int total)? onProgress,
  }) async {
    await _ensureConnected();

    final syncStream = await _openSyncStream();

    try {
      await syncStream.receiveData(
        sink: sink,
        remotePath: remotePath,
        onProgress: onProgress,
      );
    } finally {
      await syncStream.close();
    }
  }

  /// 获取文件状态
  Future<Map<String, dynamic>> statFile(String remotePath) async {
    await _ensureConnected();

    final syncStream = await _openSyncStream();

    try {
      final fileInfo = await syncStream.stat(remotePath);
      return {
        'mode': fileInfo.mode,
        'size': fileInfo.size,
        'modificationTime': fileInfo.modificationTime,
        'permissions': _formatPermissions(fileInfo.mode),
      };
    } finally {
      await syncStream.close();
    }
  }

  /// 列出目录内容
  Future<List<Map<String, dynamic>>> listDirectory(String remotePath) async {
    await _ensureConnected();

    final syncStream = await _openSyncStream();

    try {
      final entries = await syncStream.listDirectory(remotePath);
      return entries.map((entry) => {
        'name': entry.name,
        'mode': entry.mode,
        'size': entry.size,
        'modificationTime': entry.modificationTime,
        'isDirectory': entry.isDirectory,
        'isFile': entry.isFile,
        'isSymbolicLink': entry.isSymbolicLink,
        'permissions': entry.permissions,
      }).toList();
    } finally {
      await syncStream.close();
    }
  }

  /// 安装APK文件
  ///
  /// [apkFile] APK文件路径
  /// [options] 安装选项（可选）
  Future<void> installApk({
    required String apkFile,
    List<String> options = const [],
  }) async {
    final file = File(apkFile);
    if (!file.existsSync()) {
      throw AdbFileException('APK文件不存在', localPath: apkFile);
    }

    final fileSize = file.lengthSync();

    // 检查是否支持cmd命令
    if (connection.supportsFeature('cmd')) {
      // 使用新的安装方式
      final stream = await connection.openStream('exec:cmd package install -S $fileSize ${options.join(' ')}');

      try {
        // 推送APK数据
        final reader = _StreamReader(stream);
        final writer = _StreamWriter(stream);

        await file.openRead().listen((data) {
          writer.writeBytes(data);
        }).asFuture();

        writer.flush();

        // 读取响应
        final response = await reader.readAll();
        if (!response.trim().startsWith('Success')) {
          throw AdbShellException('APK安装失败',
              output: response, errorCode: 'INSTALL_FAILED');
        }
      } finally {
        await stream.close();
      }
    } else {
      // 使用旧的安装方式
      await _installApkLegacy(apkFile, options);
    }
  }

  /// 卸载应用
  ///
  /// [packageName] 包名
  Future<void> uninstallApp(String packageName) async {
    final response = await shell('pm uninstall $packageName');
    if (response.exitCode != 0) {
      throw AdbShellException('卸载失败',
          command: 'pm uninstall $packageName',
          output: response.output,
          errorOutput: response.errorOutput,
          exitCode: response.exitCode);
    }
  }

  /// 获取设备信息
  Future<Map<String, String>> getDeviceInfo() async {
    final response = await shell('getprop');
    final info = <String, String>{};

    for (final line in response.outputLines) {
      final parts = line.split(': ');
      if (parts.length == 2) {
        final key = parts[0].replaceAll('[', '').replaceAll(']', '').trim();
        final value = parts[1].replaceAll('[', '').replaceAll(']', '').trim();
        info[key] = value;
      }
    }

    return info;
  }

  /// 获取设备序列号
  Future<String> getSerialNumber() async {
    final response = await shell('getprop ro.serialno');
    return response.output.trim();
  }

  /// 获取Android版本
  Future<String> getAndroidVersion() async {
    final response = await shell('getprop ro.build.version.release');
    return response.output.trim();
  }

  /// 重启设备
  Future<void> reboot() async {
    final stream = await connection.openStream('reboot:');
    await stream.close();
  }

  /// 重启到恢复模式
  Future<void> rebootRecovery() async {
    await shell('reboot recovery');
  }

  /// 重启到引导加载程序
  Future<void> rebootBootloader() async {
    await shell('reboot bootloader');
  }

  /// 创建TCP端口转发
  ///
  /// [localPort] 本地端口
  /// [devicePort] 设备端口
  /// 返回TCP转发器对象
  Future<TcpForwarder> tcpForward(int localPort, int devicePort) async {
    await _ensureConnected();

    final forwarder = TcpForwarder(
      kadb: this,
      hostPort: localPort,
      targetPort: devicePort,
    );

    await forwarder.start();
    return forwarder;
  }

  /// 执行WiFi设备配对
  ///
  /// [host] 设备主机地址
  /// [port] 配对端口（通常是5555）
  /// [pairingCode] 配对码（显示在设备上）
  /// [deviceName] 设备名称
  static Future<void> pair(String host, int port, String pairingCode, {
    String deviceName = 'adb_dart',
    cert.AdbKeyPair? keyPair,
  }) async {
    final actualKeyPair = keyPair ?? await CertUtils.generateKeyPair();

    await PairingManager.pairDevice(
      host: host,
      port: port,
      pairingCode: pairingCode,
      keyPair: actualKeyPair,
      deviceName: deviceName,
    );
  }

  /// 检查设备是否已配对
  static bool isDevicePaired(String host, int port) {
    return PairingManager.isDevicePaired(host, port);
  }

  /// 获取配对设备地址
  static String getPairedDeviceAddress(String host, int port) {
    return PairingManager.getPairedDeviceAddress(host, port);
  }

  /// 取消设备配对
  static void unpair(String host, int port) {
    PairingManager.unpairDevice(host, port);
  }

  /// 确保已连接
  Future<void> _ensureConnected() async {
    if (_isClosed) {
      throw AdbConnectionException('连接已关闭');
    }

    if (_connection == null || !_connection!.isConnected) {
      await connect();
    }
  }

  /// 打开同步流
  Future<AdbSyncStream> _openSyncStream() async {
    final stream = await connection.openStream('sync:');
    return AdbSyncStream(stream);
  }

  /// 旧的APK安装方式
  Future<void> _installApkLegacy(String apkFile, List<String> options) async {
    final tempPath = '/data/local/tmp/${DateTime.now().millisecondsSinceEpoch}.apk';

    try {
      // 推送APK到临时目录
      await pushFile(
        localFile: apkFile,
        remotePath: tempPath,
      );

      // 安装APK
      final response = await shell('pm install ${options.join(' ')} "$tempPath"');
      if (response.exitCode != 0) {
        throw AdbShellException('APK安装失败',
            command: 'pm install',
            output: response.output,
            errorOutput: response.errorOutput,
            exitCode: response.exitCode);
      }
    } finally {
      // 删除临时文件
      await shell('rm -f "$tempPath"').catchError((_) {});
    }
  }

  /// 格式化文件权限
  String _formatPermissions(int mode) {
    final buffer = StringBuffer();

    // 文件类型
    if ((mode & 0x4000) != 0) {
      buffer.write('d');
    } else if ((mode & 0xA000) != 0) {
      buffer.write('l');
    } else {
      buffer.write('-');
    }

    // 权限
    buffer.write((mode >> 6) & 0x4 != 0 ? 'r' : '-');
    buffer.write((mode >> 6) & 0x2 != 0 ? 'w' : '-');
    buffer.write((mode >> 6) & 0x1 != 0 ? 'x' : '-');

    buffer.write((mode >> 3) & 0x4 != 0 ? 'r' : '-');
    buffer.write((mode >> 3) & 0x2 != 0 ? 'w' : '-');
    buffer.write((mode >> 3) & 0x1 != 0 ? 'x' : '-');

    buffer.write(mode & 0x4 != 0 ? 'r' : '-');
    buffer.write(mode & 0x2 != 0 ? 'w' : '-');
    buffer.write(mode & 0x1 != 0 ? 'x' : '-');

    return buffer.toString();
  }

  /// 关闭Kadb实例
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    await disconnect();
  }

  /// 创建新的Kadb实例
  factory Kadb.create({
    required String host,
    required int port,
    Duration? connectionTimeout,
    Duration? readTimeout,
    Duration? writeTimeout,
  }) {
    return Kadb(
      host,
      port,
      connectionTimeout: connectionTimeout,
      readTimeout: readTimeout,
      writeTimeout: writeTimeout,
    );
  }

  /// 测试连接
  static Future<bool> testConnection(String host, int port) async {
    try {
      final adb = Kadb(host, port);
      await adb.connect();
      final response = await adb.shell('echo test');
      await adb.close();
      return response.output.trim() == 'test';
    } catch (e) {
      return false;
    }
  }
}

/// 流读取器辅助类
class _StreamReader {
  final AdbStream _stream;
  final StringBuffer _buffer = StringBuffer();

  _StreamReader(this._stream);

  Future<String> readAll() async {
    await for (final data in _stream.inputStream) {
      _buffer.write(String.fromCharCodes(data));
    }
    return _buffer.toString();
  }
}

/// 流写入器辅助类
class _StreamWriter {
  final AdbStream _stream;

  _StreamWriter(this._stream);

  Future<void> writeBytes(Uint8List data) async {
    await _stream.write(data);
  }

  Future<void> flush() async {
    // ADB协议中，flush是隐式的
  }
}
