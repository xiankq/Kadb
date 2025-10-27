import 'dart:io';
import 'dart:async';

/// ADB连接异常
class AdbConnectionException implements Exception {
  final String message;
  final dynamic cause;
  final String? host;
  final int? port;

  AdbConnectionException(this.message, [this.cause, this.host, this.port]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbConnectionException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    if (host != null && port != null) {
      buffer.write(' ($host:$port)');
    }
    return buffer.toString();
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

  AdbProtocolException(
    this.message, [
    this.cause,
    this.command,
    this.arg0,
    this.arg1,
  ]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbProtocolException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    if (command != null) {
      buffer.write(' (command: 0x${command!.toRadixString(16)})');
    }
    if (arg0 != null) {
      buffer.write(' (arg0: $arg0)');
    }
    if (arg1 != null) {
      buffer.write(' (arg1: $arg1)');
    }
    return buffer.toString();
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

  AdbTimeoutException(this.message, [this.timeout]);

  @override
  String toString() {
    final buffer = StringBuffer('AdbTimeoutException: $message');
    if (timeout != null) {
      buffer.write(' (timeout: ${timeout!.inMilliseconds}ms)');
    }
    return buffer.toString();
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
