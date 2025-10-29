/// Shell命令响应类
/// 封装Shell命令的执行结果
library shell_response;

/// Shell命令响应
class AdbShellResponse {
  /// 标准输出内容
  final String output;

  /// 标准错误输出内容
  final String errorOutput;

  /// 退出码
  final int exitCode;

  /// 所有输出内容（标准输出 + 标准错误）
  late final String allOutput = '$output$errorOutput';

  AdbShellResponse({
    required this.output,
    required this.errorOutput,
    required this.exitCode,
  });

  /// 是否成功执行（退出码为0）
  bool get isSuccess => exitCode == 0;

  /// 是否失败（退出码非0）
  bool get isFailure => exitCode != 0;

  @override
  String toString() => 'Shell response ($exitCode):\n$allOutput';
}

/// Shell响应构建器
class AdbShellResponseBuilder {
  final StringBuffer _output = StringBuffer();
  final StringBuffer _errorOutput = StringBuffer();
  int _exitCode = -1;

  /// 添加标准输出
  void addOutput(String text) {
    _output.write(text);
  }

  /// 添加标准错误输出
  void addErrorOutput(String text) {
    _errorOutput.write(text);
  }

  /// 设置退出码
  void setExitCode(int code) {
    _exitCode = code;
  }

  /// 构建响应对象
  AdbShellResponse build() {
    return AdbShellResponse(
      output: _output.toString(),
      errorOutput: _errorOutput.toString(),
      exitCode: _exitCode,
    );
  }
}
