import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fvp/fvp.dart';
import 'connection_provider.dart';
import 'stream_provider.dart';
import 'views/connection_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 注册 FVP 插件 - 用于 TCP 流播放
  registerWith(options: {
    'platforms': ['windows', 'macos', 'linux', 'android', 'ios'],
    'video.decoders': ['FFmpeg'], // 使用 FFmpeg 解码器处理 TCP 流
    'lowLatency': 1, // 低延迟模式，适合网络流
  });

  // 添加全局错误处理
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('=== Flutter Error ===');
    debugPrint('Exception: ${details.exception}');
    debugPrint('Stack trace: ${details.stack}');
    debugPrint('====================');
  };

  
  try {
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) {
            debugPrint('创建 ConnectionProvider');
            return ConnectionProvider();
          }),
          ChangeNotifierProvider(create: (_) {
            debugPrint('创建 VideoStreamProvider');
            return VideoStreamProvider();
          }),
        ],
        child: const ScrcpyApp(),
      ),
    );
    debugPrint('应用启动成功 - FVP 插件已注册');
  } catch (e, stackTrace) {
    debugPrint('应用启动失败: $e');
    debugPrint('Stack trace: $stackTrace');
  }
}

class ScrcpyApp extends StatelessWidget {
  const ScrcpyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Scrcpy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ConnectionScreen(),
    );
  }
}