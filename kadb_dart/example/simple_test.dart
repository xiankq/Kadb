import 'dart:async';
import 'package:kadb_dart/kadb_dart.dart';

/// 简单测试
/// 最基本的连接测试
void main() async {
  print('=== 简单ADB连接测试 ===');

  try {
    // 直接使用默认配置连接
    final connection = await KadbDart.connect(
      host: '192.168.2.94',
      port: 5555,
      debug: true,
    );

    print('✅ 连接成功！');

    // 简单测试
    final shellStream = await KadbDart.executeShell(connection, 'echo', ['test']);

    shellStream.stdout.listen((data) {
      print('收到: $data');
    });

    await for (final _ in shellStream.stdout) {
      break;
    }

    await shellStream.close();
    connection.close();
    print('✅ 测试完成');

  } catch (e) {
    print('❌ 失败: $e');
  }
}