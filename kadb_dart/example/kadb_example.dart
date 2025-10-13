import 'dart:async';

import 'package:kadb_dart/kadb_dart.dart';

/// Kadb Dart 示例代码
/// 展示如何使用Dart ADB库进行各种操作
void main() async {
  print('=== Kadb Dart 示例程序 ===');
  
  try {
    // 示例1: 连接到ADB服务器
    await _exampleConnect();
    
    // 示例2: 执行Shell命令
    await _exampleShell();
    
    // 示例3: 文件同步操作
    await _exampleSync();
    
    // 示例4: TCP端口转发
    await _exampleTcpForwarding();
    
    print('所有示例执行完成！');
  } catch (e) {
    print('示例执行出错: $e');
  }
}

/// 示例1: 连接到ADB服务器
Future<void> _exampleConnect() async {
  print('\n--- 示例1: 连接到ADB服务器 ---');
  
  try {
    final connection = await KadbDart.connect(
      host: 'localhost',
      port: 5037,
      connectTimeoutMs: 5000,
    );
    
    print('✅ ADB连接建立成功');
    print('支持的功能: ${connection.supportsFeature('shell_v2') ? 'shell_v2' : '基础功能'}');
    
    // 关闭连接
    connection.close();
    print('✅ 连接已关闭');
  } catch (e) {
    print('❌ 连接失败: $e');
  }
}

/// 示例2: 执行Shell命令
Future<void> _exampleShell() async {
  print('\n--- 示例2: 执行Shell命令 ---');
  
  try {
    final connection = await KadbDart.connect();
    
    // 执行Shell命令
    final shellStream = await KadbDart.executeShell(connection, 'echo', ['Hello, ADB!']);
    
    // 监听标准输出
    shellStream.stdout.listen((data) {
      print('Shell输出: $data');
    });
    
    // 监听标准错误
    shellStream.stderr.listen((data) {
      print('Shell错误: $data');
    });
    
    // 监听退出码
    shellStream.exitCode.listen((code) {
      print('Shell退出码: $code');
    });
    
    // 等待命令执行完成
    await Future.delayed(Duration(seconds: 2));
    
    // 关闭Shell流
    await shellStream.close();
    
    // 关闭连接
    connection.close();
    print('✅ Shell命令示例完成');
  } catch (e) {
    print('❌ Shell命令执行失败: $e');
  }
}

/// 示例3: 文件同步操作
Future<void> _exampleSync() async {
  print('\n--- 示例3: 文件同步操作 ---');
  
  try {
    final connection = await KadbDart.connect();
    final syncStream = await KadbDart.openSync(connection);
    
    // 列出根目录文件
    print('正在列出根目录文件...');
    final files = await syncStream.list('/');
    
    if (files.isNotEmpty) {
      print('根目录文件列表:');
      for (final file in files.take(5)) { // 只显示前5个文件
        print('  ${file.name} (${file.size} bytes)');
      }
      if (files.length > 5) {
        print('  ... 还有 ${files.length - 5} 个文件');
      }
    } else {
      print('根目录为空');
    }
    
    // 关闭同步流
    await syncStream.close();
    
    // 关闭连接
    connection.close();
    print('✅ 文件同步示例完成');
  } catch (e) {
    print('❌ 文件同步操作失败: $e');
  }
}

/// 示例4: TCP端口转发
Future<void> _exampleTcpForwarding() async {
  print('\n--- 示例4: TCP端口转发 ---');
  
  try {
    final connection = await KadbDart.connect();
    final localPort = 8080;
    final remotePort = 8080;
    
    final forwarder = KadbDart.createTcpForwarder(connection, localPort, remotePort);
    
    print('正在建立端口转发: localhost:$localPort -> 设备端口$remotePort');
    
    await forwarder.start();
    
    print('✅ 端口转发建立成功');
    print('转发状态: ${forwarder.isRunning ? "运行中" : "已停止"}');
    
    // 等待一段时间让用户测试
    print('端口转发已建立，等待5秒...');
    await Future.delayed(Duration(seconds: 5));
    
    // 停止转发器
    await forwarder.stop();
    
    // 关闭连接
    connection.close();
    print('✅ TCP端口转发示例完成');
  } catch (e) {
    print('❌ TCP端口转发失败: $e');
  }
}

/// 高级示例: 完整的ADB会话
Future<void> _advancedExample() async {
  print('\n--- 高级示例: 完整的ADB会话 ---');
  
  final connection = await KadbDart.connect();
  
  try {
    // 1. 检查设备状态
    final shell = await KadbDart.executeShell(connection, 'getprop', ['ro.build.version.sdk']);
    
    final sdkVersion = await shell.stdout.first;
    print('设备SDK版本: $sdkVersion');
    
    await shell.close();
    
    // 2. 文件操作
    final sync = await KadbDart.openSync(connection);
    
    // 检查系统属性文件
    final buildProp = await sync.stat('/system/build.prop');
    print('build.prop 文件大小: ${buildProp.size} bytes');
    
    await sync.close();
    
    // 3. 网络测试
    final forwarder = KadbDart.createTcpForwarder(connection, 9090, 9090);
    
    // 建立临时端口转发进行网络测试
    await forwarder.start();
    
    print('网络测试端口转发已建立');
    
    // 取消转发
    await forwarder.stop();
    await forwarder.dispose();
    
    print('✅ 高级示例完成');
  } finally {
    connection.close();
  }
}