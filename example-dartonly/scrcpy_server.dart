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

  AdbConnection? connection;
  TcpForwarder? forwarder;

  try {
    // 1. 连接设备
    print('正在连接到设备 192.168.2.32:5555...');
    final keyPair = await CertUtils.loadKeyPair();

    connection = await KadbDart.create(
      host: '192.168.2.32',
      port: 5557,
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
      'assets/scrcpy-server',
      '/data/local/tmp/scrcpy-server.jar',
      mode: 33261, // 0o100645 in decimal
    );
    print('✅ scrcpy-server已推送');

    // 3. 启动TCP转发
    print('正在启动TCP转发: 端口 1234 -> localabstract:scrcpy');
    forwarder = TcpForwarder(
      connection,
      1234,
      'localabstract:scrcpy',
      debug: false, // 关闭调试输出以提升性能
    );
    await forwarder.start();
    print('✅ TCP转发已启动');

    // 4. 启动scrcpy服务器
    print('正在启动scrcpy服务器...');
    final shellCommand =
        'CLASSPATH=/data/local/tmp/scrcpy-server.jar '
        'app_process / com.genymobile.scrcpy.Server 3.3.3 '
        'tunnel_forward=true audio=false control=false cleanup=false raw_stream=true max_size=720';

    final shellStream = await KadbDart.executeShell(
      connection,
      'sh',
      args: ['-c', shellCommand],
    );

    print('✅ scrcpy服务器已启动');

    // 5. 等待服务器启动
    print('⏳ 等待scrcpy服务器完全启动...');
    await Future.delayed(Duration(seconds: 5));

    // 保持shell流的引用，因为scrcpy服务器需要它保持运行
    // 不要关闭shellStream，因为这会终止scrcpy服务器
    print('💡 shell流保持打开以维持scrcpy服务器运行');

    // 监听shell流输出，提供更好的调试信息
    shellStream.stdout.listen((output) {
      if (output.contains('ERROR') || output.contains('error')) {
        print('🔴 scrcpy服务器错误: $output');
      } else if (output.contains('INFO') || output.contains('info')) {
        print('ℹ️ scrcpy服务器信息: $output');
      } else if (output.trim().isNotEmpty) {
        print('📝 scrcpy服务器输出: $output');
      }
    });

    // 6. 显示使用说明
    print('\n🎉 scrcpy服务器启动完成！');
    print('📺 使用以下命令连接视频流:');
    print('   ffplay -v quiet -i tcp://localhost:1234');
    print('   或');
    print('   vlc tcp://localhost:1234');
    print('\n💡 重要提示：');
    print('   • 视频流可能需要几秒钟才能稳定');
    print('   • scrcpy-server是单实例服务，一次只能处理一个连接');
    print('   • 关闭播放器后，需要等待几秒钟才能重新连接');
    print('   • 如果连接失败，请等待5-10秒后重试\n');

    // 7. 保持运行（最简单的循环，完全避免创建新的流）
    print('🔄 服务器运行中，按 Ctrl+C 停止...');

    // 使用最简单的方式保持运行
    while (true) {
      try {
        await Future.delayed(Duration(seconds: 60));
        print('💡 服务器运行中... 端口: 1234');
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
      if (connection != null && !connection.isClosed) {
        connection.close();
      }
    } catch (e) {
      print('⚠️ 关闭连接时出错: $e');
    }
    print('✅ 清理完成');
  }
}
