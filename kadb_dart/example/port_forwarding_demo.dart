import 'dart:async';
import 'package:kadb_dart/kadb_dart.dart';

/// 端口转发演示
/// 展示如何使用KadbDart进行TCP端口转发
Future<void> main() async {
  const String host = '100.123.66.1';
  const int port = 5555;

  print('🚀 KadbDart 端口转发演示');
  print('=' * 50);
  print('目标设备: $host:$port');
  print('');

  try {
    final keyPair = await CertUtils.loadKeyPair();

    // 1. 连接到设备
    print('📡 1. 连接到设备...');
    final connection = await KadbDart.connect(
      host: host,
      port: port,
      keyPair: keyPair,
    );
    print('✅ 连接成功！');
    print('');

    // 2. 获取设备信息
    print('📱 2. 获取设备信息...');
    final deviceModel = await executeShellCommandFixed(
      connection,
      'getprop ro.product.model',
    );
    print('设备型号: ${deviceModel.trim()}');
    print('');

    // 3. 测试TCP转发
    print('🔄 3. 测试TCP端口转发...');
    await testTcpForwarding(connection);
    print('');

    // 4. 测试反向TCP转发
    print('🔄 4. 测试反向TCP端口转发...');
    await testReverseTcpForwarding(connection);
    print('');

    // 5. 演示端口转发器的状态管理
    print('🔄 5. 演示端口转发器状态管理...');
    await demonstrateStateManagement(connection);
    print('');

    // 关闭连接
    connection.close();
    print('✅ 演示完成');
  } catch (e) {
    print('❌ 错误: $e');
  }
}

/// 修复的Shell命令执行方法
Future<String> executeShellCommandFixed(
  AdbConnection connection,
  String command, {
  Duration? timeout,
}) async {
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
  result = result
      .replaceAll(RegExp(r'exit\(0\)', caseSensitive: false), '')
      .trim();

  return result;
}

/// 测试TCP端口转发
Future<void> testTcpForwarding(AdbConnection connection) async {
  try {
    // 创建转发器：本地端口 8080 -> 设备端口 80
    final forwarder = KadbDart.createTcpForwarder(connection, 8080, 80);

    print('  📝 创建TCP转发器: 本地端口 8080 -> 设备端口 80');
    print('  🔍 当前状态: ${forwarder.state}');

    // 启动转发器
    await forwarder.start();
    print('  ✅ TCP转发器已启动');
    print('  🔍 运行状态: ${forwarder.isRunning}');

    // 等待一段时间
    await Future.delayed(Duration(seconds: 2));

    // 停止转发器
    await forwarder.stop();
    print('  🛑 TCP转发器已停止');
    print('  🔍 运行状态: ${forwarder.isRunning}');

    // 清理资源
    forwarder.dispose();
  } catch (e) {
    print('  ❌ TCP转发测试失败: $e');
  }
}

/// 测试反向TCP端口转发
Future<void> testReverseTcpForwarding(AdbConnection connection) async {
  try {
    // 创建反向转发器：设备端口 8080 -> 本地端口 9080
    final reverseForwarder = KadbDart.createReverseTcpForwarder(
      connection,
      8080,
      9080,
    );

    print('  📝 创建反向TCP转发器: 设备端口 8080 -> 本地端口 9080');
    print('  🔍 当前状态: ${reverseForwarder.isRunning}');

    // 启动反向转发器
    await reverseForwarder.start();
    print('  ✅ 反向TCP转发器已启动');
    print('  🔍 运行状态: ${reverseForwarder.isRunning}');

    // 等待一段时间
    await Future.delayed(Duration(seconds: 2));

    // 停止反向转发器
    await reverseForwarder.stop();
    print('  🛑 反向TCP转发器已停止');
    print('  🔍 运行状态: ${reverseForwarder.isRunning}');

    // 清理资源
    reverseForwarder.dispose();
  } catch (e) {
    print('  ❌ 反向TCP转发测试失败: $e');
  }
}

/// 演示端口转发器的状态管理
Future<void> demonstrateStateManagement(AdbConnection connection) async {
  try {
    // 使用便捷方法启动转发器
    print('  📝 使用便捷方法启动转发器...');
    final forwarder = await KadbDart.startTcpForward(connection, 8081, 81);

    print('  ✅ 转发器已自动启动');
    print('  🔍 本地端口: ${forwarder.hostPort}');
    print('  🔍 目标端口: ${forwarder.targetPort}');
    print('  🔍 当前状态: ${forwarder.state}');

    // 演示重复启动的错误处理
    print('  📝 测试重复启动...');
    try {
      await forwarder.start();
      print('  ⚠️ 重复启动成功（这不应该发生）');
    } catch (e) {
      print('  ✅ 正确处理重复启动错误: ${e.runtimeType}');
    }

    // 演示状态转换
    print('  📝 监控状态变化...');
    for (int i = 0; i < 3; i++) {
      await Future.delayed(Duration(milliseconds: 500));
      print(
        '    ${i + 1}. 状态: ${forwarder.state}, 运行中: ${forwarder.isRunning}',
      );
    }

    // 停止转发器
    await forwarder.stop();
    print('  ✅ 转发器已停止');

    // 演示重复停止的处理
    print('  📝 测试重复停止...');
    await forwarder.stop();
    print('  ✅ 重复停止处理正常');

    // 清理资源
    forwarder.dispose();
  } catch (e) {
    print('  ❌ 状态管理演示失败: $e');
  }
}
