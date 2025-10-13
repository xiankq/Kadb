/// ADB密钥对存储管理
/// 用于持久化和重用ADB密钥对，确保重连时使用相同的密钥
library;

import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:kadb_dart/cert/adb_key_pair.dart';

/// ADB密钥对存储管理器
class KeyPairStorage {
  /// 默认密钥存储目录
  static String get _defaultKeyDir {
    final homeDir = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return path.join(homeDir, '.kadb_dart');
  }

  /// 保存密钥对到文件
  /// [keyPair] 要保存的密钥对
  /// [keyName] 密钥名称（默认为'default'）
  /// [keyDir] 密钥存储目录（可选）
  static Future<void> saveKeyPair(
    AdbKeyPair keyPair, {
    String keyName = 'default',
    String? keyDir,
  }) async {
    final directory = keyDir ?? _defaultKeyDir;
    await Directory(directory).create(recursive: true);

    final privateKeyPath = path.join(directory, '$keyName.key');
    final publicKeyPath = path.join(directory, '$keyName.pub');

    // 保存私钥（PEM格式）
    final privateKeyPem = keyPair.toPrivateKeyPem();
    await File(privateKeyPath).writeAsString(privateKeyPem);

    // 保存公钥（用于调试和验证）
    final publicKeySsh = keyPair.toPublicKeySsh();
    await File(publicKeyPath).writeAsString(publicKeySsh);

    print('密钥对已保存到:');
    print('  私钥: $privateKeyPath');
    print('  公钥: $publicKeyPath');
  }

  /// 从文件加载密钥对
  /// [keyName] 密钥名称（默认为'default'）
  /// [keyDir] 密钥存储目录（可选）
  /// 返回加载的密钥对，如果不存在则返回null
  static Future<AdbKeyPair?> loadKeyPair({
    String keyName = 'default',
    String? keyDir,
  }) async {
    final directory = keyDir ?? _defaultKeyDir;
    final privateKeyPath = path.join(directory, '$keyName.key');

    final privateKeyFile = File(privateKeyPath);
    if (!await privateKeyFile.exists()) {
      return null;
    }

    try {
      final privateKeyPem = await privateKeyFile.readAsString();
      final keyPair = await AdbKeyPair.fromPrivateKeyPem(privateKeyPem);
      print('密钥对已从文件加载: $privateKeyPath');
      return keyPair;
    } catch (e) {
      print('加载密钥对失败: $e');
      return null;
    }
  }

  /// 获取或创建密钥对
  /// 首先尝试从文件加载，如果不存在则创建新的并保存
  /// [keyName] 密钥名称（默认为'default'）
  /// [keyDir] 密钥存储目录（可选）
  static Future<AdbKeyPair> getOrCreateKeyPair({
    String keyName = 'default',
    String? keyDir,
  }) async {
    // 尝试加载现有密钥对
    final existingKeyPair = await loadKeyPair(keyName: keyName, keyDir: keyDir);
    if (existingKeyPair != null) {
      return existingKeyPair;
    }

    // 创建新密钥对
    print('创建新的ADB密钥对...');
    final newKeyPair = await AdbKeyPair.generate();
    await saveKeyPair(newKeyPair, keyName: keyName, keyDir: keyDir);
    return newKeyPair;
  }

  /// 检查密钥文件是否存在
  /// [keyName] 密钥名称（默认为'default'）
  /// [keyDir] 密钥存储目录（可选）
  static Future<bool> keyPairExists({
    String keyName = 'default',
    String? keyDir,
  }) async {
    final directory = keyDir ?? _defaultKeyDir;
    final privateKeyPath = path.join(directory, '$keyName.key');
    return await File(privateKeyPath).exists();
  }

  /// 删除密钥文件
  /// [keyName] 密钥名称（默认为'default'）
  /// [keyDir] 密钥存储目录（可选）
  static Future<bool> deleteKeyPair({
    String keyName = 'default',
    String? keyDir,
  }) async {
    final directory = keyDir ?? _defaultKeyDir;
    final privateKeyPath = path.join(directory, '$keyName.key');
    final publicKeyPath = path.join(directory, '$keyName.pub');

    try {
      await File(privateKeyPath).delete();
      await File(publicKeyPath).delete();
      print('密钥文件已删除: $privateKeyPath');
      return true;
    } catch (e) {
      print('删除密钥文件失败: $e');
      return false;
    }
  }
}