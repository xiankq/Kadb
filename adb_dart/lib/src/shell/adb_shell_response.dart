/*
 * Dart ADB 实现
 * 基于Kadb项目移植的纯Dart ADB客户端库
 */

/// ADB Shell命令执行结果
class AdbShellResponse {
  final String stdout;
  final String stderr;
  final int exitCode;

  AdbShellResponse({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  /// 获取所有输出（stdout + stderr）
  String get allOutput => stdout + stderr;

  /// 检查命令是否成功执行
  bool get isSuccess => exitCode == 0;

  @override
  String toString() {
    return 'AdbShellResponse(exitCode: $exitCode, stdout: "${stdout.trim()}", stderr: "${stderr.trim()}")';
  }
}
