import 'dart:async';
import 'dart:io';
import 'package:kadb_dart/kadb_dart.dart';
import 'package:kadb_dart/cert/cert_utils.dart';

/// 调试连接示例
/// 使用系统ADB密钥进行连接测试
void main() async {
  print('=== 调试ADB连接示例 ===');

  final host = '192.168.2.94';
  final port = 5555;

  print('正在连接到 $host:$port...');

  try {
    // 1. 检查系统ADB公钥
    print('\n1. 检查系统ADB公钥...');
    await _checkSystemAdbKeys();

    // 2. 生成新的密钥对
    print('\n2. 生成新的密钥对...');
    final keyPair = await CertUtils.loadKeyPair();

    // 3. 显示系统身份信息
    print('\n3. 显示系统身份信息...');
    final systemIdentity = CertUtils.generateSystemIdentity();
    print('系统身份: $systemIdentity');

    // 4. 显示生成的公钥信息
    print('\n4. 显示生成的公钥信息...');
    final publicKeyBytes = CertUtils.generateAuthFormatPublicKey(keyPair, systemIdentity);
    final publicKeyString = String.fromCharCodes(publicKeyBytes);
    print('公钥长度: ${publicKeyBytes.length}');
    print('公钥内容: $publicKeyString');

    // 5. 尝试连接
    print('\n5. 尝试连接...');
    final connection = await KadbDart.connect(
      host: host,
      port: port,
      keyPair: keyPair,
      debug: true,
    );

    print('✅ ADB连接建立成功');

    // 6. 测试简单命令
    print('\n6. 测试简单命令...');
    final shellStream = await KadbDart.executeShell(connection, 'echo', ['Hello from Dart ADB']);

    String output = '';
    shellStream.stdout.listen((data) {
      output += data;
      print('收到输出: $data');
    });

    await shellStream.stdout.first;
    await shellStream.close();

    print('✅ 命令执行完成，输出: $output');

    // 关闭连接
    connection.close();
    print('✅ 连接已关闭');

  } catch (e) {
    print('❌ 连接失败: $e');
    print('错误堆栈: ${StackTrace.current}');
  }
}

/// 检查系统ADB密钥
Future<void> _checkSystemAdbKeys() async {
  final homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  final adbKeysPath = '$homeDir/.android/adbkey.pub';

  final adbKeysFile = File(adbKeysPath);
  if (await adbKeysFile.exists()) {
    print('✅ 找到系统ADB公钥: $adbKeysPath');
    final content = await adbKeysFile.readAsString();
    print('系统公钥内容: $content');
    print('系统公钥长度: ${content.length}');
  } else {
    print('❌ 未找到系统ADB公钥');
  }
}