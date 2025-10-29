/// 纯Dart实现ADB协议库的基本使用示例
///
/// 这个示例展示了如何使用adb_dart库进行基本的ADB操作
import 'dart:io';
import 'package:adb_dart/adb_dart.dart';

void main() async {
  try {
    print('=== ADB Dart 基本使用示例 ===');

    // 创建ADB客户端实例
    final adb = Kadb('localhost', 5555);

    // 检查连接状态
    print('正在连接ADB服务器...');
    if (!adb.connectionCheck()) {
      print('连接失败，请确保ADB服务器正在运行');
      return;
    }
    print('连接成功!');

    // 执行shell命令
    print('\n--- 执行shell命令 ---');
    final shellResponse = await adb.shell('echo "Hello from Dart ADB!"');
    print('输出: ${shellResponse.output.trim()}');
    print('错误: ${shellResponse.errorOutput}');
    print('退出码: ${shellResponse.exitCode}');

    // 检查设备信息
    print('\n--- 设备信息 ---');
    final deviceInfo = await adb.shell('getprop ro.product.model');
    print('设备型号: ${deviceInfo.output.trim()}');

    // 文件操作示例
    print('\n--- 文件操作 ---');

    // 创建临时文件用于测试
    final tempFile = File('test_adb.txt');
    await tempFile.writeAsString('这是来自Dart ADB的测试文件');

    print('推送文件到设备...');
    await adb.push(tempFile, '/data/local/tmp/test_adb.txt');
    print('文件推送成功');

    // 验证文件是否存在
    final checkFile = await adb.shell('ls /data/local/tmp/test_adb.txt');
    if (checkFile.exitCode == 0) {
      print('文件已成功推送到设备');

      // 拉取文件
      print('从设备拉取文件...');
      final downloadedFile = File('downloaded_test.txt');
      await adb.pull(downloadedFile, '/data/local/tmp/test_adb.txt');

      final downloadedContent = await downloadedFile.readAsString();
      print('下载的文件内容: $downloadedContent');

      // 清理文件
      await downloadedFile.delete();
    }

    // 清理测试文件
    await tempFile.delete();
    await adb.shell('rm /data/local/tmp/test_adb.txt');

    // APK安装示例（需要实际的APK文件）
    // print('\n--- APK安装 ---');
    // final apkFile = File('test.apk');
    // if (await apkFile.exists()) {
    //   await adb.install(apkFile);
    //   print('APK安装成功');
    // } else {
    //   print('测试APK文件不存在，跳过安装测试');
    // }

    // 端口转发示例
    print('\n--- 端口转发 ---');
    print('设置端口转发...');
    final forwarder = await adb.tcpForward(8080, 8080);
    print('端口转发已设置: 本地8080 -> 设备8080');

    // 等待用户输入
    print('按任意键停止端口转发...');
    await Future.delayed(Duration(seconds: 2));

    forwarder.close();
    print('端口转发已停止');

    // 关闭连接
    adb.close();
    print('\n=== 示例执行完成 ===');
  } catch (e) {
    print('错误: $e');
    exit(1);
  }
}

/// 设备配对示例
void pairingExample() async {
  print('=== 设备配对示例 ===');

  try {
    // 配对码通常显示在设备的开发者选项中
    const pairingCode = '123456';

    print('正在配对设备...');
    await Kadb.pair('192.168.1.100', 5555, pairingCode);
    print('配对成功!');

    // 现在可以使用常规ADB功能
    final adb = Kadb('192.168.1.100', 5555);
    final response = await adb.shell('echo "Paired successfully!"');
    print('设备响应: ${response.output.trim()}');

    adb.close();
  } catch (e) {
    print('配对失败: $e');
  }
}
