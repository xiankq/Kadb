import 'dart:async';
import 'dart:io';
import 'package:kadb_dart/kadb_dart.dart';

/// 简化的端口转发演示
/// 专注于核心功能测试
Future<void> main() async {
  const String host = '100.123.66.1';
  const int port = 5555;

  print('🚀 KadbDart 简化端口转发演示');
  print('=' * 50);
  print('目标设备: $host:$port');
  print('');

  try {
    // 1. 连接到设备
    print('📡 1. 连接到设备...');
    final connection = await KadbDart.connect(host: host, port: port);
    print('✅ 连接成功！');
    print('');

    // 2. 获取设备信息
    print('📱 2. 获取设备信息...');
    final deviceModel = await executeShellCommandFixed(connection, 'getprop ro.product.model');
    print('设备型号: ${deviceModel.trim()}');
    print('');

    // 3. 测试基本端口转发
    print('🔄 3. 测试基本端口转发...');
    await testBasicForwarding(connection);
    print('');

    // 4. 测试端口转发器管理
    print('🔄 4. 测试端口转发器管理...');
    await testForwarderManagement(connection);
    print('');

    // 5. 测试反向转发
    print('🔄 5. 测试反向端口转发...');
    await testReverseForwarding(connection);
    print('');

    // 关闭连接
    connection.close();
    print('✅ 演示完成');

  } catch (e) {
    print('❌ 错误: $e');
  }
}

/// 测试基本端口转发
Future<void> testBasicForwarding(AdbConnection connection) async {
  try {
    // 查找可用端口
    final localPort = await findAvailablePort(9000);
    final targetPort = 80; // HTTP端口

    print('  📝 创建转发: 本地端口 $localPort -> 设备端口 $targetPort');
    final forwarder = KadbDart.createTcpForwarder(connection, localPort, targetPort);

    print('  🔍 初始状态: ${forwarder.state}');
    print('  🔍 运行状态: ${forwarder.isRunning}');

    // 启动转发器
    await forwarder.start();
    print('  ✅ 转发器已启动');
    print('  🔍 当前状态: ${forwarder.state}');
    print('  🔍 运行状态: ${forwarder.isRunning}');

    // 测试连接（简单测试）
    print('  📝 测试连接到转发端口...');
    try {
      final socket = await Socket.connect('localhost', localPort, timeout: Duration(seconds: 3));
      print('  ✅ 成功连接到转发端口 $localPort');
      socket.close();
    } catch (e) {
      print('  ⚠️ 连接测试失败: $e (这可能是正常的，如果设备端口 $targetPort 没有服务)');
    }

    // 保持运行一段时间
    print('  ⏳ 转发器运行2秒...');
    await Future.delayed(Duration(seconds: 2));

    // 停止转发器
    await forwarder.stop();
    print('  🛑 转发器已停止');
    print('  🔍 最终状态: ${forwarder.state}');
    print('  🔍 运行状态: ${forwarder.isRunning}');

    // 清理资源
    forwarder.dispose();

  } catch (e) {
    print('  ❌ 基本转发测试失败: $e');
  }
}

/// 测试端口转发器管理
Future<void> testForwarderManagement(AdbConnection connection) async {
  try {
    print('  📝 测试转发器生命周期管理...');

    final localPort = await findAvailablePort(9100);
    final forwarder = TcpForwarder(connection, localPort, 80);

    // 测试重复启动
    await forwarder.start();
    print('  ✅ 第一次启动成功');

    try {
      await forwarder.start();
      print('  ⚠️ 重复启动成功（不应该发生）');
    } catch (e) {
      print('  ✅ 正确拒绝重复启动: ${e.runtimeType}');
    }

    // 测试状态检查
    print('  🔍 状态检查:');
    print('    state: ${forwarder.state}');
    print('    isRunning: ${forwarder.isRunning}');
    print('    hostPort: ${forwarder.hostPort}');
    print('    targetPort: ${forwarder.targetPort}');

    await Future.delayed(Duration(seconds: 1));

    // 停止转发器
    await forwarder.stop();
    print('  ✅ 转发器已停止');

    // 测试重复停止
    await forwarder.stop();
    print('  ✅ 重复停止处理正常');

    forwarder.dispose();

  } catch (e) {
    print('  ❌ 转发器管理测试失败: $e');
  }
}

/// 测试反向端口转发
Future<void> testReverseForwarding(AdbConnection connection) async {
  try {
    final localPort = await findAvailablePort(9200);
    final devicePort = 8080;

    print('  📝 创建反向转发: 设备端口 $devicePort -> 本地端口 $localPort');
    final reverseForwarder = KadbDart.createReverseTcpForwarder(connection, devicePort, localPort);

    print('  🔍 初始状态: ${reverseForwarder.isRunning}');

    // 启动反向转发器
    await reverseForwarder.start();
    print('  ✅ 反向转发器已启动');
    print('  🔍 运行状态: ${reverseForwarder.isRunning}');

    // 保持运行一段时间
    await Future.delayed(Duration(seconds: 1));

    // 停止反向转发器
    await reverseForwarder.stop();
    print('  🛑 反向转发器已停止');
    print('  🔍 运行状态: ${reverseForwarder.isRunning}');

    reverseForwarder.dispose();

  } catch (e) {
    print('  ❌ 反向转发测试失败: $e');
  }
}

/// 查找可用端口
Future<int> findAvailablePort(int startPort) async {
  for (int port = startPort; port < startPort + 100; port++) {
    try {
      final server = await ServerSocket.bind('localhost', port);
      await server.close();
      return port;
    } catch (e) {
      // 端口被占用，继续寻找
    }
  }
  throw Exception('无法找到可用端口');
}

/// 修复的Shell命令执行方法
Future<String> executeShellCommandFixed(AdbConnection connection, String command, {Duration? timeout}) async {
  timeout ??= Duration(seconds: 10);
  final stream = await KadbDart.executeShell(connection, command);
  final buffer = StringBuffer();
  final completer = Completer<String>();
  bool hasData = false;
  Timer? timeoutTimer;
  bool isDone = false;

  // 设置超时
  timeoutTimer = Timer(timeout!, () {
    if (!completer.isCompleted) {
      completer.completeError(TimeoutException('命令执行超时: $command', timeout));
    }
  });

  // 监听标准输出
  final stdoutSubscription = stream.stdout.listen(
    (data) {
      timeoutTimer?.cancel();
      if (!hasData) {
        hasData = true;
        // 第一次收到数据，清空buffer并写入
        buffer.clear();
        buffer.write(data);
      } else {
        // 追加数据
        buffer.write(data);
      }
    },
    onDone: () {
      if (!isDone) {
        isDone = true;
        timeoutTimer?.cancel();
        if (!completer.isCompleted) {
          String result = buffer.toString();

          // 清理结果：去除重复数据和多余的空格换行
          result = result.trim();
          result = _cleanupDuplicateData(result);

          if (result.isNotEmpty) {
            completer.complete(result);
          } else {
            completer.complete('');
          }
        }
      }
    },
    onError: (error) {
      timeoutTimer?.cancel();
      if (!completer.isCompleted && !isDone) {
        isDone = true;
        if (error.toString().contains('AdbStreamClosed')) {
          if (hasData) {
            String result = buffer.toString();
            result = result.trim();
            result = _cleanupDuplicateData(result);
            completer.complete(result);
          } else {
            completer.complete('');
          }
        } else {
          completer.completeError(error);
        }
      }
    },
    cancelOnError: false,
  );

  // 监听标准错误
  final stderrSubscription = stream.stderr.listen(
    (data) {
      // 记录错误但不影响主要输出
      final errorData = data.trim();
      if (errorData.isNotEmpty && !errorData.contains('[shell] exit')) {
        print('    ⚠️ 标准错误: $errorData');
      }
    },
    onError: (error) {
      // 忽略标准错误中的流关闭和超时
      if (!error.toString().contains('AdbStreamClosed') &&
          !error.toString().contains('TimeoutException')) {
        print('    ⚠️ 错误流错误: $error');
      }
    },
    cancelOnError: false,
  );

  try {
    return await completer.future;
  } finally {
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
    timeoutTimer?.cancel();
    await stream.close();
  }
}

/// 清理重复数据
String _cleanupDuplicateData(String data) {
  if (data.isEmpty) return data;

  // 去除常见的重复模式
  String result = data;

  // 如果数据长度大于10且前半部分和后半部分完全相同，取一半
  if (result.length > 10 && result.length % 2 == 0) {
    int halfLength = result.length ~/ 2;
    String firstHalf = result.substring(0, halfLength);
    String secondHalf = result.substring(halfLength);

    if (firstHalf == secondHalf) {
      result = firstHalf;
    }
  }

  // 去除行首行尾的[shell]标记
  result = result.replaceAll(RegExp(r'\[shell\]'), '').trim();

  // 去除exit(0)行
  result = result.replaceAll(RegExp(r'exit\(0\)', caseSensitive: false), '').trim();

  return result;
}