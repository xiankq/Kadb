import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

/// ADB连接异常
class AdbConnectionException implements Exception {
  final String message;
  final dynamic cause;
  final String? host;
  final int? port;
  final int? errorCode;

  AdbConnectionException(
    this.message, [
    this.cause,
    this.host,
    this.port,
    this.errorCode,
  ]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbConnectionException: $message');
    if (cause != null) {
      buffer.write('\n  Caused by: $cause');
    }
    if (host != null && port != null) {
      buffer.write('\n  Connection: $host:$port');
    }
    if (errorCode != null) {
      buffer.write('\n  Error code: $errorCode');
    }
    return buffer.toString();
  }

  /// 获取详细的错误信息
  String get detailedMessage {
    final buffer = StringBuffer();
    buffer.writeln('ADB Connection Error: $message');
    
    if (cause != null) {
      buffer.writeln('Root Cause: $cause');
    }
    
    if (host != null && port != null) {
      buffer.writeln('Target: $host:$port');
    }
    
    if (errorCode != null) {
      buffer.writeln('System Error Code: $errorCode');
      buffer.writeln('Error Description: ${_getErrorDescription(errorCode!)}');
    }
    
    return buffer.toString();
  }

  String _getErrorDescription(int code) {
    switch (code) {
      case 61: return 'Connection refused';
      case 64: return 'Host is down';
      case 65: return 'No route to host';
      case 104: return 'Connection reset by peer';
      case 111: return 'Connection refused';
      case 113: return 'No route to host';
      case 110: return 'Connection timed out';
      case 115: return 'Operation in progress';
      default: return 'Unknown error';
    }
  }

  /// 检查是否为可恢复的错误
  bool get isRecoverable {
    if (errorCode == null) return false;
    return const [61, 64, 65, 104, 111, 113].contains(errorCode);
  }
}

/// ADB流异常
class AdbStreamException implements Exception {
  final String message;
  final dynamic cause;
  final int? streamId;

  AdbStreamException(this.message, [this.cause, this.streamId]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbStreamException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    if (streamId != null) {
      buffer.write(' (stream: $streamId)');
    }
    return buffer.toString();
  }
}

/// ADB协议异常
class AdbProtocolException implements Exception {
  final String message;
  final dynamic cause;
  final int? command;
  final int? arg0;
  final int? arg1;
  final Uint8List? payload;

  AdbProtocolException(
    this.message, [
    this.cause,
    this.command,
    this.arg0,
    this.arg1,
    this.payload,
  ]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbProtocolException: $message');
    if (cause != null) {
      buffer.write('\n  Caused by: $cause');
    }
    if (command != null) {
      buffer.write('\n  Command: 0x${command!.toRadixString(16)} (${_getCommandName(command!)})');
    }
    if (arg0 != null) {
      buffer.write('\n  Arg0: $arg0 (0x${arg0!.toRadixString(16)})');
    }
    if (arg1 != null) {
      buffer.write('\n  Arg1: $arg1 (0x${arg1!.toRadixString(16)})');
    }
    if (payload != null && payload!.isNotEmpty) {
      buffer.write('\n  Payload: ${payload!.length} bytes');
      if (payload!.length <= 64) {
        buffer.write(' (hex: ${_bytesToHex(payload!)})');
      }
    }
    return buffer.toString();
  }

  String _getCommandName(int cmd) {
    const commands = {
      0x48545541: 'AUTH',
      0x4e584e43: 'CNXN',
      0x4e45504f: 'OPEN',
      0x59414b4f: 'OKAY',
      0x45534c43: 'CLSE',
      0x45545257: 'WRTE',
      0x534c5453: 'STLS',
    };
    return commands[cmd] ?? 'UNKNOWN';
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  /// 获取协议错误类型
  String get errorType {
    if (command == 0x48545541) return 'Authentication Error';
    if (command == 0x4e584e43) return 'Connection Error';
    if (command == 0x4e45504f) return 'Stream Open Error';
    if (command == 0x59414b4f) return 'Stream Acknowledgment Error';
    if (command == 0x45534c43) return 'Stream Close Error';
    if (command == 0x45545257) return 'Data Write Error';
    if (command == 0x534c5453) return 'TLS Error';
    return 'Protocol Error';
  }
}

/// ADB认证异常
class AdbAuthException implements Exception {
  final String message;
  final dynamic cause;
  final String? authType;

  AdbAuthException(this.message, [this.cause, this.authType]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbAuthException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    if (authType != null) {
      buffer.write(' (auth type: $authType)');
    }
    return buffer.toString();
  }
}

/// ADB配对认证异常
class AdbPairAuthException implements Exception {
  final String message;
  final dynamic cause;
  final String? pairingCode;

  AdbPairAuthException(this.message, [this.cause, this.pairingCode]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbPairAuthException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    if (pairingCode != null) {
      buffer.write(' (pairing code: $pairingCode)');
    }
    return buffer.toString();
  }
}

/// ADB流关闭异常
class AdbStreamClosedException implements Exception {
  final String message;
  final dynamic cause;
  final int? streamId;

  AdbStreamClosedException(this.message, [this.cause, this.streamId]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbStreamClosedException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    if (streamId != null) {
      buffer.write(' (stream: $streamId)');
    }
    return buffer.toString();
  }
}

/// ADB同步异常
class AdbSyncException implements Exception {
  final String message;
  final dynamic cause;
  final String? remotePath;

  AdbSyncException(this.message, [this.cause, this.remotePath]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbSyncException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    if (remotePath != null) {
      buffer.write(' (path: $remotePath)');
    }
    return buffer.toString();
  }
}

/// ADB安装异常
class AdbInstallException implements Exception {
  final String message;
  final dynamic cause;
  final String? packageName;
  final String? apkPath;

  AdbInstallException(
    this.message, [
    this.cause,
    this.packageName,
    this.apkPath,
  ]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbInstallException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    if (packageName != null) {
      buffer.write(' (package: $packageName)');
    }
    if (apkPath != null) {
      buffer.write(' (apk: $apkPath)');
    }
    return buffer.toString();
  }
}

/// ADB转发异常
class AdbForwardException implements Exception {
  final String message;
  final dynamic cause;
  final int? hostPort;
  final int? targetPort;

  AdbForwardException(
    this.message, [
    this.cause,
    this.hostPort,
    this.targetPort,
  ]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbForwardException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    if (hostPort != null) {
      buffer.write(' (host port: $hostPort)');
    }
    if (targetPort != null) {
      buffer.write(' (target port: $targetPort)');
    }
    return buffer.toString();
  }
}

/// ADB超时异常
class AdbTimeoutException implements Exception {
  final String message;
  final Duration? timeout;
  final String? operation;

  AdbTimeoutException(
    this.message, [
    this.timeout,
    this.operation,
  ]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbTimeoutException: $message');
    if (operation != null) {
      buffer.write('\n  Operation: $operation');
    }
    if (timeout != null) {
      buffer.write('\n  Timeout: ${timeout!.inMilliseconds}ms');
    }
    return buffer.toString();
  }

  /// 获取超时建议
  String get timeoutSuggestion {
    if (timeout == null) return '请检查网络连接和设备状态';
    
    if (timeout!.inMilliseconds < 5000) {
      return '当前超时时间较短(${timeout!.inMilliseconds}ms)，建议增加到10秒以上';
    } else if (timeout!.inMilliseconds > 60000) {
      return '当前超时时间较长(${timeout!.inMilliseconds}ms)，建议检查网络连接';
    }
    
    return '请检查网络连接、设备状态和服务端配置';
  }
}

/// ADB设备异常
class AdbDeviceException implements Exception {
  final String message;
  final dynamic cause;
  final String? deviceId;

  AdbDeviceException(this.message, [this.cause, this.deviceId]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbDeviceException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    if (deviceId != null) {
      buffer.write(' (device: $deviceId)');
    }
    return buffer.toString();
  }
}

/// ADB证书异常
class AdbCertificateException implements Exception {
  final String message;
  final dynamic cause;

  AdbCertificateException(this.message, [this.cause]);

  @override
  String toString() =>
      'AdbCertificateException: $message${cause != null ? ' (caused by: $cause)' : ''}';
}

/// 异常工具类
class ExceptionUtils {
  /// 包装异常为ADB异常
  static Exception wrapException(
    dynamic error,
    String context, [
    String? details,
  ]) {
    final message = details != null ? '$context: $details' : context;

    if (error is SocketException) {
      return AdbConnectionException(
        message,
        error,
        error.address?.host,
        error.port,
      );
    } else if (error is TimeoutException) {
      return AdbTimeoutException(message, error.duration);
    } else if (error is IOException) {
      return AdbConnectionException(message, error);
    } else if (error is StateError) {
      return AdbStreamClosedException(message, error);
    } else if (error is Exception) {
      return error; // 已经是异常类型
    } else {
      return Exception('$message (caused by: $error)');
    }
  }

  /// 检查是否为可恢复的错误
  static bool isRecoverableError(dynamic error) {
    if (error is SocketException) {
      return error.osError?.errorCode == 104 || // Connection reset by peer
          error.osError?.errorCode == 111 || // Connection refused
          error.osError?.errorCode == 113; // No route to host
    }
    return false;
  }

  /// 获取错误代码
  static int? getErrorCode(dynamic error) {
    if (error is SocketException) {
      return error.osError?.errorCode;
    } else if (error is AdbConnectionException) {
      if (error.cause is SocketException) {
        return (error.cause as SocketException).osError?.errorCode;
      }
    }
    return null;
  }

  /// 格式化错误消息
  static String formatErrorMessage(dynamic error, [StackTrace? stackTrace]) {
    final buffer = StringBuffer();
    buffer.writeln('错误: $error');

    if (stackTrace != null) {
      buffer.writeln('堆栈跟踪:');
      buffer.writeln(stackTrace.toString());
    }

    return buffer.toString();
  }
}
