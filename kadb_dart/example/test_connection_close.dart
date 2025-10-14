import 'dart:async';
import 'package:kadb_dart/kadb_dart.dart';

/// 测试连接关闭功能
Future<void> main() async {
  const String host = '100.123.66.1';
  const int port = 5555;

  print('🔧 测试连接关闭功能');
  print('=' * 40);
  print('目标设备: $host:$port');
  print('');

  try {
    print('📡 1. 连接到设备...');
    final connection = await KadbDart.connect(host: host, port: port);
    print('✅ 连接成功！');
    print('');

    print('📱 2. 获取设备信息...');
    final deviceModel = await executeShellCommandFixed(connection, 'getprop ro.product.model');
    print('设备型号: ${deviceModel.trim()}');
    print('');

    print('🔌 3. 正常关闭连接...');
    connection.close();
    print('✅ 连接已关闭，没有抛出异常');
    print('');

    print('🔌 4. 尝试重复关闭...');
    connection.close();
    print('✅ 重复关闭没有抛出异常');
    print('');

    print('✅ 连接关闭功能测试完成');

  } catch (e) {
    print('❌ 错误: $e');
    print('连接关闭功能仍有问题');
  }
}

/// 修复的Shell命令执行方法
Future<String> executeShellCommandFixed(AdbConnection connection, String command, {Duration? timeout}) async {
  timeout ??= Duration(seconds: 5); // 缩短超时时间
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