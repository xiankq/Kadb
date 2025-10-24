/// Shell命令响应类
/// 封装Shell命令执行的输出结果
class AdbShellResponse {
  /// 标准输出
  final String output;

  /// 错误输出
  final String errorOutput;

  /// 退出码
  final int exitCode;

  /// 构造函数
  AdbShellResponse(this.output, this.errorOutput, this.exitCode);

  /// 获取所有输出（标准输出 + 错误输出）
  String get allOutput => '$output$errorOutput';

  @override
  String toString() => 'Shell响应 ($exitCode):\n$allOutput';
}
