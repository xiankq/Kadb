import 'dart:io';
import 'dart:async';
import 'package:kadb_dart/kadb_dart.dart';
import 'package:kadb_dart/exception/adb_stream_closed.dart';

/// 简单的TCP转发测试
void main() async {
  // 设置Zone异常处理器来捕获所有未处理的异常
  runZonedGuarded(
    () async {
      print('🚀 启动简单TCP转发测试...');

      late AdbConnection connection;
      TcpForwarder? forwarder;

      try {
        // 1. 连接设备
        print('正在连接到设备 192.168.2.32:5556...');
        final keyPair = await CertUtils.loadKeyPair();

        connection = await KadbDart.create(
          host: '192.168.2.32',
          port: 5556,
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
          '/data/local/tmp/scrcpy-server-dart.jar',
          mode: 33261,
        );

        // 验证文件是否推送成功
        print('🔍 验证scrcpy-server文件是否推送成功...');
        try {
          final checkResult = await KadbDart.executeShell(connection, 'ls', [
            '-la',
            '/data/local/tmp/scrcpy-server-dart.jar',
          ]);

          await for (final line in checkResult.stdout) {
            if (line.contains('scrcpy-server-dart.jar')) {
              print('✅ scrcpy-server文件验证成功: $line');
            }
          }
        } catch (e) {
          print('❌ scrcpy-server文件验证失败: $e');
          print('🔄 尝试重新推送文件...');

          // 重新推送
          await KadbDart.push(
            connection,
            '../scrcpy/scrcpy-server',
            '/data/local/tmp/scrcpy-server-dart.jar',
            mode: 33261,
          );
          print('✅ scrcpy-server重新推送完成');
        }

        print('✅ scrcpy-server已推送');

        // 3. 启动TCP转发
        print('正在启动TCP转发: 端口 11234 -> localabstract:scrcpy');
        forwarder = TcpForwarder(
          connection,
          11234,
          'localabstract:scrcpy',
          debug: true,
        );
        await forwarder.start();
        print('✅ TCP转发已启动');

        // 4. 启动scrcpy服务器（使用更适合的参数）
        print('正在启动scrcpy服务器...');
        final shellCommand =
            'CLASSPATH=/data/local/tmp/scrcpy-server-dart.jar app_process / com.genymobile.scrcpy.Server 3.3.3 tunnel_forward=true max_size=720';

        final shellStream = await KadbDart.executeShell(connection, 'sh', [
          '-c',
          shellCommand,
        ]);

        print('✅ scrcpy服务器已启动');

        // 监听服务器输出
        shellStream.stdout.listen(
          (data) {
            if (data.contains('INFO:') ||
                data.contains('WARN:') ||
                data.contains('ERROR:')) {
              print('服务器: ${data.trim()}');
            } else if (data.length > 100 &&
                !data.contains(RegExp(r'[a-zA-Z]'))) {
              print('🎥 视频数据 (${data.length} 字节)');
            }
          },
          onError: (error) {
            if (error is AdbStreamClosed) {
              print('⚠️ 服务器输出流已关闭，这可能是正常的');
            } else {
              print('输出错误: $error');
            }
          },
          onDone: () => print('服务器输出结束'),
          cancelOnError: false,
        );

        shellStream.stderr.listen(
          (data) => print('错误: $data'),
          onError: (error) {
            if (error is AdbStreamClosed) {
              print('⚠️ 错误输出流已关闭，这可能是正常的');
            } else {
              print('错误流异常: $error');
            }
          },
          onDone: () => print('错误输出结束'),
          cancelOnError: false,
        );

        // 5. 等待scrcpy服务器完全启动
        print('⏳ 等待scrcpy服务器完全启动...');
        await Future.delayed(Duration(seconds: 3));

        // 7. 保持运行
        print('🔄 服务运行中，按 Ctrl+C 停止...');
        print('💡 现在可以使用 ffplay -v quiet -i tcp://localhost:11234 连接');
        while (true) {
          try {
            await Future.delayed(Duration(seconds: 10));
            print('💡 服务仍在运行中... 端口: 11234');
          } catch (e) {
            if (e is AdbStreamClosed) {
              print('⚠️ ADB流已关闭，这可能是正常的连接断开');
              print('💡 scrcpy服务器可能已完成传输或主动断开连接');
              print('🔄 程序将继续运行，可以尝试重新连接');
              continue; // 继续循环
            } else {
              print('❌ 运行时错误: $e');
              break; // 其他错误则退出循环
            }
          }
        }
      } catch (e) {
        if (e is AdbStreamClosed) {
          print('⚠️ ADB流已关闭，这可能是正常的连接断开');
          print('💡 scrcpy服务器可能已完成传输或主动断开连接');
          print('🔄 程序将继续运行，可以尝试重新连接');
        } else {
          print('❌ 错误: $e');
        }
      } finally {
        print('🛑 正在清理资源...');
        await forwarder?.stop();
        connection.close();
        print('✅ 清理完成');
      }
    },
    (error, stackTrace) {
      if (error is AdbStreamClosed) {
        print('⚠️ ADB流已关闭，这可能是正常的连接断开');
        print('💡 scrcpy服务器可能已完成传输或主动断开连接');
        print('🔄 程序将继续运行，可以尝试重新连接');
      } else {
        print('❌ 未捕获的异常: $error');
        print('📍 堆栈跟踪: $stackTrace');
      }
    },
  );
}
