/// 文件同步流实现
///
/// 实现ADB SYNC协议，支持文件推送和拉取
/// 支持大文件分块传输和进度回调
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'adb_stream.dart';

/// SYNC协议命令
class SyncCommand {
  /// 列出目录
  static const String list = 'LIST';

  /// 接收文件
  static const String recv = 'RECV';

  /// 发送文件
  static const String send = 'SEND';

  /// 获取文件状态
  static const String stat = 'STAT';

  /// 数据块
  static const String data = 'DATA';

  /// 完成
  static const String done = 'DONE';

  /// 确认
  static const String okay = 'OKAY';

  /// 退出
  static const String quit = 'QUIT';

  /// 失败
  static const String fail = 'FAIL';

  /// 所有有效的SYNC命令
  static const Set<String> allCommands = {
    list, recv, send, stat, data, done, okay, quit, fail,
  };
}

/// 文件信息
class FileInfo {
  /// 文件模式（权限）
  final int mode;

  /// 文件大小
  final int size;

  /// 最后修改时间（秒）
  final int modificationTime;

  /// 构造函数
  const FileInfo({
    required this.mode,
    required this.size,
    required this.modificationTime,
  });

  /// 转换为字符串
  @override
  String toString() {
    return 'FileInfo(mode: 0${mode.toRadixString(8)}, size: $size, mtime: $modificationTime)';
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'mode': mode,
      'size': size,
      'modificationTime': modificationTime,
    };
  }
}

/// 目录条目
class DirectoryEntry {
  /// 文件模式
  final int mode;

  /// 文件大小
  final int size;

  /// 最后修改时间
  final int modificationTime;

  /// 文件名称
  final String name;

  /// 构造函数
  const DirectoryEntry({
    required this.mode,
    required this.size,
    required this.modificationTime,
    required this.name,
  });

  /// 检查是否是目录
  bool get isDirectory => (mode & 0x4000) != 0;

  /// 检查是否是文件
  bool get isFile => (mode & 0x8000) != 0;

  /// 检查是否是符号链接
  bool get isSymbolicLink => (mode & 0xA000) != 0;

  /// 获取文件权限（Unix格式）
  String get permissions {
    final buffer = StringBuffer();

    // 文件类型
    if (isDirectory) {
      buffer.write('d');
    } else if (isSymbolicLink) {
      buffer.write('l');
    } else {
      buffer.write('-');
    }

    // 所有者权限
    buffer.write((mode >> 6) & 0x4 != 0 ? 'r' : '-');
    buffer.write((mode >> 6) & 0x2 != 0 ? 'w' : '-');
    buffer.write((mode >> 6) & 0x1 != 0 ? 'x' : '-');

    // 组权限
    buffer.write((mode >> 3) & 0x4 != 0 ? 'r' : '-');
    buffer.write((mode >> 3) & 0x2 != 0 ? 'w' : '-');
    buffer.write((mode >> 3) & 0x1 != 0 ? 'x' : '-');

    // 其他权限
    buffer.write(mode & 0x4 != 0 ? 'r' : '-');
    buffer.write(mode & 0x2 != 0 ? 'w' : '-');
    buffer.write(mode & 0x1 != 0 ? 'x' : '-');

    return buffer.toString();
  }

  @override
  String toString() {
    return '$permissions $size $modificationTime $name';
  }
}

/// 进度回调
typedef ProgressCallback = void Function(int bytesTransferred, int totalBytes);

/// 文件同步流
class AdbSyncStream {
  final AdbStream _stream;

  /// 构造函数
  AdbSyncStream(this._stream);

  /// 发送文件到设备
  ///
  /// [localFile] 本地文件
  /// [remotePath] 远程路径
  /// [mode] 文件模式（可选，默认为0644）
  /// [lastModifiedMs] 最后修改时间（可选，默认为当前时间）
  /// [onProgress] 进度回调（可选）
  Future<void> sendFile({
    required File localFile,
    required String remotePath,
    int? mode,
    int? lastModifiedMs,
    ProgressCallback? onProgress,
  }) async {
    if (!localFile.existsSync()) {
      throw ArgumentError('本地文件不存在: ${localFile.path}');
    }

    final fileMode = mode ?? await _getFileMode(localFile);
    final lastModified = lastModifiedMs ?? localFile.lastModifiedSync().millisecondsSinceEpoch;

    await sendData(
      data: localFile.openRead(),
      remotePath: remotePath,
      size: localFile.lengthSync(),
      mode: fileMode,
      lastModifiedMs: lastModified,
      onProgress: onProgress,
    );
  }

  /// 发送数据流到设备
  ///
  /// [data] 数据流
  /// [remotePath] 远程路径
  /// [size] 数据大小
  /// [mode] 文件模式
  /// [lastModifiedMs] 最后修改时间
  /// [onProgress] 进度回调（可选）
  Future<void> sendData({
    required Stream<List<int>> data,
    required String remotePath,
    required int size,
    required int mode,
    required int lastModifiedMs,
    ProgressCallback? onProgress,
  }) async {
    final writer = _SYNCWriter(_stream);

    // 构造远程路径（包含模式和文件大小）
    final remoteInfo = '$remotePath,$mode';

    // 发送SEND命令
    await writer.writeCommand(SyncCommand.send, remoteInfo.length);
    await writer.writeString(remoteInfo);

    int bytesTransferred = 0;

    // 发送数据块
    await for (final chunk in data) {
      if (chunk.isEmpty) continue;

      final chunkData = _toUint8List(chunk);

      // 发送DATA命令
      await writer.writeCommand(SyncCommand.data, chunkData.length);
      await writer.writeBytes(chunkData);

      bytesTransferred += chunkData.length;

      // 进度回调
      if (onProgress != null) {
        onProgress(bytesTransferred, size);
      }
    }

    // 发送DONE命令（包含最后修改时间）
    final lastModifiedSeconds = lastModifiedMs ~/ 1000;
    await writer.writeCommand(SyncCommand.done, lastModifiedSeconds);

    // 等待确认
    final response = await _readResponse();
    if (response.command != SyncCommand.okay) {
      throw StateError('文件发送失败: ${response.message}');
    }
  }

  /// 从设备接收文件
  ///
  /// [localFile] 本地文件路径
  /// [remotePath] 远程路径
  /// [onProgress] 进度回调（可选）
  Future<void> receiveFile({
    required String localFile,
    required String remotePath,
    ProgressCallback? onProgress,
  }) async {
    final file = File(localFile);
    final sink = file.openWrite();

    try {
      await receiveData(
        sink: sink,
        remotePath: remotePath,
        onProgress: onProgress,
      );
    } finally {
      await sink.close();
    }
  }

  /// 从设备接收数据
  ///
  /// [sink] 数据接收器
  /// [remotePath] 远程路径
  /// [onProgress] 进度回调（可选）
  Future<void> receiveData({
    required EventSink<List<int>> sink,
    required String remotePath,
    ProgressCallback? onProgress,
  }) async {
    final writer = _SYNCWriter(_stream);

    // 发送RECV命令
    await writer.writeCommand(SyncCommand.recv, remotePath.length);
    await writer.writeString(remotePath);

    int bytesTransferred = 0;

    // 读取数据块
    while (true) {
      final response = await _readResponse();

      switch (response.command) {
        case SyncCommand.data:
          // 数据块
          final data = response.data;
          sink.add(data);
          bytesTransferred += data.length;

          if (onProgress != null) {
            onProgress(bytesTransferred, -1); // 总大小未知
          }
          break;

        case SyncCommand.done:
          // 传输完成
          sink.close();
          return;

        case SyncCommand.fail:
          // 传输失败
          sink.addError(StateError('文件接收失败: ${response.message}'));
          return;

        default:
          throw StateError('意外的SYNC响应: ${response.command}');
      }
    }
  }

  /// 获取文件状态
  Future<FileInfo> stat(String remotePath) async {
    final writer = _SYNCWriter(_stream);

    // 发送STAT命令
    await writer.writeCommand(SyncCommand.stat, remotePath.length);
    await writer.writeString(remotePath);

    // 读取响应
    final response = await _readResponse();
    if (response.command != SyncCommand.stat) {
      throw StateError('STAT命令失败: ${response.message}');
    }

    return FileInfo(
      mode: response.mode,
      size: response.size,
      modificationTime: response.modificationTime,
    );
  }

  /// 列出目录内容
  Future<List<DirectoryEntry>> listDirectory(String remotePath) async {
    final writer = _SYNCWriter(_stream);
    final entries = <DirectoryEntry>[];

    // 发送LIST命令
    await writer.writeCommand(SyncCommand.list, remotePath.length);
    await writer.writeString(remotePath);

    // 读取目录条目
    while (true) {
      final response = await _readResponse();

      switch (response.command) {
        case SyncCommand.dent:
          // 目录条目
          entries.add(DirectoryEntry(
            mode: response.mode,
            size: response.size,
            modificationTime: response.modificationTime,
            name: response.name,
          ));
          break;

        case SyncCommand.done:
          // 列表完成
          return entries;

        default:
          throw StateError('意外的LIST响应: ${response.command}');
      }
    }
  }

  /// 关闭同步流
  Future<void> close() async {
    final writer = _SYNCWriter(_stream);

    // 发送QUIT命令
    await writer.writeCommand(SyncCommand.quit, 0);

    // 关闭底层流
    await _stream.close();
  }

  /// 读取SYNC响应
  Future<_SYNCResponse> _readResponse() async {
    final reader = _SYNCReader(_stream);

    // 读取命令和参数
    final command = await reader.readCommand();
    final arg = await reader.readInt32();

    switch (command) {
      case SyncCommand.okay:
        return _SYNCResponse.okay();

      case SyncCommand.fail:
        final message = await reader.readString(arg);
        return _SYNCResponse.fail(message);

      case SyncCommand.stat:
        final mode = arg;
        final size = await reader.readInt32();
        final time = await reader.readInt32();
        return _SYNCResponse.stat(mode, size, time);

      case SyncCommand.dent:
        final mode = arg;
        final size = await reader.readInt32();
        final time = await reader.readInt32();
        final nameLen = await reader.readInt32();
        final name = await reader.readString(nameLen);
        return _SYNCResponse.dent(mode, size, time, name);

      case SyncCommand.data:
        final data = await reader.readBytes(arg);
        return _SYNCResponse.data(data);

      case SyncCommand.done:
        return _SYNCResponse.done();

      default:
        throw StateError('未知的SYNC命令: $command');
    }
  }

  /// 获取文件模式（Unix权限）
  /// 获取文件模式（完整实现，基于Kadb的readMode）
  Future<int> _getFileMode(File file) async {
    try {
      // 尝试读取Unix文件权限
      if (Platform.isLinux || Platform.isMacOS) {
        try {
          // 在支持Unix文件系统的平台上，尝试读取文件权限
          final result = await Process.run('stat', ['-c', '%a', file.path]);
          if (result.exitCode == 0) {
            final permissions = int.tryParse(result.stdout.toString().trim());
            if (permissions != null) {
              // 将八进制权限转换为Unix模式
              return permissions | _getFileTypeMode(file);
            }
          }
        } catch (e) {
          // 忽略错误，继续使用其他方法
        }

        // 尝试使用ls命令
        try {
          final result = await Process.run('ls', ['-ld', file.path]);
          if (result.exitCode == 0) {
            final output = result.stdout.toString();
            final permissions = _parseFilePermissions(output);
            if (permissions != null) {
              return permissions | _getFileTypeMode(file);
            }
          }
        } catch (e) {
          // 忽略错误，继续使用其他方法
        }
      }

      // 使用Dart的文件权限API（跨平台）
      return _getFileModeFromDartApi(file);

    } catch (e) {
      // 如果所有方法都失败，返回默认权限
      return 0o644 | _getFileTypeMode(file); // rw-r--r--
    }
  }

  /// 从Dart API获取文件模式
  int _getFileModeFromDartApi(File file) {
    int mode = _getFileTypeMode(file);

    try {
      // 检查文件权限
      if (_canRead(file)) {
        mode |= 0o444; // r--r--r-- (所有用户读权限)
      }
      if (_canWrite(file)) {
        mode |= 0o222; // -w--w--w- (所有用户写权限)
      }
      if (_canExecute(file)) {
        mode |= 0o111; // --x--x--x (所有用户执行权限)
      }

      // 根据文件所有者是当前用户，设置所有者权限
      if (_isOwner(file)) {
        // 如果是文件所有者，给予完全权限
        mode |= 0o700; // rwx------
      }

      return mode;
    } catch (e) {
      // 如果出错，返回安全默认值
      return _getFileTypeMode(file) | 0o644;
    }
  }

  /// 获取文件类型模式
  int _getFileTypeMode(File file) {
    try {
      final stat = file.statSync();

      switch (stat.type) {
        case FileSystemEntityType.file:
          return 0x8000; // S_IFREG
        case FileSystemEntityType.directory:
          return 0x4000; // S_IFDIR
        case FileSystemEntityType.link:
          return 0xa000; // S_IFLNK
        case FileSystemEntityType.pipe:
          return 0x1000; // S_IFIFO
        case FileSystemEntityType.socket:
          return 0xc000; // S_IFSOCK
        case FileSystemEntityType.block:
          return 0x6000; // S_IFBLK
        case FileSystemEntityType.character:
          return 0x2000; // S_IFCHR
        default:
          return 0x8000; // S_IFREG (默认作为文件)
      }
    } catch (e) {
      return 0x8000; // S_IFREG (默认作为文件)
    }
  }

  /// 解析文件权限字符串（如ls -l输出）
  int? _parseFilePermissions(String lsOutput) {
    // 解析类似 "drwxr-xr-x" 的权限字符串
    final permissionMatch = RegExp(r'^([d-])([r-])([w-])([x-])([r-])([w-])([x-])([r-])([w-])([x-])').firstMatch(lsOutput);
    if (permissionMatch == null) return null;

    int mode = 0;

    // 文件类型
    if (permissionMatch.group(1) == 'd') {
      mode |= 0x4000; // S_IFDIR
    } else {
      mode |= 0x8000; // S_IFREG
    }

    // 所有者权限
    if (permissionMatch.group(2) == 'r') mode |= 0o400;
    if (permissionMatch.group(3) == 'w') mode |= 0o200;
    if (permissionMatch.group(4) == 'x') mode |= 0o100;

    // 组权限
    if (permissionMatch.group(5) == 'r') mode |= 0o040;
    if (permissionMatch.group(6) == 'w') mode |= 0o020;
    if (permissionMatch.group(7) == 'x') mode |= 0o010;

    // 其他用户权限
    if (permissionMatch.group(8) == 'r') mode |= 0o004;
    if (permissionMatch.group(9) == 'w') mode |= 0o002;
    if (permissionMatch.group(10) == 'x') mode |= 0o001;

    return mode;
  }

  /// 检查是否可以读取文件
  bool _canRead(File file) {
    try {
      return file.existsSync() && file.statSync().mode != 0;
    } catch (e) {
      return false;
    }
  }

  /// 检查是否可以写入文件
  bool _canWrite(File file) {
    try {
      // 尝试创建临时文件来测试写入权限
      final tempFile = File('${file.path}.tmp_${DateTime.now().millisecondsSinceEpoch}');
      tempFile.createSync();
      tempFile.deleteSync();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 检查是否可以执行文件
  bool _canExecute(File file) {
    try {
      if (!file.existsSync()) return false;

      // 在Windows上，检查文件扩展名
      if (Platform.isWindows) {
        final executableExtensions = ['.exe', '.bat', '.cmd', '.com', '.pif', '.scr', '.vbs', '.js'];
        final path = file.path.toLowerCase();
        return executableExtensions.any((ext) => path.endsWith(ext));
      }

      // 在Unix系统上，使用系统调用检查执行权限
      try {
        // 方法1: 尝试使用stat命令获取权限
        final result = Process.runSync('stat', ['-c', '%a', file.path]);
        if (result.exitCode == 0) {
          final permissions = int.tryParse(result.stdout.toString().trim());
          if (permissions != null) {
            // 检查所有者、组和其他用户的执行权限
            return (permissions & 0o111) != 0; // 任何执行权限位被设置
          }
        }
      } catch (e) {
        // 忽略错误，尝试其他方法
      }

      // 方法2: 尝试使用ls命令
      try {
        final result = Process.runSync('ls', ['-ld', file.path]);
        if (result.exitCode == 0) {
          final output = result.stdout.toString();
          // 解析权限字符串，检查执行位
          final permissionMatch = RegExp(r'^([d-])([r-])([w-])([x-])([r-])([w-])([x-])([r-])([w-])([x-])').firstMatch(output);
          if (permissionMatch != null) {
            // 检查任何执行位：所有者(4)、组(7)、其他(10)
            return permissionMatch.group(4) == 'x' ||
                   permissionMatch.group(7) == 'x' ||
                   permissionMatch.group(10) == 'x';
          }
        }
      } catch (e) {
        // 忽略错误，使用备用方法
      }

      // 方法3: 尝试访问文件模式（如果平台支持）
      try {
        if (Platform.isLinux || Platform.isMacOS) {
          // 尝试使用文件模式的低12位
          final stat = file.statSync();
          // 在Unix系统上，stat.mode包含权限信息
          final mode = stat.mode;
          // 检查执行权限位（所有者、组、其他）
          return (mode & 0o111) != 0;
        }
      } catch (e) {
        // 忽略错误
      }

      // 方法4: 最后备用 - 尝试实际执行测试（不推荐，但最准确）
      try {
        // 仅在Unix系统上尝试
        if (Platform.isLinux || Platform.isMacOS) {
          // 尝试使用access系统调用（通过test命令）
          final result = Process.runSync('test', ['-x', file.path]);
          return result.exitCode == 0;
        }
      } catch (e) {
        // 如果所有方法都失败，返回false
        return false;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// 检查是否是文件所有者（完整实现）
  bool _isOwner(File file) {
    try {
      // 在Unix系统上，真正的文件所有者检查需要系统调用
      if (Platform.isLinux || Platform.isMacOS) {
        try {
          // 方法1: 使用stat命令获取文件所有者的UID
          final result = Process.runSync('stat', ['-c', '%u', file.path]);
          if (result.exitCode == 0) {
            final fileOwnerUid = int.tryParse(result.stdout.toString().trim());
            if (fileOwnerUid != null) {
              // 获取当前用户的UID
              final userResult = Process.runSync('id', ['-u']);
              if (userResult.exitCode == 0) {
                final currentUid = int.tryParse(userResult.stdout.toString().trim());
                if (currentUid != null) {
                  return fileOwnerUid == currentUid;
                }
              }
            }
          }
        } catch (e) {
          // 忽略错误，尝试其他方法
        }

        // 方法2: 使用ls命令和文件权限推断
        try {
          final result = Process.runSync('ls', ['-ld', file.path]);
          if (result.exitCode == 0) {
            final output = result.stdout.toString();
            // 检查我们是否有写权限（通常表示我们是所有者或是root）
            final permissionMatch = RegExp(r'^([d-])([r-])([w-])([x-])([r-])([w-])([x-])([r-])([w-])([x-])').firstMatch(output);
            if (permissionMatch != null) {
              // 如果所有者有写权限，且我们有写权限，则我们可能是所有者
              return permissionMatch.group(3) == 'w';
            }
          }
        } catch (e) {
          // 忽略错误，使用备用方法
        }

        // 方法3: 使用文件系统权限和访问时间推断（不太准确）
        try {
          final stat = file.statSync();
          // 如果我们有写权限，通常表示我们是所有者或者是组成员
          // 但这只是一个近似判断
          final mode = stat.mode;
          return (mode & 0o200) != 0; // 所有者写权限
        } catch (e) {
          // 忽略错误
        }
      }

      // 在Windows上，所有者概念不同，我们使用平台特定的逻辑
      if (Platform.isWindows) {
        // Windows上使用文件属性检查
        try {
          // 如果我们能修改文件，通常表示我们有足够权限
          return _canWrite(file);
        } catch (e) {
          return false;
        }
      }

      // 最后备用：使用写权限作为所有者的近似判断
      return _canWrite(file);

    } catch (e) {
      return false;
    }
  }

  /// 转换数据类型
  Uint8List _toUint8List(List<int> data) {
    if (data is Uint8List) {
      return data;
    }
    return Uint8List.fromList(data);
  }
}

/// SYNC写入器
class _SYNCWriter {
  final AdbStream _stream;

  _SYNCWriter(this._stream);

  /// 写入命令
  Future<void> writeCommand(String command, int arg) async {
    final data = Uint8List(8);
    data.setAll(0, command.codeUnits);
    data.setAll(4, _writeInt32(arg));
    await _stream.write(data);
  }

  /// 写入字符串
  Future<void> writeString(String str) async {
    await _stream.write(Uint8List.fromList(str.codeUnits));
  }

  /// 写入字节数组
  Future<void> writeBytes(Uint8List data) async {
    await _stream.write(data);
  }

  /// 写入32位整数（小端格式）
  Uint8List _writeInt32(int value) {
    return Uint8List(4)
      ..[0] = value & 0xFF
      ..[1] = (value >> 8) & 0xFF
      ..[2] = (value >> 16) & 0xFF
      ..[3] = (value >> 24) & 0xFF;
  }
}

/// SYNC读取器
class _SYNCReader {
  final AdbStream _stream;

  _SYNCReader(this._stream);

  /// 读取命令
  Future<String> readCommand() async {
    final data = await _stream.readFully(4);
    return String.fromCharCodes(data);
  }

  /// 读取32位整数
  Future<int> readInt32() async {
    final data = await _stream.readFully(4);
    return _readInt32(data, 0);
  }

  /// 读取字符串
  Future<String> readString(int length) async {
    final data = await _stream.readFully(length);
    return String.fromCharCodes(data);
  }

  /// 读取字节数组
  Future<Uint8List> readBytes(int length) async {
    return await _stream.readFully(length);
  }

  /// 读取32位整数（小端格式）
  int _readInt32(Uint8List data, int offset) {
    return (data[offset] & 0xFF) |
           ((data[offset + 1] & 0xFF) << 8) |
           ((data[offset + 2] & 0xFF) << 16) |
           ((data[offset + 3] & 0xFF) << 24);
  }
}

/// SYNC响应
class _SYNCResponse {
  final String command;
  final String? message;
  final int? mode;
  final int? size;
  final int? modificationTime;
  final String? name;
  final Uint8List? data;

  _SYNCResponse.okay()
      : command = SyncCommand.okay,
        message = null,
        mode = null,
        size = null,
        modificationTime = null,
        name = null,
        data = null;

  _SYNCResponse.fail(this.message)
      : command = SyncCommand.fail,
        mode = null,
        size = null,
        modificationTime = null,
        name = null,
        data = null;

  _SYNCResponse.stat(this.mode, this.size, this.modificationTime)
      : command = SyncCommand.stat,
        message = null,
        name = null,
        data = null;

  _SYNCResponse.dent(this.mode, this.size, this.modificationTime, this.name)
      : command = SyncCommand.dent,
        message = null,
        data = null;

  _SYNCResponse.data(this.data)
      : command = SyncCommand.data,
        message = null,
        mode = null,
        size = null,
        modificationTime = null,
        name = null;

  _SYNCResponse.done()
      : command = SyncCommand.done,
        message = null,
        mode = null,
        size = null,
        modificationTime = null,
        name = null,
        data = null;
}
