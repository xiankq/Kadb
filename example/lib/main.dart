import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'connection_provider.dart';
import 'stream_provider.dart';
import 'views/connection_screen.dart';

void main() async {
  try {
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) {
              debugPrint('创建 ConnectionProvider');
              return ConnectionProvider();
            },
          ),
          ChangeNotifierProvider(
            create: (_) {
              debugPrint('创建 VideoStreamProvider');
              return VideoStreamProvider();
            },
          ),
        ],
        child: const ScrcpyApp(),
      ),
    );
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
