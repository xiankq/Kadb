import 'dart:io';
import 'package:kadb_dart/kadb_dart.dart';
import 'package:kadb_dart/debug/logging.dart';

void main() async {
  // 设置调试级别：false=仅关键信息，true=标准调试，verbose=true=详细调试
  const bool debugMode = false;
  const bool verboseMode = false;
  
  // 初始化日志系统
  Logging.setDebug(debugMode);
  Logging.setVerbose(verboseMode);

  Logging.status('启动scrcpy服务器...');

  late AdbConnection connection;
  TcpForwarder? forwarder;

  try {
    // 1. 连接设备
    print('正在连接到设备 192.168.2.32:5556...');
    final keyPair = await CertUtils.loadKeyPair();

    connection = await KadbDart.create(
      host: '192.168.2.148',
      port: 5555,
      keyPair: keyPair,
      debug: false,
      ioTimeoutMs: 30000,
      connectTimeoutMs: 15000,
    );

    print('✅ 设备连接成功！');

    // 2. 推送scrcpy-server
    print('正在推送scrcpy-server到设备...');
    await KadbDart.push(
      connection,
      '../scrcpy/scrcpy-server',
      '/data/local/tmp/scrcpy-server.jar',
      mode: 33261,
    );
    print('✅ scrcpy-server已推送');

    // 3. 启动TCP转发
    print('正在启动TCP转发: 端口 11238 -> localabstract:scrcpy');
    forwarder = TcpForwarder(
      connection,
      11238,
      'localabstract:scrcpy',
      debug: false, // 关闭调试输出以提升性能
    );
    await forwarder.start();
    print('✅ TCP转发已启动');

    // 4. 启动scrcpy服务器
    print('正在启动scrcpy服务器...');
    final shellCommand =
        'CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server 3.3.3 tunnel_forward=true audio=false control=false cleanup=false raw_stream=true max_size=720';

    final shellStream = await KadbDart.executeShell(connection, 'sh', [
      '-c',
      shellCommand,
    ]);

    print('✅ scrcpy服务器已启动');

    // 5. 等待服务器启动
    print('⏳ 等待scrcpy服务器完全启动...');
    await Future.delayed(Duration(seconds: 5));

    // 6. 显示使用说明
    print('\n🎉 scrcpy服务器启动完成！');
    print('📺 使用以下命令连接视频流:');
    print('   ffplay -v quiet -i tcp://localhost:11238');
    print('   或');
    print('   vlc tcp://localhost:11238');
    print('\n💡 提示：视频流可能需要几秒钟才能稳定\n');

    // 7. 保持运行（最简单的循环，完全避免创建新的流）
    print('🔄 服务器运行中，按 Ctrl+C 停止...');

    // 使用最简单的方式保持运行
    while (true) {
      try {
        await Future.delayed(Duration(seconds: 60));
        print('💡 服务器运行中... 端口: 11238');
      } catch (e) {
        print('⚠️ 运行时警告: $e');
        // 继续运行，不退出
      }
    }
  } catch (e) {
    print('❌ 错误: $e');
  } finally {
    print('🛑 正在清理资源...');
    try {
      await forwarder?.stop();
    } catch (e) {
      print('⚠️ 停止转发器时出错: $e');
    }

    try {
      connection.close();
    } catch (e) {
      print('⚠️ 关闭连接时出错: $e');
    }
    print('✅ 清理完成');
  }
}
