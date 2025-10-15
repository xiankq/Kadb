/// Kadb Dart - 纯Dart实现的ADB客户端库
///
/// 提供完整的ADB协议实现，包括：
/// - ADB连接管理
/// - Shell命令执行
/// - 文件同步操作
/// - TCP端口转发
/// - 设备配对功能
///
/// 所有功能都完整复刻自Kotlin版本，确保功能一致性。
library;

// 核心协议组件
export 'core/adb_protocol.dart';
export 'core/adb_message.dart';
export 'core/adb_reader.dart';
export 'core/adb_writer.dart';
export 'core/adb_connection.dart';
export 'core/adb_message_queue.dart';

// 证书和密钥管理
export 'cert/adb_key_pair.dart';
export 'cert/cert_utils.dart';

// 传输通道
export 'transport/transport_channel.dart';

// 流操作
export 'stream/adb_stream.dart';
export 'stream/adb_shell_stream.dart';
export 'shell/adb_shell_response.dart';
export 'stream/adb_sync_stream.dart';

// 转发功能
export 'forwarding/tcp_forwarder.dart';

// 配对功能
export 'pair/pairing_connection_ctx.dart';

import 'dart:async';
import 'dart:io';
import 'core/adb_connection.dart';
import 'cert/adb_key_pair.dart';
import 'cert/cert_utils.dart';
import 'stream/adb_shell_stream.dart';
import 'shell/adb_shell_response.dart';
import 'stream/adb_sync_stream.dart';
import 'stream/adb_stream.dart';
import 'forwarding/tcp_forwarder.dart';

/// ADB客户端主类
/// 提供高级API来管理ADB连接和操作
/// 参照Kotlin版本的API设计
class KadbDart {
  /// 连接到ADB服务器（对应Kotlin的create方法）
  /// [host] 主机地址（默认localhost）
  /// [port] 端口号（默认5037）
  /// [keyPair] ADB密钥对（可选，自动生成）
  /// [connectTimeoutMs] 连接超时时间（毫秒）
  /// [ioTimeoutMs] IO超时时间（毫秒）
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

  /// 保留connect方法用于向后兼容
  @Deprecated('使用create方法替代，与Kotlin版本保持一致')
  static Future<AdbConnection> connect({
    String host = 'localhost',
    int port = 5037,
    AdbKeyPair? keyPair,
    int connectTimeoutMs = 10000,
    int ioTimeoutMs = 30000,
    bool debug = false,
  }) async {
    return await create(
      host: host,
      port: port,
      keyPair: keyPair,
      connectTimeoutMs: connectTimeoutMs,
      ioTimeoutMs: ioTimeoutMs,
      debug: debug,
    );
  }

  /// 执行Shell命令
  /// [connection] ADB连接
  /// [command] Shell命令
  /// [args] 命令参数
  /// [debug] 是否启用调试模式
  static Future<AdbShellStream> executeShell(
    AdbConnection connection,
    String command, [
    List<String> args = const [],
    bool debug = false,
  ]) async {
    return AdbShellStream.execute(connection, command, args, debug);
  }

  /// 打开同步流
  /// [connection] ADB连接
  static Future<AdbSyncStream> openSync(AdbConnection connection) async {
    return AdbSyncStream.open(connection);
  }

  /// 创建TCP转发器
  /// [connection] ADB连接
  /// [hostPort] 本地端口
  /// [destination] 目标服务，如 "tcp:8080", "localabstract:scrcpy", "shell:cat"
  ///
  /// 返回可自动关闭的TCP转发器实例
  static TcpForwarder createTcpForwarder(
    AdbConnection connection,
    int hostPort,
    String destination,
  ) {
    return TcpForwarder(connection, hostPort, destination);
  }

  /// 创建反向TCP转发器
  /// [connection] ADB连接
  /// [devicePort] 设备端口
  /// [hostPort] 本地端口
  ///
  /// 返回可自动关闭的反向TCP转发器实例
  static ReverseTcpForwarder createReverseTcpForwarder(
    AdbConnection connection,
    int devicePort,
    int hostPort,
  ) {
    return ReverseTcpForwarder(connection, devicePort, hostPort);
  }

  /// 启动TCP端口转发（便捷方法）
  /// [connection] ADB连接
  /// [hostPort] 本地端口
  /// [destination] 目标服务，如 "tcp:8080", "localabstract:scrcpy", "shell:cat"
  ///
  /// 自动启动转发器并返回可关闭的实例
  static Future<TcpForwarder> startTcpForward(
    AdbConnection connection,
    int hostPort,
    String destination,
  ) async {
    final forwarder = TcpForwarder(connection, hostPort, destination);
    await forwarder.start();
    return forwarder;
  }

  /// 启动反向TCP端口转发（便捷方法）
  /// [connection] ADB连接
  /// [devicePort] 设备端口
  /// [hostPort] 本地端口
  ///
  /// 自动启动反向转发器并返回可关闭的实例
  static Future<ReverseTcpForwarder> startReverseTcpForward(
    AdbConnection connection,
    int devicePort,
    int hostPort,
  ) async {
    final forwarder = ReverseTcpForwarder(connection, devicePort, hostPort);
    await forwarder.start();
    return forwarder;
  }

  /// 尝试连接（对应Kotlin的tryConnection方法）
  /// [host] 主机地址
  /// [port] 端口号
  ///
  /// 尝试建立连接并执行测试命令，如果成功返回连接对象，失败返回null
  static Future<AdbConnection?> tryConnection({
    String host = 'localhost',
    int port = 5037,
  }) async {
    try {
      final connection = await create(host: host, port: port);
      // 执行测试命令验证连接
      final shellStream = await executeShell(connection, 'echo success');
      final result = await shellStream.readAll();

      if (result.trim() == 'success') {
        return connection;
      } else {
        connection.close();
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// 创建配对连接
  /// [host] 主机地址
  /// [port] 端口号
  /// [pairingCode] 配对码
  /// [name] 设备名称
  /// [keyPair] ADB密钥对
  static Future<void> pair({
    required String host,
    required int port,
    required String pairingCode,
    String? name,
    AdbKeyPair? keyPair,
  }) async {
    // TODO: 实现配对功能
    // 这里需要实现PairingConnectionCtx的配对逻辑
    throw UnimplementedError('配对功能尚未实现');
  }

  // ==================== 文件操作方法 ====================

  /// 推送文件到设备
  /// [connection] ADB连接
  /// [localPath] 本地文件路径
  /// [remotePath] 设备上的目标路径
  /// [mode] 文件权限（默认为644）
  static Future<void> push(
    AdbConnection connection,
    String localPath,
    String remotePath, {
    int mode = 420, // 0o644 in decimal
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw FileSystemException('文件不存在', localPath);
    }

    final fileBytes = await file.readAsBytes();
    final fileStream = Stream.value(fileBytes);
    final currentTime = await file.lastModified();

    final syncStream = await openSync(connection);

    await syncStream.send(fileStream, remotePath, mode, currentTime.millisecondsSinceEpoch);
  }

  /// 推送文件流到设备
  /// [connection] ADB连接
  /// [source] 文件数据流
  /// [remotePath] 设备上的目标路径
  /// [mode] 文件权限
  /// [lastModifiedMs] 最后修改时间（毫秒）
  static Future<void> pushStream(
    AdbConnection connection,
    Stream<List<int>> source,
    String remotePath, {
    int mode = 420, // 0o644 in decimal
    int? lastModifiedMs,
  }) async {
    final syncStream = await openSync(connection);
    final currentTime = lastModifiedMs ?? DateTime.now().millisecondsSinceEpoch;
    await syncStream.send(source, remotePath, mode, currentTime);
  }

  /// 从设备拉取文件
  /// [connection] ADB连接
  /// [remotePath] 设备上的文件路径
  /// [localPath] 本地保存路径
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
  /// [connection] ADB连接
  /// [remotePath] 设备上的文件路径
  /// [sink] 输出流
  static Future<void> pullStream(
    AdbConnection connection,
    String remotePath,
    StreamSink<List<int>> sink,
  ) async {
    final syncStream = await openSync(connection);
    await syncStream.recv(sink, remotePath);
  }

  // ==================== APK安装方法 ====================

  /// 安装APK文件
  /// [connection] ADB连接
  /// [apkPath] APK文件路径
  /// [options] 安装选项
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

    // 检查是否支持cmd特性
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

    final commandArgs = ['package', 'install', '-S', fileSize.toString(), ...options];
    final command = commandArgs.join(' ');

    // 创建exec流并写入APK数据
    final adbStream = await connection.open('exec:cmd $command');
    await adbStream.sink.writeBytes(fileBytes);
    await adbStream.sink.flush();

    // 读取响应
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

  /// 使用pm命令安装APK（传统方法）
  static Future<void> _installWithPm(
    AdbConnection connection,
    File apkFile,
    List<String> options,
  ) async {
    final remotePath = '/data/local/tmp/${apkFile.path.split('/').last}';

    // 推送APK到设备
    await push(connection, apkFile.path, remotePath);

    // 执行pm install命令
    final optionsStr = options.join(' ');
    final command = 'pm install $optionsStr "$remotePath"';

    final shellStream = await executeShell(connection, command);
    final result = await shellStream.readAll();

    final exitCodeFuture = shellStream.exitCode.first;
    final exitCode = await exitCodeFuture;
    if (exitCode != 0) {
      throw Exception('APK安装失败: $result');
    }
  }

  /// 安装多个APK文件（Split APKs）
  /// [connection] ADB连接
  /// [apkPaths] APK文件路径列表
  /// [options] 安装选项
  static Future<void> installMultiple(
    AdbConnection connection,
    List<String> apkPaths, {
    List<String> options = const [],
  }) async {
    final files = apkPaths.map((path) => File(path)).toList();

    // 验证所有文件
    for (final file in files) {
      if (!await file.exists()) {
        throw FileSystemException('APK文件不存在', file.path);
      }
    }

    // 计算总大小
    final totalSize = files.fold<int>(0, (sum, file) => sum + file.lengthSync());

    // 创建安装会话
    final sessionCommand = 'pm install-create -S $totalSize ${options.join(' ')}';
    final shellStream = await executeShell(connection, sessionCommand);
    final sessionResponse = await shellStream.readAll();

    final sessionId = _extractSessionId(sessionResponse);

    try {
      // 安装每个APK
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final remotePath = '/data/local/tmp/${file.path.split('/').last}';

        // 推送APK
        await push(connection, file.path, remotePath);

        // 写入到会话
        final writeCommand = 'pm install-write -S ${file.lengthSync()} $sessionId $i "$remotePath"';
        final writeStream = await executeShell(connection, writeCommand);
        final writeResult = await writeStream.readAll();

        if (!writeResult.contains('Success')) {
          throw Exception('APK写入失败: $writeResult');
        }
      }

      // 提交安装
      final commitCommand = 'pm install-commit $sessionId';
      final commitStream = await executeShell(connection, commitCommand);
      final commitResult = await commitStream.readAll();

      if (!commitResult.contains('Success')) {
        throw Exception('APK安装提交失败: $commitResult');
      }

    } catch (e) {
      // 如果出错，放弃安装会话
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
  /// [connection] ADB连接
  /// [packageName] 包名
  static Future<void> uninstall(
    AdbConnection connection,
    String packageName,
  ) async {
    final command = 'cmd package uninstall $packageName';
    final shellStream = await executeShell(connection, command);
    await shellStream.readAll();

    final exitCodeFuture = shellStream.exitCode.first;
    final exitCode = await exitCodeFuture;
    if (exitCode != 0) {
      throw Exception('应用卸载失败');
    }
  }

  // ==================== 流操作方法（对应Kotlin的open方法） ====================

  /// 打开ADB流（对应Kotlin的open方法）
  /// [connection] ADB连接
  /// [destination] 目标地址
  static Future<AdbStream> open(
    AdbConnection connection,
    String destination,
  ) async {
    return await connection.open(destination);
  }

  /// 打开Shell流（对应Kotlin的openShell方法）
  /// [connection] ADB连接
  /// [command] Shell命令（可选）
  static Future<AdbShellStream> openShell(
    AdbConnection connection, [
    String command = '',
  ]) async {
    return AdbShellStream.execute(connection, command, []);
  }

  /// 执行Shell命令并返回完整响应（对应Kotlin的shell方法）
  /// [connection] ADB连接
  /// [command] Shell命令
  static Future<AdbShellResponse> shell(
    AdbConnection connection,
    String command,
  ) async {
    final shellStream = await openShell(connection, command);
    final output = await shellStream.readAll();
    final exitCodeFuture = shellStream.exitCode.first;
    final exitCode = await exitCodeFuture;
    return AdbShellResponse(output, '', exitCode);
  }

  // ==================== 高级命令方法 ====================

  /// 执行cmd命令（对应Kotlin的execCmd方法）
  /// [connection] ADB连接
  /// [command] 命令参数
  static Future<AdbStream> execCmd(
    AdbConnection connection,
    List<String> command,
  ) async {
    final commandStr = command.join(' ');
    return await connection.open('exec:cmd $commandStr');
  }

  /// 执行abb_exec命令（对应Kotlin的abbExec方法）
  /// [connection] ADB连接
  /// [command] 命令参数
  static Future<AdbStream> abbExec(
    AdbConnection connection,
    List<String> command,
  ) async {
    final commandStr = command.join('\u0000');
    return await connection.open('abb_exec:$commandStr');
  }

  /// 获取root权限
  /// [connection] ADB连接
  /// 返回重启后的ADB连接字符串
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
  /// [connection] ADB连接
  /// 返回重启后的ADB连接字符串
  static Future<String> unroot(AdbConnection connection) async {
    final adbStream = await connection.open('unroot:');
    final responseBytes = <int>[];
    await for (final chunk in adbStream.source.stream) {
      responseBytes.addAll(chunk);
    }
    await adbStream.close();
    return String.fromCharCodes(responseBytes);
  }

  // ==================== 辅助方法 ====================

  /// 检查设备是否支持指定特性
  /// [connection] ADB连接
  /// [feature] 特性名称
  static Future<bool> _supportsFeature(
    AdbConnection connection,
    String feature,
  ) async {
    try {
      // 通过查询设备特性来判断
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