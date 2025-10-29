/// ADB异常定义
///
/// 定义了ADB操作过程中可能抛出的各种异常
/// 所有异常都继承自AdbException基类，提供中文错误信息
library;

/// ADB基础异常类
class AdbException implements Exception {
  /// 错误消息
  final String message;

  /// 错误代码（可选）
  final String? errorCode;

  /// 原始异常（可选）
  final Object? cause;

  /// 构造函数
  const AdbException(this.message, {this.errorCode, this.cause});

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('ADB异常');

    if (errorCode != null) {
      buffer.write('[$errorCode]');
    }

    buffer.write(': $message');

    if (cause != null) {
      buffer.write(' (原因: $cause)');
    }

    return buffer.toString();
  }
}

/// 连接异常
class AdbConnectionException extends AdbException {
  const AdbConnectionException(String message,
      {String? errorCode, Object? cause})
      : super(message, errorCode: errorCode, cause: cause);
}

/// 认证异常
class AdbAuthException extends AdbException {
  const AdbAuthException(String message, {String? errorCode, Object? cause})
      : super(message, errorCode: errorCode, cause: cause);
}

/// 配对认证异常
class AdbPairAuthException extends AdbAuthException {
  const AdbPairAuthException(String message, {String? errorCode, Object? cause})
      : super(message, errorCode: errorCode, cause: cause);
}

/// 流操作异常
class AdbStreamException extends AdbException {
  /// 本地流ID
  final int? localId;

  /// 远程流ID
  final int? remoteId;

  const AdbStreamException(
    String message, {
    this.localId,
    this.remoteId,
    String? errorCode,
    Object? cause,
  }) : super(message, errorCode: errorCode, cause: cause);

  @override
  String toString() {
    final buffer = StringBuffer('流操作异常');

    if (errorCode != null) {
      buffer.write('[$errorCode]');
    }

    buffer.write(': $message');

    if (localId != null || remoteId != null) {
      buffer.write(' (');
      if (localId != null) {
        buffer.write('本地ID: 0x${localId!.toRadixString(16).toUpperCase()}');
      }
      if (localId != null && remoteId != null) {
        buffer.write(', ');
      }
      if (remoteId != null) {
        buffer.write('远程ID: 0x${remoteId!.toRadixString(16).toUpperCase()}');
      }
      buffer.write(')');
    }

    if (cause != null) {
      buffer.write(' (原因: $cause)');
    }

    return buffer.toString();
  }
}

/// 流已关闭异常
class AdbStreamClosed extends AdbStreamException {
  const AdbStreamClosed(int localId)
      : super('流已关闭', localId: localId, errorCode: 'STREAM_CLOSED');
}

/// 传输异常
class AdbTransportException extends AdbException {
  /// 本地地址
  final String? localAddress;

  /// 远程地址
  final String? remoteAddress;

  /// 本地端口
  final int? localPort;

  /// 远程端口
  final int? remotePort;

  const AdbTransportException(
    String message, {
    this.localAddress,
    this.remoteAddress,
    this.localPort,
    this.remotePort,
    String? errorCode,
    Object? cause,
  }) : super(message, errorCode: errorCode, cause: cause);

  @override
  String toString() {
    final buffer = StringBuffer('传输异常');

    if (errorCode != null) {
      buffer.write('[$errorCode]');
    }

    buffer.write(': $message');

    final hasAddress = localAddress != null || remoteAddress != null;
    final hasPort = localPort != null || remotePort != null;

    if (hasAddress || hasPort) {
      buffer.write(' (');

      if (hasAddress) {
        if (localAddress != null) {
          buffer.write('本地: $localAddress');
          if (localPort != null) {
            buffer.write(':$localPort');
          }
        }

        if (remoteAddress != null) {
          if (localAddress != null) buffer.write(', ');
          buffer.write('远程: $remoteAddress');
          if (remotePort != null) {
            buffer.write(':$remotePort');
          }
        }
      } else if (hasPort) {
        if (localPort != null) {
          buffer.write('本地端口: $localPort');
        }
        if (remotePort != null) {
          if (localPort != null) buffer.write(', ');
          buffer.write('远程端口: $remotePort');
        }
      }

      buffer.write(')');
    }

    if (cause != null) {
      buffer.write(' (原因: $cause)');
    }

    return buffer.toString();
  }
}

/// 协议异常
class AdbProtocolException extends AdbException {
  const AdbProtocolException(String message, {String? errorCode, Object? cause})
      : super(message, errorCode: errorCode, cause: cause);
}

/// 消息格式异常
class AdbMessageException extends AdbProtocolException {
  const AdbMessageException(String message, {String? errorCode, Object? cause})
      : super(message, errorCode: errorCode, cause: cause);
}

/// 校验和异常
class AdbChecksumException extends AdbMessageException {
  final int expectedChecksum;
  final int actualChecksum;

  const AdbChecksumException(
    this.expectedChecksum,
    this.actualChecksum, {
    String? errorCode,
    Object? cause,
  }) : super(
          '消息校验和验证失败',
          errorCode: errorCode ?? 'CHECKSUM_MISMATCH',
          cause: cause,
        );

  @override
  String toString() {
    return '校验和异常[$errorCode]: 期望校验和=$expectedChecksum, 实际校验和=$actualChecksum';
  }
}

/// 超时异常
class AdbTimeoutException extends AdbException {
  final Duration timeout;

  const AdbTimeoutException(this.timeout, String message)
      : super(message, errorCode: 'TIMEOUT');

  @override
  String toString() {
    return '超时异常[$errorCode]: $message (超时时间: ${timeout.inMilliseconds}ms)';
  }
}

/// 文件操作异常
class AdbFileException extends AdbException {
  /// 远程文件路径
  final String? remotePath;

  /// 本地文件路径
  final String? localPath;

  const AdbFileException(
    String message, {
    this.remotePath,
    this.localPath,
    String? errorCode,
    Object? cause,
  }) : super(message, errorCode: errorCode, cause: cause);

  @override
  String toString() {
    final buffer = StringBuffer('文件操作异常');

    if (errorCode != null) {
      buffer.write('[$errorCode]');
    }

    buffer.write(': $message');

    if (remotePath != null || localPath != null) {
      buffer.write(' (');

      if (remotePath != null) {
        buffer.write('远程: $remotePath');
      }

      if (localPath != null) {
        if (remotePath != null) buffer.write(', ');
        buffer.write('本地: $localPath');
      }

      buffer.write(')');
    }

    if (cause != null) {
      buffer.write(' (原因: $cause)');
    }

    return buffer.toString();
  }
}

/// Shell命令异常
class AdbShellException extends AdbException {
  /// 命令字符串
  final String? command;

  /// 退出码
  final int? exitCode;

  /// 标准输出
  final String? stdout;

  /// 标准错误
  final String? stderr;

  const AdbShellException(
    String message, {
    this.command,
    this.exitCode,
    this.stdout,
    this.stderr,
    String? errorCode,
    Object? cause,
  }) : super(message, errorCode: errorCode, cause: cause);

  @override
  String toString() {
    final buffer = StringBuffer('Shell命令异常');

    if (errorCode != null) {
      buffer.write('[$errorCode]');
    }

    buffer.write(': $message');

    if (command != null || exitCode != null) {
      buffer.write(' (');

      if (command != null) {
        buffer.write('命令: $command');
      }

      if (exitCode != null) {
        if (command != null) buffer.write(', ');
        buffer.write('退出码: $exitCode');
      }

      buffer.write(')');
    }

    if (stdout != null && stdout!.isNotEmpty) {
      buffer.write('\n标准输出:\n$stdout');
    }

    if (stderr != null && stderr!.isNotEmpty) {
      buffer.write('\n标准错误:\n$stderr');
    }

    if (cause != null) {
      buffer.write('\n原因: $cause');
    }

    return buffer.toString();
  }
}
