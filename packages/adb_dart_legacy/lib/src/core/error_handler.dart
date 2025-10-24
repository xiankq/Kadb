import 'dart:async';
import 'dart:io';
import '../utils/logging.dart';

/// ADB异常基类
class AdbException implements Exception {
  final String message;
  final dynamic originalError;

  AdbException(this.message, {this.originalError});

  @override
  String toString() => 'AdbException: $message';
}

/// 连接错误异常
class AdbConnectionException extends AdbException {
  AdbConnectionException(super.message, {super.originalError});
}

/// 认证错误异常
class AdbAuthenticationException extends AdbException {
  AdbAuthenticationException(super.message, {super.originalError});
}

/// 协议错误异常
class AdbProtocolException extends AdbException {
  AdbProtocolException(super.message, {super.originalError});
}

/// 超时错误异常
class AdbTimeoutException extends AdbException {
  AdbTimeoutException(super.message, {super.originalError});
}

/// 错误处理函数
AdbException handleError(dynamic error, {String? context}) {
  final errorStr = error.toString().toLowerCase();
  final contextStr = context != null ? ' [$context]' : '';

  // 连接错误
  if (error is SocketException ||
      errorStr.contains('connection') ||
      errorStr.contains('refused')) {
    return AdbConnectionException(
      '连接错误$contextStr: $error',
      originalError: error,
    );
  }

  // 认证错误
  if (errorStr.contains('auth') || errorStr.contains('certificate')) {
    return AdbAuthenticationException(
      '认证错误$contextStr: $error',
      originalError: error,
    );
  }

  // 协议错误
  if (errorStr.contains('protocol') || errorStr.contains('message')) {
    return AdbProtocolException(
      '协议错误$contextStr: $error',
      originalError: error,
    );
  }

  // 超时错误
  if (error is TimeoutException || errorStr.contains('timeout')) {
    return AdbTimeoutException('操作超时$contextStr: $error', originalError: error);
  }

  // 其他错误
  return AdbException('未知错误$contextStr: $error', originalError: error);
}

/// 错误处理装饰器函数
Future<T> withErrorHandling<T>(
  Future<T> Function() operation, {
  String? context,
}) async {
  try {
    return await operation();
  } catch (error) {
    final exception = handleError(error, context: context);
    Logging.error('操作失败: ${exception.message}');
    throw exception;
  }
}
