/// Kadb Dart - 纯Dart实现的ADB客户端库
library;

export 'src/core/adb_protocol.dart';
export 'src/core/adb_message.dart';
export 'src/core/adb_reader.dart';
export 'src/core/adb_writer.dart';
export 'src/core/adb_connection.dart';
export 'src/security/adb_key_pair.dart';
export 'src/security/cert_utils.dart';
export 'src/transport/transport_channel.dart';
export 'src/stream/adb_stream.dart';
export 'src/stream/adb_shell_stream.dart';
export 'src/shell/adb_shell_response.dart';
export 'src/stream/adb_sync_stream.dart';
export 'src/forward/tcp_forwarder.dart';
export 'src/security/pairing_connection_ctx.dart';

import 'dart:async';
import 'dart:io';

import 'src/core/adb_connection.dart';
import 'src/security/adb_key_pair.dart';
import 'src/security/cert_utils.dart';
import 'src/stream/adb_shell_stream.dart';
import 'src/shell/adb_shell_response.dart';
import 'src/stream/adb_sync_stream.dart';
import 'src/stream/adb_stream.dart';
import 'src/forward/tcp_forwarder.dart';

/// ADB客户端主类
class KadbDart {
  /// 连接到ADB服务器
  static Future<AdbConnection> create({
    String host = 'localhost',
    int port = 5037,
    AdbKeyPair? keyPair,
    int connectTimeoutMs = 10000,
    int ioTimeoutMs = 30000,
    bool debug = false,
  }) async {
    final actualKeyPair = keyPair ?? await CertUtils.loadKeyPair();
    final connection = AdbConnection(
      keyPair: actualKeyPair,
      ioTimeout: Duration(milliseconds: ioTimeoutMs),
      debug: debug,
    );
    await connection.connect(host, port);
    return connection;
  }

  /// 执行Shell命令
  static Future<AdbShellStream> executeShell(
    AdbConnection connection,
    String command, {
    List<String> args = const [],
    bool debug = false,
  }) async {
    return AdbShellStream.execute(connection, command, args, debug);
  }

  /// 打开同步流
  static Future<AdbSyncStream> openSync(AdbConnection connection) async {
    return AdbSyncStream.open(connection);
  }

  /// 启动TCP端口转发
  static Future<TcpForwarder> tcpForward(
    AdbConnection connection,
    int hostPort,
    String destination, {
    bool debug = false,
  }) async {
    final forwarder = TcpForwarder(
      connection,
      hostPort,
      destination,
      debug: debug,
    );
    await forwarder.start();
    return forwarder;
  }

  /// 创建配对连接
  static Future<void> pair({
    required String host,
    required int port,
    required String pairingCode,
    String? name,
    AdbKeyPair? keyPair,
  }) async {
    throw UnimplementedError('配对功能尚未实现');
  }

  /// 推送文件到设备
  static Future<void> push(
    AdbConnection connection,
    String localPath,
    String remotePath, {
    int mode = 420,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw FileSystemException('文件不存在', localPath);
    }

    final fileBytes = await file.readAsBytes();
    final fileStream = Stream.value(fileBytes);
    final currentTime = await file.lastModified();

    final syncStream = await openSync(connection);
    await syncStream.send(
      fileStream,
      remotePath,
      mode,
      currentTime.millisecondsSinceEpoch,
    );
  }

  /// 推送文件流到设备
  static Future<void> pushStream(
    AdbConnection connection,
    Stream<List<int>> source,
    String remotePath, {
    int mode = 420,
    int? lastModifiedMs,
  }) async {
    final syncStream = await openSync(connection);
    final currentTime = lastModifiedMs ?? DateTime.now().millisecondsSinceEpoch;
    await syncStream.send(source, remotePath, mode, currentTime);
  }

  /// 从设备拉取文件
  static Future<void> pull(
    AdbConnection connection,
    String remotePath,
    String localPath,
  ) async {
    final file = File(localPath);
    final sink = file.openWrite();

    try {
      final syncStream = await openSync(connection);
      await syncStream.recv(sink, remotePath);
      await sink.close();
    } catch (e) {
      await sink.close();
      rethrow;
    }
  }

  /// 从设备拉取文件到流
  static Future<void> pullStream(
    AdbConnection connection,
    String remotePath,
    StreamSink<List<int>> sink,
  ) async {
    final syncStream = await openSync(connection);
    await syncStream.recv(sink, remotePath);
  }

  /// 安装APK文件
  static Future<void> install(
    AdbConnection connection,
    String apkPath, {
    List<String> options = const [],
  }) async {
    final file = File(apkPath);
    if (!await file.exists()) {
      throw FileSystemException('APK文件不存在', apkPath);
    }

    if (!apkPath.endsWith('.apk')) {
      throw ArgumentError('文件必须是APK格式');
    }

    if (await _supportsFeature(connection, 'cmd')) {
      await _installWithCmd(connection, file, options);
    } else {
      await _installWithPm(connection, file, options);
    }
  }

  /// 使用cmd命令安装APK
  static Future<void> _installWithCmd(
    AdbConnection connection,
    File apkFile,
    List<String> options,
  ) async {
    final fileSize = await apkFile.length();
    final fileBytes = await apkFile.readAsBytes();

    final commandArgs = [
      'package',
      'install',
      '-S',
      fileSize.toString(),
      ...options,
    ];
    final command = commandArgs.join(' ');

    final adbStream = await connection.open('exec:cmd $command');
    await adbStream.sink.writeBytes(fileBytes);
    await adbStream.sink.flush();

    final responseBytes = <int>[];
    await for (final chunk in adbStream.source.stream) {
      responseBytes.addAll(chunk);
    }
    final responseText = String.fromCharCodes(responseBytes);

    if (!responseText.startsWith('Success')) {
      throw Exception('APK安装失败: $responseText');
    }

    await adbStream.close();
  }

  /// 使用pm命令安装APK
  static Future<void> _installWithPm(
    AdbConnection connection,
    File apkFile,
    List<String> options,
  ) async {
    final remotePath = '/data/local/tmp/${apkFile.path.split('/').last}';
    await push(connection, apkFile.path, remotePath);

    final optionsStr = options.join(' ');
    final command = 'pm install $optionsStr "$remotePath"';

    final shellStream = await executeShell(connection, command);
    final result = await shellStream.readAll();

    final exitCode = await shellStream.exitCode.first;
    if (exitCode != 0) {
      throw Exception('APK安装失败: $result');
    }
  }

  /// 安装多个APK文件
  static Future<void> installMultiple(
    AdbConnection connection,
    List<String> apkPaths, {
    List<String> options = const [],
  }) async {
    final files = apkPaths.map((path) => File(path)).toList();

    for (final file in files) {
      if (!await file.exists()) {
        throw FileSystemException('APK文件不存在', file.path);
      }
    }

    final totalSize = files.fold<int>(
      0,
      (sum, file) => sum + file.lengthSync(),
    );
    final sessionCommand =
        'pm install-create -S $totalSize ${options.join(' ')}';
    final shellStream = await executeShell(connection, sessionCommand);
    final sessionResponse = await shellStream.readAll();

    final sessionId = _extractSessionId(sessionResponse);

    try {
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final remotePath = '/data/local/tmp/${file.path.split('/').last}';

        await push(connection, file.path, remotePath);

        final writeCommand =
            'pm install-write -S ${file.lengthSync()} $sessionId $i "$remotePath"';
        final writeStream = await executeShell(connection, writeCommand);
        final writeResult = await writeStream.readAll();

        if (!writeResult.contains('Success')) {
          throw Exception('APK写入失败: $writeResult');
        }
      }

      final commitCommand = 'pm install-commit $sessionId';
      final commitStream = await executeShell(connection, commitCommand);
      final commitResult = await commitStream.readAll();

      if (!commitResult.contains('Success')) {
        throw Exception('APK安装提交失败: $commitResult');
      }
    } catch (e) {
      try {
        final abandonCommand = 'pm install-abandon $sessionId';
        await executeShell(connection, abandonCommand);
      } catch (_) {
        // 忽略放弃会话时的错误
      }
      rethrow;
    }
  }

  /// 卸载应用包
  static Future<void> uninstall(
    AdbConnection connection,
    String packageName,
  ) async {
    final command = 'cmd package uninstall $packageName';
    final shellStream = await executeShell(connection, command);
    await shellStream.readAll();

    final exitCode = await shellStream.exitCode.first;
    if (exitCode != 0) {
      throw Exception('应用卸载失败');
    }
  }

  /// 打开ADB流
  static Future<AdbStream> open(
    AdbConnection connection,
    String destination,
  ) async {
    return connection.open(destination);
  }

  /// 打开Shell流
  static Future<AdbShellStream> openShell(
    AdbConnection connection, [
    String command = '',
  ]) async {
    return AdbShellStream.execute(connection, command, []);
  }

  /// 执行Shell命令并返回完整响应
  static Future<AdbShellResponse> shell(
    AdbConnection connection,
    String command,
  ) async {
    final shellStream = await openShell(connection, command);
    final output = await shellStream.readAll();
    final exitCode = await shellStream.exitCode.first;
    return AdbShellResponse(output, '', exitCode);
  }

  /// 执行cmd命令
  static Future<AdbStream> execCmd(
    AdbConnection connection,
    List<String> command,
  ) async {
    final commandStr = command.join(' ');
    return connection.open('exec:cmd $commandStr');
  }

  /// 执行abb_exec命令
  static Future<AdbStream> abbExec(
    AdbConnection connection,
    List<String> command,
  ) async {
    final commandStr = command.join('\u0000');
    return connection.open('abb_exec:$commandStr');
  }

  /// 获取root权限
  static Future<String> root(AdbConnection connection) async {
    final adbStream = await connection.open('root:');
    final responseBytes = <int>[];
    await for (final chunk in adbStream.source.stream) {
      responseBytes.addAll(chunk);
    }
    await adbStream.close();
    return String.fromCharCodes(responseBytes);
  }

  /// 取消root权限
  static Future<String> unroot(AdbConnection connection) async {
    final adbStream = await connection.open('unroot:');
    final responseBytes = <int>[];
    await for (final chunk in adbStream.source.stream) {
      responseBytes.addAll(chunk);
    }
    await adbStream.close();
    return String.fromCharCodes(responseBytes);
  }

  /// 检查设备是否支持指定特性
  static Future<bool> _supportsFeature(
    AdbConnection connection,
    String feature,
  ) async {
    try {
      final shellStream = await executeShell(connection, 'pm list features');
      final features = await shellStream.readAll();
      return features.contains(feature);
    } catch (e) {
      return false;
    }
  }

  /// 从安装会话响应中提取会话ID
  static String _extractSessionId(String response) {
    final regex = RegExp(r'\[(\w+)\]');
    final match = regex.firstMatch(response);
    if (match != null) {
      return match.group(1)!;
    }
    throw Exception('无法创建安装会话: $response');
  }
}
